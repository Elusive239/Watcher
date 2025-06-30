module xwatcher;
import std::collections;
import std::io;
import libc;
import std::os::win32;
import std::os::posix;
import std::thread;

alias PThread @if(!$defined(PThread)) = void*;

alias XWatcherCallbackFn = fn void( XWatcherFileEvent event, ZString path, int context, void* additional_data);

enum XWatcherFileEvent : char {
	UNSPECIFIED,
	REMOVED,
	CREATED,
	MODIFIED,
	OPENED,
	ATTRIBUTES_CHANGED,
	NONE,
	RENAMED,
	// probs more but i couldn't care much
}

struct XWatcher {
	XWatcherDirectoryList directories;
	PThread  thread;
	Thread        thread_id;
	bool       alive;
	int inotify_fd @if(env::POSIX); // fd == file descriptor (a common UNIX thing)
}

struct XWatcherDirectory {
	// list of files
	XWatcherFileList files;

	ZString         path;
	// used for adding (additional) context in the handler (if needed)
	int            context;
	// in case you'd like to avoid global variables
	void          *additional_data;

	XWatcherCallbackFn callback_func;

	Win32_PHANDLE     handle @if(env::WIN32);
	Win32_LPOVERLAPPED overlapped @if(env::WIN32);
	char    *event_buffer @if(env::WIN32);
	
	int inotify_watch_fd @if(env::POSIX);
}

fn void free_xdirectory(XWatcherDirectory* reference) { 
	mem::free(reference.path);
	foreach (file : reference.files) {
		mem::free(file);
	}
	reference.files.free();
	if(reference.additional_data) mem::free(reference.additional_data);
	mem::free(reference);
}


struct XWatcherReference {
	ZString path;
	XWatcherCallbackFn callback_func;
	int context;
	void *additional_data;
}

fn void free_xreference(XWatcherReference* reference){
	mem::free(reference.path);
	if(reference.additional_data) mem::free(reference.additional_data);
	mem::free(reference);
}

struct XWatcherFile {
	// just the file name alone
	ZString name;
	// used for adding (additional) context in the handler (if needed)
	int  context;
	// in case you'd like to avoid global variables
	void *additional_data;

	XWatcherCallbackFn callback_func;
}

fn void free_xfile_reference(XWatcherFile* file){
	mem::free(file.name);
	if(file.additional_data) mem::free(file.additional_data);
	mem::free(file);
}

macro todo(){
	unreachable("TODO: %s (%s)", $$FUNC, env::OS_TYPE);
}

fn XWatcher *xcreate() {

	XWatcher *watcher = mem::new(XWatcher);
	watcher.directories.init(mem);

	$if env::POSIX : 
		// NEED INOTIFY
		// watcher.inotify_fd = inotify_init1(O_NONBLOCK);
		if(watcher.inotify_fd < 0) {
			io::eprintn("inotify_init");
			return null;
		}
	$endif
	return watcher;
}

fn bool xappend_file(XWatcher* watcher, XWatcherReference* reference) {
	char *path = allocator::new_array(mem, char, reference.path.len());
	foreach(idx, char c : reference.path[: reference.path.len()]){
		path[idx] = c;
	}
	// libc::strdup(reference.path);

	// the file MUST NOT contain slashed at the end
	if(path[libc::strlen((ZString)path)-1] == DIRBRK) return false;

	char *filename = null;

	// we need to split the filename and path
	for(int i = (int) libc::strlen((ZString)path)-1; i > 0; i--) {
		if(path[i] == DIRBRK) {
			path[i]  = '\0'; // break the string, so it splits into two
			filename = &path[i+1]; // set the rest of it as the filename
			break;
		}
	}

	// If the directory is specifically local, treat it as such.
	if(filename == null) {
		filename = path;
	}

	XWatcherDirectory *dir = null;

	// check against the database of (pre-existing) directories
	for(int i = 0; i < watcher.directories.len(); i++) {
		// paths match
		if(libc::strcmp(watcher.directories[i].path, (ZString) path) == 0) {
			dir = watcher.directories[i];
		}
	}

	// directory exists, check if an callback has been already added
	if(dir == null) {
		XWatcherDirectory* new_dir = mem::new(XWatcherDirectory);

		new_dir.callback_func    = null; // DO NOT add callbacks if it's a file
		new_dir.context          = 0;    // context should be invalid as well
		new_dir.additional_data  = null; // so should the data
		new_dir.path             = (ZString) path; // add a path to the directory
		$if env::POSIX:
			new_dir.inotify_watch_fd = -1;   // invalidate inotify
		$endif
		$if env::WIN32:
			new_dir.handle       = null;
		$endif

		// initialize file arrays
		new_dir.files.init(mem);

		// add the directory to the masses
		watcher.directories.push(new_dir);
		// arr_add(watcher.directories, new_dir);

		// move the pointer to the newly added element
		dir = watcher.directories[watcher.directories.len()-1];
	}

	// search for the file
	XWatcherFile *file = null;
	for(int i = 0; i < dir.files.len(); i++) {
		if(libc::strcmp(dir.files[i].name, (ZString)filename) == 0) {
			file = dir.files[i];
		}
	}
	return true;
	// todo();
}

fn bool xappend_directory(XWatcher* watcher, XWatcherReference* reference) {
	char *path = allocator::new_array(mem, char, reference.path.len());
	foreach(idx, char c : reference.path[: reference.path.len()]){
		path[idx] = c;
	}
	// libc::strdup(reference.path);

	// the file MUST NOT contain slashed at the end
	if(path[libc::strlen((ZString)path)-1] == DIRBRK) return false;
	XWatcherDirectory *dir = null;

	// check against the database of (pre-existing) directories
	for(int i=0; i < watcher.directories.len(); i++) {
		// paths match
		if(libc::strcmp(watcher.directories[i].path, (ZString)path) == 0) {
			dir = watcher.directories[i];
		}
	}

	// directory exists, check if an callback has been already added
	if(dir) {
		// ERROR, CALLBACK EXISTS
		if(dir.callback_func) {
			return false;
		}

		dir.callback_func   = reference.callback_func;
		dir.context         = reference.context;
		dir.additional_data = reference.additional_data;
	} else {
		// keep an eye for this one as it's on the stack
		dir = mem::new(XWatcherDirectory);

		dir.path = (ZString)path;
		dir.callback_func   = reference.callback_func;
		dir.context         = reference.context;
		dir.additional_data = reference.additional_data;

		// initialize file arrays
		// arr_init(dir.files);
		dir.files.init(mem);

		$if env::POSIX:
			dir.inotify_watch_fd = inotify_add_watch(
					watcher.inotify_fd,
					dir.path,
					IN_ALL_EVENTS);
			if(dir.inotify_watch_fd == -1) {
				perror("inotify_watch_fd");
				return false;
			}
		$endif
		$if env::WIN32:
			// add directory path
			dir.handle = win32::createFileA((Win32_LPCSTR)dir.path,
					FILE_LIST_DIRECTORY,
					FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
					null,
					OPEN_EXISTING,
					FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
					null);
			if(dir.handle == win32::INVALID_HANDLE_VALUE) {
				// get error code
				Win32_DWORD error = win32::getLastError();
				// char *message;

				// get error message
				// FormatMessage(
				// 	FORMAT_MESSAGE_ALLOCATE_BUFFER |
				// 	FORMAT_MESSAGE_FROM_SYSTEM |
				// 	FORMAT_MESSAGE_IGNORE_INSERTS,
				// 	null,
				// 	error,
				// 	MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
				// 	(LPTSTR) &message,
				// 	0, null);

				io::eprintf("CreateFile failed: %d\n",
						error);

				return false;
			}

			// create event structure
			dir.overlapped.hEvent = win32::createEventA(null, (Win32_BOOL)false, 0, null);
			if(dir.overlapped.hEvent == null) {
				// get error code
				Win32_DWORD error = win32::getLastError();
				// char *message;

				// get error message
				// FormatMessage(
				// 	FORMAT_MESSAGE_ALLOCATE_BUFFER |
				// 	FORMAT_MESSAGE_FROM_SYSTEM |
				// 	FORMAT_MESSAGE_IGNORE_INSERTS,
				// 	null,
				// 	error,
				// 	MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
				// 	(Win32LPSTR) &message,
				// 	0, null);

					io::eprintf("CreateEvent failed: %d\n",
						error);

				return false;
			}

			// allocate the event buffer
			dir.event_buffer = mem::malloc(BUF_LEN);
			if(dir.event_buffer == null) {
				io::eprintf( "malloc failed at __FILE__:__LINE__!\n");
				return false;
			}

			// set reading params
			bool success = (bool) readDirectoryChangesW(
					dir.handle, dir.event_buffer, BUF_LEN,  (Win32_BOOL) true,
					FILE_NOTIFY_CHANGE_FILE_NAME  |
					FILE_NOTIFY_CHANGE_DIR_NAME   |
					FILE_NOTIFY_CHANGE_LAST_WRITE,
					null, dir.overlapped, null);
			if(!success) {
				// get error code
				Win32_DWORD error = win32::getLastError();
				// char *message;

				// get error message
				// FormatMessage(
				// 	FORMAT_MESSAGE_ALLOCATE_BUFFER |
				// 	FORMAT_MESSAGE_FROM_SYSTEM |
				// 	FORMAT_MESSAGE_IGNORE_INSERTS,
				// 	null,
				// 	error,
				// 	MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
				// 	(LPTSTR) &message,
				// 	0, null);

				io::eprintf("ReadDirectoryChangesW failed: %d\n",
						error);

				return false;
			}
		$endif
		watcher.directories.push(dir);
		// arr_add(watcher->directories, dir);
	}

	return true;
	// todo();
}

fn bool xstart(XWatcher* watcher) {
	watcher.alive = true;
	watcher.thread_id = (Thread)1;
	(void) watcher.thread_id.create(&internal_xWatcherProcess, watcher);
	
	// possix::pthread_create(
	// 		&watcher.thread,
	// 		NULL,
	// 		&internal_xWatcherProcess,
	// 		watcher);
	
	if(watcher.thread_id != (Thread)0) {
		io::eprint("pthread_create");
		watcher.alive = false;
		return false;
	}

	return true;
}

fn void xdestroy(XWatcher* watcher) {
	// void *ret;
	watcher.alive = false;
	// $if env::POSIX : 
	// 	posix::pthread_join(watcher.thread, &ret);
	// $endif
	(void) watcher.thread_id.join();
	foreach(dir : watcher.directories){
		free_xdirectory(dir);
	}
	watcher.directories.free();
	mem::free(watcher);
}

alias XWatcherFileList = list::List{XWatcherFile*};
alias XWatcherDirectoryList = list::List{XWatcherDirectory*};

module xwatcher @if(env::WIN32);
import std::os::win32;
import libc;
import std::io;


//Winnt.h // https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-file_notify_information
struct FileNotifyInformation {
  Win32_DWORD nextEntryOffset;
  Win32_DWORD action;
  Win32_DWORD fileNameLength;
  Win32_WCHAR* fileName;
} 

const CUInt FILE_ACTION_ADDED            = 0x00000001;
const CUInt FILE_ACTION_REMOVED          = 0x00000002;
const CUInt FILE_ACTION_MODIFIED         = 0x00000003;
const CUInt FILE_ACTION_RENAMED_OLD_NAME = 0x00000004;
const CUInt FILE_ACTION_RENAMED_NEW_NAME = 0x00000005;

//Winbase.h
const CUInt FILE_NOTIFY_CHANGE_FILE_NAME   = 0x00000001;
const CUInt FILE_NOTIFY_CHANGE_DIR_NAME    = 0x00000002;
const CUInt FILE_NOTIFY_CHANGE_ATTRIBUTES  = 0x00000004;
const CUInt FILE_NOTIFY_CHANGE_SIZE        = 0x00000008;
const CUInt FILE_NOTIFY_CHANGE_LAST_WRITE  = 0x00000010;
const CUInt FILE_NOTIFY_CHANGE_LAST_ACCESS = 0x00000020;
const CUInt FILE_NOTIFY_CHANGE_CREATION    = 0x00000040;
const CUInt FILE_NOTIFY_CHANGE_SECURITY    = 0x00000100;

// https://learn.microsoft.com/en-us/windows/win32/fileio/file-access-rights-constants
const CUInt FILE_LIST_DIRECTORY = 1;

const CUInt FILE_SHARE_DELETE = 0x00000004;
const CUInt FILE_SHARE_READ   = 0x00000001;
const CUInt FILE_SHARE_WRITE  = 0x00000002;

const CUInt CREATE_ALWAYS     = 2;
const CUInt CREATE_NEW        = 1;
const CUInt OPEN_ALWAYS       = 4;
const CUInt OPEN_EXISTING     = 3;
const CUInt TRUNCATE_EXISTING = 5;

const CUInt FILE_FLAG_BACKUP_SEMANTICS  = 0x02000000;
const CUInt FILE_FLAG_DELETE_ON_CLOSE   = 0x04000000;
const CUInt FILE_FLAG_NO_BUFFERING      = 0x20000000;
const CUInt FILE_FLAG_OPEN_NO_RECALL    = 0x00100000;
const CUInt FILE_FLAG_OPEN_REPARSE_POINT= 0x00200000;
const CUInt FILE_FLAG_OVERLAPPED        = 0x40000000;
const CUInt FILE_FLAG_POSIX_SEMANTICS   = 0x01000000;
const CUInt FILE_FLAG_RANDOM_ACCESS     = 0x10000000;
const CUInt FILE_FLAG_SESSION_AWARE     = 0x00800000;
const CUInt FILE_FLAG_SEQUENTIAL_SCAN   = 0x08000000;
const CUInt FILE_FLAG_WRITE_THROUGH     = 0x80000000;

// https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilea

//for compatibility
const CInt BUF_LEN     = 1024;
const char DIRBRK      = '\\';

// https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-readdirectorychangesw
extern fn Win32_BOOL readDirectoryChangesW(
	Win32_HANDLE, 
	Win32_LPVOID, 
	Win32_DWORD,
	Win32_BOOL,
	Win32_DWORD,
	Win32_LPDWORD,
	Win32_LPOVERLAPPED,
	void* // <- this is wrong... but what *is* 'LPOVERLAPPED_COMPLETION_ROUTINE' ?
) @extern("ReadDirectoryChangesW");

fn int internal_xWatcherProcess(void *argument) {
		XWatcher* watcher = (XWatcher*) argument;
		XWatcherDirectory*[] directories = watcher.directories.to_array(mem);

		// create an event list so we can still make use of the Windows API
		Win32_PHANDLE[] events = allocator::new_array(mem, Win32_PHANDLE, directories.len);
		for(usz i = 0; i < directories.len; i++) {
			events[i] = directories[i].overlapped.hEvent;
		}

		// obv first check if we need to stay alive
		while(watcher.alive) {
			// wait for any of the objects to respond
			Win32_DWORD result = win32::waitForMultipleObjects(directories.len,
					events, (Win32_BOOL)false, 50 );/* timeout of 50ms */

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
					continue;
				} else {
					// RUNTIME ERROR! Let's bail
					win32::exitThread(win32::getLastError());
				}
			}

			// shorhand for convenience
			XWatcherDirectory *dir = directories[object_index];

			// retrieve event data
			Win32_DWORD bytes_transferred;
			win32::getOverlappedResult(dir.handle,
					dir.overlapped,
					&bytes_transferred, (Win32_BOOL)false);

			// assign the data's pointer to a proper format for convenience
			FileNotifyInformation *event = (FileNotifyInformation*)
					dir.event_buffer;

			// loop through the data
			for (;;) {
				// figure out the wchar string size and allocate as needed
				Win32_DWORD name_len = event.fileNameLength / Win32_WCHAR.sizeof;
				// char *name_char = mem::malloc(char.sizeof*((long)name_len+1));
				// usz converted_chars;

				// // convert wchar* filename to char*
				// wcstombs_s(&converted_chars, name_char,
				// 		name_len+1, event.fileName, name_len);
				String tmp = string::from_wstring(mem, (WString) &( event.fileName[0]))!!;
				char* name_char = tmp.ptr;
				usz converted_chars = tmp.len;

				// convert to proper event type
				XWatcherFileEvent send_event = XWatcherFileEvent.NONE;
				switch (event.action) {
					case FILE_ACTION_ADDED:
						send_event = XWatcherFileEvent.CREATED;
						break;
					case FILE_ACTION_REMOVED:
						send_event = XWatcherFileEvent.REMOVED;
						break;
					case FILE_ACTION_MODIFIED:
						send_event = XWatcherFileEvent.MODIFIED;
						break;
					case FILE_ACTION_RENAMED_OLD_NAME:
					case FILE_ACTION_RENAMED_NEW_NAME:
						send_event = XWatcherFileEvent.RENAMED;
						break;
					default:
						send_event = XWatcherFileEvent.UNSPECIFIED;
						break;
				}

				// find matching file (if any)
				XWatcherFile *file = null;
				for(usz j = 0; j < dir.files.len(); j++) {
					if(libc::strcmp(dir.files[j].name, (ZString)name_char) == 0) {
						file = dir.files[j];
					}
				}

				// file found(?)
				if(file != null) {
					if(send_event != XWatcherFileEvent.NONE) {
						// figure out the file path size
						usz filepath_size = libc::strlen(dir.path);
						filepath_size += libc::strlen(file.name);
						filepath_size += 2;

						// create file path string
						char *filepath = (char*)mem::malloc(filepath_size);
						libc::snprintf(filepath, filepath_size, "%s%c%s",
								dir.path, DIRBRK, file.name);

						// callback
						file.callback_func(send_event,
											(ZString)filepath,
											file.context,
											file.additional_data);

						// free that garbage
						free(filepath);
					}
				} else {
					// Cannot find file, lets try directory
					if(dir.callback_func != null &&
							send_event != XWatcherFileEvent.NONE) {
						dir.callback_func(send_event,
								dir.path,
								dir.context,
								dir.additional_data);
					}
				}

				// free up the converted string
				mem::free(name_char);

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
					dir.overlapped,
					null);

			if(!success) {
				// get error code
				Win32_DWORD error = win32::getLastError();
				// char *message;

				// get error message
				// win32::FormatMessage(
				// 	FORMAT_MESSAGE_ALLOCATE_BUFFER |
				// 	FORMAT_MESSAGE_FROM_SYSTEM |
				// 	FORMAT_MESSAGE_IGNORE_INSERTS,
				// 	null,
				// 	error,
				// 	MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
				// 	(LPTSTR) &message,
				// 	0, null);

				io::eprintf("readDirectoryChangesW failed: %d\n",
						error);

				win32::exitThread(error);
			}
		}
		// cleanup time
		for(usz i = 0; i < watcher.directories.len(); i++) {
			XWatcherDirectory *directory = watcher.directories[i];
			for(usz j = 0; j < directory.files.len(); j++) {
				XWatcherFile *file = directory.files[j];
				mem::free(file.name);
			}
			directory.files.free();
			mem::free(directory.path);
			mem::free(directory.event_buffer);
			win32::closeHandle(directory.handle);
		}
		watcher.directories.free();
		mem::free(events);
		mem::free(directories);
		return 0;
	}


module xwatcher @if(env::POSIX);
import std::os::posix;
import inotify;

const CInt EVENT_SIZE  = (INotifyEvent.sizeof);
const CInt BUF_LEN     = (1024 * (EVENT_SIZE + 16));
const char DIRBRK      = '/';
