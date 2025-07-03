module watcher;
import std::io;
import std::thread;
import std::collections;
import std::os::win32;
import std::os::posix;
import std::net::os;
import inotify;

macro todo(String $str = "") {
	$if  $str.len > 0:
	unreachable("TODO(%s): %s (%s)", $str , $$FUNC, env::OS_TYPE);
	$else
	unreachable("TODO: %s (%s)", $$FUNC, env::OS_TYPE);
	$endif
}

alias WatcherFileList = list::List{WatcherFile*};
alias WatcherDirectoryList = list::List{WatcherDirectory*};
alias WatcherCallbackFn = fn void( WatcherFileEvent event, ZString path, int context, void* additional_data);

enum WatcherFileEvent : usz {
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

struct Watcher {
	WatcherDirectoryList directories;
	Thread        thread_id;
	bool       alive;
	int inotify_fd @if(env::LINUX); // fd == file descriptor (a common UNIX thing)
}

struct WatcherDirectory {
	// list of files
	WatcherFileList files;
	ZString         path;
	// used for adding (additional) context in the handler (if needed)
	int            context;
	// in case you'd like to avoid global variables
	void          *additional_data;

	WatcherCallbackFn callback_func;

	Win32_PHANDLE     handle @if(env::WIN32);
	Win32_OVERLAPPED overlapped @if(env::WIN32);
	char    *event_buffer @if(env::WIN32);
	
	int inotify_watch_fd @if(env::LINUX);
}

struct WatcherReference {
	ZString path;
	WatcherCallbackFn callback_func;
	int context;
	void *additional_data;
}

struct WatcherFile (Printable) {
	// just the file name alone
	ZString name;
	// used for adding (additional) context in the handler (if needed)
	int  context;
	// in case you'd like to avoid global variables
	void *additional_data;

	WatcherCallbackFn callback_func;
}

fn usz? WatcherFile.to_format(&this, Formatter *formatter) @dynamic {
	return formatter.printf("%s", this.name)!;
}

fn Watcher *create_watcher() {
	Watcher *watcher = mem::new(Watcher); 
	watcher.directories.init(mem,initial_capacity:1);

	$if env::LINUX : 
		// NEED INOTIFY
		watcher.inotify_fd = inotify::init1(os::O_NONBLOCK);
		if(watcher.inotify_fd < 0) {
			io::eprintn("inotify_init");
			return null;
		}
	$endif
	return watcher;
}

<*
	@require $typeof(path).typeid == ZString.typeid || $typeof(path).typeid == String.typeid || $defined(path.str_view)
*>
macro bool Watcher.watch(Watcher* watcher, path, WatcherCallbackFn callback_func = null, void* additional_data = null, int context = 1) {
	//back out early if the watcher is awake, prevents a crash..
	if(watcher.alive) return false;

	$if $defined(path.str_view) == true:
	WatcherReference ref = {
		.path = (ZString) path.str_view(),
		.callback_func = callback_func,
		.context = context,
		.additional_data = additional_data,
	};
	$else 
	WatcherReference ref = {
		.path = (ZString) path,
		.callback_func = callback_func,
		.context = context,
		.additional_data = additional_data,
	};
	$endif
	return append_reference(watcher, &ref);
}

fn bool append_reference(Watcher* watcher, WatcherReference* reference) {
	Path? path = reference.path.str_view().to_path(mem);
	defer (void) path.free();
	if(catch err = path) {
		io::eprintfn("Error: %s", err);
		return false;
	}

	if(path::is_dir(path)){
		return append_directory(watcher,reference);
	}else if (path::is_file(path)){
		// todo("I'm working on it, m'kay?");
		return append_file     (watcher,reference);
	}

	return false;
}

fn bool append_file     (Watcher* watcher, WatcherReference* reference) {
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

	WatcherDirectory* dir = watcher.fetch_directory(path);

	// directory exists, check if an callback has been already added
	if(!dir) {
		dir = mem::new( WatcherDirectory);
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
		dir.files.init(mem,initial_capacity:1);
		watcher.directories.push(dir);
	}

	// search for the file
	WatcherFile *file = null;
	for(usz i = 0; i < dir.files.len(); i++) {
		if(dir.files[i].name == filename) {
			file = dir.files[i];
		}
	}

	if(file != null) {
		io::eprintfn("File %s already exists!",filename);
		return false; // file already exists, that's an ERROR
	}

	WatcherFile* new_file = mem::new(WatcherFile);
	// avoid an invalid free because this shares the memory space
	// of the full path string
	new_file.name            = (ZString) filename;
	new_file.context         = reference.context;
	new_file.additional_data = reference.additional_data;
	new_file.callback_func   = reference.callback_func;

	dir.files.push(new_file);
	file = new_file;
	$switch:
			$case env::LINUX :
				if(!dir.inotify_add_watch(watcher.inotify_fd)) return false;
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

fn bool append_directory(Watcher* watcher, WatcherReference* reference) {
	String path = reference.path.str_view().copy(mem);
	
	// inotify only works with directories that do NOT have a front-slash
	// at the end, so we have to make sure to cut that out
	if(path[path.len-1] == DIRBRK) path[path.len-1] = '\0';

	WatcherDirectory* dir = watcher.fetch_directory(path);

	// directory exists, check if an callback has been already added
	if(dir) {
		// ERROR, CALLBACK EXISTS
		if(dir.callback_func) {
			io::eprintn("ERROR, CALLBACK EXISTS!");
			return false;
		}


		dir.init_with_reference(reference);
	} else{
		dir = mem::new(WatcherDirectory);

		dir.path = (ZString)path;
		dir.init_with_reference(reference);
		dir.files.init(mem, initial_capacity:1);
		$switch:
			$case env::LINUX :
				if(!dir.inotify_add_watch(watcher.inotify_fd)) return false;
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

macro void WatcherDirectory.init_with_reference(&dir, WatcherReference* reference) {
	dir.callback_func   = reference.callback_func;
	dir.context         = reference.context;
	dir.additional_data = reference.additional_data;
}

fn WatcherDirectory* Watcher.fetch_directory(Watcher* watcher, String path) {
	WatcherDirectory* dir = null;
	// check against the database of (pre-existing) directories
	for(usz i=0; i < watcher.directories.len(); i++) {
		// paths match
		if(watcher.directories[i].path == path) dir = watcher.directories[i];
	}
	return dir;
}

fn bool Watcher.start(Watcher* watcher) {
	watcher.alive = true;
	
	if(catch watcher.thread_id.create(&internal_watcher_process, watcher)) {
		io::eprint("couldn't create a new thread...");
		watcher.alive = false;
		return false;
	}

	return true;
}

fn void destroy_watcher(Watcher* watcher) {
	watcher.alive = false;
	if(catch err = watcher.thread_id.join()) err?!!;
	foreach(WatcherDirectory* dir : watcher.directories){
		foreach(WatcherFile* file : dir.files){
			mem::free(file.name);
			mem::free(file);
		}
		$if env::WIN32 :
		if(dir.event_buffer) mem::free(dir.event_buffer);
		$endif 
		dir.files.free();
		mem::free(dir.path);
		mem::free(dir);
	}
	watcher.directories.free();
	mem::free(watcher);
}

module watcher @if(env::WIN32);
import std::io;
import std::os::win32;

macro bool WatcherDirectory.createFile(&dir) {
	// add directory path
	dir.handle = win32::createFileA(
		(ichar*)dir.path, //probably unsafe....
		FILE_LIST_DIRECTORY,
		FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
		null,
		OPEN_EXISTING,
		FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
		null
	);
	if(dir.handle == win32::INVALID_HANDLE_VALUE) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("CreateFile failed: Windows Error %d\n", error);
		return false;
	}
	return true;
}

macro bool WatcherDirectory.create_event(&dir) {
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

macro bool WatcherDirectory.allocate_event_buffer(&dir) {
	// allocate the event buffer
	dir.event_buffer = mem::calloc(BUF_LEN);
	if(dir.event_buffer == null) {
		io::eprintf( "calloc failed at %s:$s!\n", $$FILE, $$LINE);
		return false;
	}
	return true;
}

macro bool WatcherDirectory.set_reading_params(&dir) {
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

module watcher;
import inotify;
import std::io;

macro bool WatcherDirectory.inotify_add_watch(&dir, int inotify_fd) {
	dir.inotify_watch_fd = inotify::add_watch(inotify_fd, dir.path, inotify::IN_ALL_EVENTS);
	if(dir.inotify_watch_fd == -1) {
		io::eprintn("inotify_watch_fd -1, failed to add dir to inotify!");
		return false;
	}
	return true;
}