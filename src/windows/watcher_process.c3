module watcher @if(env::WIN32);
import std::os::win32;
import std::io;

const CInt BUF_LEN     = 1024;
const char DIRBRK      = '\\';

fn int internal_watcher_process(void *argument) {
	Watcher* watcher = (Watcher*) argument;
	WatcherDirectory*[] directories = watcher.directories.array_view();

	// create an event list so we can still make use of the Windows API
    @pool_init(mem, BUF_LEN, BUF_LEN){ 

	Win32_PHANDLE[] events = allocator::new_array(tmem, Win32_PHANDLE, directories.len);
	for(usz i = 0; i < directories.len; i++) {
		events[i] = directories[i].overlapped.hEvent;
	}

	while(watcher.alive) {
		// wait for any of the objects to respond
		Win32_DWORD result = win32::waitForMultipleObjects(
			directories.len,
			events, 
			(Win32_BOOL)false, 
			50 /* timeout of 50ms */
		);

		// test which object was it
		int object_index = -1;
		for(int i = 0; i < directories.len; i++) {
			if(result == (win32::WAIT_OBJECT_0 + i)) {
				object_index = i;
				break;
			}
		}

		if(object_index == -1) {
			if(result == win32::WAIT_TIMEOUT) {
				// it just timed out, let's continue
					//me-> maybe we yield?
				continue;
			} else {
				// RUNTIME ERROR! Let's bail
				io::printfn("Runtime Error! Bailing!");
				win32::exitThread(win32::getLastError());
			}
		}

		// shorhand for convenience
		WatcherDirectory *dir = directories[object_index];
		// retrieve event data
		Win32_DWORD bytes_transferred;
		win32::getOverlappedResult(
			dir.handle,
			&dir.overlapped,
			&bytes_transferred, 
			(Win32_BOOL)false
		);

		// assign the data's pointer to a proper format for convenience
		FileNotifyInformation *event = (FileNotifyInformation*) dir.event_buffer;

		// loop through the data
		DString tmp;
		tmp.init(tmem);
		for (;;)  {
			defer tmp.clear();
			String converted_name = string::from_wstring(tmem, (WString) &(event.fileName[0]))!!;
			tmp.append(converted_name);
			converted_name.free(tmem);
			tmp.append_char('\0'); //null terminate!

			ZString name_char = (ZString) (tmp.str_view().ptr);
			usz converted_chars = tmp.str_view().len-1; //account for null terminator

			// convert to proper event type
			WatcherFileEvent send_event = WatcherFileEvent.NONE;
			switch (event.action) {
				case FILE_ACTION_ADDED:
					send_event = WatcherFileEvent.CREATED;
					break;
				case FILE_ACTION_REMOVED:
					send_event = WatcherFileEvent.REMOVED;
					break;
				case FILE_ACTION_MODIFIED:
					send_event = WatcherFileEvent.MODIFIED;
					break;
				case FILE_ACTION_RENAMED_OLD_NAME:
				case FILE_ACTION_RENAMED_NEW_NAME:
					send_event = WatcherFileEvent.RENAMED;
					break;
				default:
					send_event = WatcherFileEvent.UNSPECIFIED;
					break;
			}

			// find matching file (if any)
			WatcherFile *file = null;
			for(usz j = 0; j < dir.files.len(); j++) {
				usz test_file_name_len = dir.files[j].name.len();
				if(converted_chars != test_file_name_len) {continue;}
				else if(dir.files[j].name[0:test_file_name_len] == name_char[0:test_file_name_len] ) {
					file = dir.files[j];
					break;
				}
			}

			// file found(?)
			if(file != null) {
				if(send_event != WatcherFileEvent.NONE) @pool() {
                    DString filepath;
                    filepath.init(tmem);
                    filepath.appendf("%s%c%s", dir.path, DIRBRK, file.name);

					// callback
					file.callback_func(send_event,
										(ZString)(filepath.zstr_view()),
										file.context,
										file.additional_data);
				};
			}else {
				io::printfn("FILE IS NULL? Expected '%s' Found: '%s'", name_char, dir.files.array_view());
				// Cannot find file, lets try directory
				if(dir.callback_func != null &&
						send_event != WatcherFileEvent.NONE) {
					dir.callback_func(
						send_event,
						dir.path,
						dir.context,
						dir.additional_data
					);
				}
			}
			// Are there more events to handle?
			if (event.nextEntryOffset) {
				*((char**)&event) += event.nextEntryOffset;
			} else {
				break;
			}
		}
		Win32_DWORD dwNotifyFilter =
			FILE_NOTIFY_CHANGE_FILE_NAME |
			FILE_NOTIFY_CHANGE_DIR_NAME |
			FILE_NOTIFY_CHANGE_ATTRIBUTES |
			FILE_NOTIFY_CHANGE_SIZE |
			FILE_NOTIFY_CHANGE_LAST_WRITE |
			FILE_NOTIFY_CHANGE_LAST_ACCESS |
			FILE_NOTIFY_CHANGE_CREATION |
			FILE_NOTIFY_CHANGE_SECURITY;
		bool recursive = false;

		// Queue the next event
		bool success = (bool) readDirectoryChangesW(
			dir.handle,
			dir.event_buffer,
			BUF_LEN,
			(Win32_BOOL)recursive,
			dwNotifyFilter,
			null,
			&dir.overlapped,
			null
		);
		if(!success) {
			// get error code
			Win32_DWORD error = win32::getLastError();
			io::eprintf("readDirectoryChangesW failed: %d\n", error);
			win32::exitThread(error);
		}
	}};
	//cleanup here (TBD)... arena allocator looking nice rn..
	for(usz i = 0; i < watcher.directories.len(); i++) {
		WatcherDirectory *directory = watcher.directories[i];
		win32::closeHandle(directory.handle);
	}
	return 0;
}
