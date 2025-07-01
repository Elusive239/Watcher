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
	int inotify_fd @if(env::LINUX); // fd == file descriptor (a common UNIX thing)
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
	Win32_OVERLAPPED overlapped @if(env::WIN32);
	char    *event_buffer @if(env::WIN32);
	
	int inotify_watch_fd @if(env::LINUX);
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

macro todo(String $str = "") {
	$if  $str.len > 0:
	unreachable("TODO(%s): %s (%s)", $str , $$FUNC, env::OS_TYPE);
	$else
	unreachable("TODO: %s (%s)", $$FUNC, env::OS_TYPE);
	$endif
}

fn XWatcher *xcreate() {

	XWatcher *watcher = mem::new(XWatcher);
	watcher.directories.init(mem);

	$if env::LINUX : 
		// NEED INOTIFY
		watcher.inotify_fd = inotify_init1(O_NONBLOCK);
		if(watcher.inotify_fd < 0) {
			io::eprintn("inotify_init");
			return null;
		}
	$endif
	return watcher;
}

fn bool xappend_reference(XWatcher* watcher, XWatcherReference* reference) {
	Path? path = reference.path.str_view().to_path(mem);
	defer (void) path.free();
	if(catch err = path) {
		io::eprintfn("Error: %s", err);
		return false;
	}

	if(path::is_dir(path)){
		return xappend_directory(watcher,reference);
	}else if (path::is_file(path)){
		// todo("I'm working on it, m'kay?");
		return xappend_file     (watcher,reference);
	}

	return false;
}

fn bool xappend_file     (XWatcher* watcher, XWatcherReference* reference) {
	String path = reference.path.str_view().copy(mem);
	//don't need to check for front slash here.. presumably...

	String filename;

	// we need to split the filename and path
	for(usz i = path.len-1; i > 0; i--) {
		if(path[i] == DIRBRK) {
			filename = path[i..path.len-1].copy(mem); // set the rest of it as the filename
			filename[0..filename.len-2] = filename[1..filename.len-1];
			filename[filename.len-1] = 0;
			path  = path[0..i+1]; // break the string, so it splits into two
			path [i+1] = 0;
			break;
		}
	}

	// If the directory is specifically local, treat it as such.
	if(filename.len == 0) {
		filename = path;
	}

	XWatcherDirectory* dir = watcher.fetch_directory(path);

	// directory exists, check if an callback has been already added
	if(!dir) {
		dir = mem::new(XWatcherDirectory);
		dir.callback_func   =null; 
		dir.context         =0 ;
		dir.additional_data =null;
		dir.path= (ZString) path;
		$switch:
			$case env::LINUX :
				dir.inotify_watch_fd = -1;
			$case env::WIN32 :
				dir.handle       = null;
			$default:
				todo("This playform is currently unsupported...");
		$endswitch
		dir.files.init(mem);
		watcher.directories.push(dir);
	}

	// search for the file
	XWatcherFile *file = null;
	for(usz i = 0; i < dir.files.len(); i++) {
		if(dir.files[i].name == filename) {
			file = dir.files[i];
		}
	}

	if(file != null) {
		io::eprintfn("File %s already exists!",filename);
		return false; // file already exists, that's an ERROR
	}

	XWatcherFile* new_file = mem::new(XWatcherFile);
	// avoid an invalid free because this shares the memory space
	// of the full path string
	new_file.name            = (ZString) filename.copy(mem);
	new_file.context         = reference.context;
	new_file.additional_data = reference.additional_data;
	new_file.callback_func   = reference.callback_func;

	dir.files.push(new_file);
	file = new_file;

	$switch:
			$case env::LINUX :
				if(!dir.inotify_add_watch()) return false;
			$case env::WIN32 :
				if(!dir.createFile()) return false;

				if(!dir.create_event()) return false;

				if(!dir.allocate_event_buffer()) return false;

				if(!dir.set_reading_params()) return false;

			$default:
				todo("This playform is currently unsupported...");
		$endswitch

	return true;	
}

fn bool xappend_directory(XWatcher* watcher, XWatcherReference* reference) {
	String path = reference.path.str_view().copy(mem);
	
	// inotify only works with directories that do NOT have a front-slash
	// at the end, so we have to make sure to cut that out
	if(path[path.len-1] == DIRBRK) path[path.len-1] = '\0';

	XWatcherDirectory* dir = watcher.fetch_directory(path);

	// directory exists, check if an callback has been already added
	if(dir) {
		// ERROR, CALLBACK EXISTS
		if(dir.callback_func) {
			io::eprintn("ERROR, CALLBACK EXISTS!");
			return false;
		}


		dir.init_with_reference(reference);
	} else{
		dir = mem::new(XWatcherDirectory);

		dir.path = (ZString)path;
		dir.init_with_reference(reference);
		dir.files.init(mem);
		$switch:
			$case env::LINUX :
				if(!dir.inotify_add_watch()) return false;
			$case env::WIN32 :
				if(!dir.createFile()) return false;
				if(!dir.create_event()) return false;
				if(!dir.allocate_event_buffer()) return false;
				if(!dir.set_reading_params()) return false;
			$default:
				todo("This playform is currently unsupported...");
		$endswitch
		watcher.directories.push(dir);
	}

	return true;
}

macro bool XWatcherDirectory.createFile(&dir) {
	// add directory path
	dir.handle = win32::createFileA(
			(ichar*)dir.path, //probably unsafe....
			FILE_LIST_DIRECTORY,
			FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
			null,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
			null);
	if(dir.handle == win32::INVALID_HANDLE_VALUE) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("CreateFile failed: Windows Error %d\n", error);
		return false;
	}
	return true;
}

macro void XWatcherDirectory.init_with_reference(&dir, XWatcherReference* reference) {
	dir.callback_func   = reference.callback_func;
	dir.context         = reference.context;
	dir.additional_data = reference.additional_data;
}

macro bool XWatcherDirectory.inotify_add_watch(&dir) {
	dir.inotify_watch_fd = inotify::inotify_add_watch( watcher.inotify_fd, dir.path, IN_ALL_EVENTS);
	if(dir.inotify_watch_fd == -1) {
		io::eprintn("inotify_watch_fd -1, failed to add dir to inotify!");
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.create_event(&dir) {
	// create event structure
	dir.overlapped.hEvent = win32::createEventA(null, (Win32_BOOL) false, 0, null);
	if(dir.overlapped.hEvent == null) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("CreateEvent failed: Windows Error %d\n",error);
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.allocate_event_buffer(&dir) {
	// allocate the event buffer
	dir.event_buffer = calloc(BUF_LEN);
	if(dir.event_buffer == null) {
		io::eprintf( "calloc failed at %s:$s!\n", $$FILE, $$LINE);
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.set_reading_params(&dir) {
	// set reading params
	bool success = (bool) readDirectoryChangesW(
			dir.handle, dir.event_buffer, BUF_LEN, (Win32_BOOL) true,
			FILE_NOTIFY_CHANGE_FILE_NAME  |
			FILE_NOTIFY_CHANGE_DIR_NAME   |
			FILE_NOTIFY_CHANGE_LAST_WRITE,
			null, &dir.overlapped, null);
	if(!success) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("ReadDirectoryChangesW failed: %d\n", error);
	}
	return success;
}

fn XWatcherDirectory* XWatcher.fetch_directory(XWatcher* watcher, String path) {
	XWatcherDirectory* dir = null;
	// check against the database of (pre-existing) directories
	for(usz i=0; i < watcher.directories.len(); i++) {
		// paths match
		if(watcher.directories[i].path == path) dir = watcher.directories[i];
	}
	return dir;
}

fn bool xstart(XWatcher* watcher) {
	watcher.alive = true;
	
	watcher.thread_id.create(&internal_xwatcher_process, watcher)!!;
	
	if(watcher.thread_id == (Thread)0) {
		io::eprint("couldn't create a new thread...");
		watcher.alive = false;
		return false;
	}
	io::printfn("thread created...");
	return true;
}

fn void xdestroy(XWatcher* watcher) {
	watcher.alive = false;
	if(catch err = watcher.thread_id.join()) err?!!;
	if(watcher) mem::free(watcher);
	io::printfn("watcher destroyed...");
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
  Win32_WCHAR[1] fileName;
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


fn int internal_xwatcher_process(void *argument) {
	XWatcher* watcher = (XWatcher*) argument;
	XWatcherDirectory*[] directories = watcher.directories.array_view();

	// create an event list so we can still make use of the Windows API
	Win32_PHANDLE[] events = allocator::new_array(mem, Win32_PHANDLE, directories.len);
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
		XWatcherDirectory *dir = directories[object_index];
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
		tmp.init(mem);
		@pool_init(mem, BUF_LEN, BUF_LEN){ 
		for (;;)  {
			defer tmp.clear();
			String converted_name = string::from_wstring(mem, (WString) &(event.fileName[0]))!!;
			tmp.append(converted_name);
			converted_name.free(mem);
			tmp.append_char('\0'); //null terminate!

			ZString name_char = (ZString) (tmp.str_view().ptr);
			usz converted_chars = tmp.str_view().len;

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
				if(dir.files[j].name == name_char ) {
					file = dir.files[j];
				}
			}

			// file found(?)
			if(file != null) {
				if(send_event != XWatcherFileEvent.NONE) {
					// figure out the file path size
					usz filepath_size = dir.path.len() + file.name.len() + 2;
					// create file path string
					char *filepath = (char*)mem::malloc(filepath_size);
					defer mem::free(filepath); // free that garbage
					libc::snprintf(filepath, filepath_size, "%s%c%s",
							dir.path, DIRBRK, file.name);
					// callback
					file.callback_func(send_event,
										(ZString)filepath,
										file.context,
										file.additional_data);
				}
			}else {
				// Cannot find file, lets try directory
				if(dir.callback_func != null &&
						send_event != XWatcherFileEvent.NONE) {
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
		}};
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
	}
	//cleanup here (TBD)... arena allocator looking nice rn..
	for(usz i = 0; i < watcher.directories.len(); i++) {
		XWatcherDirectory *directory = watcher.directories[i];
		win32::closeHandle(directory.handle);
	}
	return 0;
}

module xwatcher @if(env::LINUX);
import std::os::posix;
import inotify;

const CInt EVENT_SIZE  = (INotifyEvent.sizeof);
const CInt BUF_LEN     = (1024 * (EVENT_SIZE + 16));
const char DIRBRK      = '/';
