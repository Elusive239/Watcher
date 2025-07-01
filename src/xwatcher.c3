module xwatcher;
import std::collections;
import std::io;
import libc;
import std::os::win32;
import std::os::posix;
import std::thread;
import inotify;

macro todo(String $str = "") {
	$if  $str.len > 0:
	unreachable("TODO(%s): %s (%s)", $str , $$FUNC, env::OS_TYPE);
	$else
	unreachable("TODO: %s (%s)", $$FUNC, env::OS_TYPE);
	$endif
}

alias XWatcherFileList = list::List{XWatcherFile*};
alias XWatcherDirectoryList = list::List{XWatcherDirectory*};
alias XWatcherCallbackFn = fn void( XWatcherFileEvent event, ZString path, int context, void* additional_data);

enum XWatcherFileEvent : usz {
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
	void*  thread; //pthread, check uses..
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

struct XWatcherFile (Printable) {
	// just the file name alone
	ZString name;
	// used for adding (additional) context in the handler (if needed)
	int  context;
	// in case you'd like to avoid global variables
	void *additional_data;

	XWatcherCallbackFn callback_func;
}

fn usz? XWatcherFile.to_format(&this, Formatter *formatter) @dynamic {
	return formatter.printf("%s", this.name)!;
}

fn XWatcher *create_watcher() {
	XWatcher *watcher = mem::new(XWatcher); 
	watcher.directories.init(mem,initial_capacity:1);

	$if env::LINUX : 
		// NEED INOTIFY
		watcher.inotify_fd = inotify::inotify_init1(O_NONBLOCK);
		if(watcher.inotify_fd < 0) {
			io::eprintn("inotify_init");
			return null;
		}
	$endif
	return watcher;
}

<*
	@require $typeof(path).typeid == ZString.typeid || $typeof(path).typeid == String.typeid
*>
macro bool XWatcher.watch(XWatcher* watcher, path, XWatcherCallbackFn callback_func = null, int context = 1) {
	XWatcherReference ref = {
		.path = (ZString) path,
		.callback_func = callback_func,
		.context = context,
	};
	return append_reference(watcher, &ref);
}

fn bool append_reference(XWatcher* watcher, XWatcherReference* reference) {
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

fn bool append_file     (XWatcher* watcher, XWatcherReference* reference) {
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
		dir = mem::new( XWatcherDirectory);
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
	new_file.name            = (ZString) filename;
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

fn bool append_directory(XWatcher* watcher, XWatcherReference* reference) {
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
		dir.files.init(mem, initial_capacity:1);
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

macro void XWatcherDirectory.init_with_reference(&dir, XWatcherReference* reference) {
	dir.callback_func   = reference.callback_func;
	dir.context         = reference.context;
	dir.additional_data = reference.additional_data;
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

fn bool XWatcher.start(XWatcher* watcher) {
	watcher.alive = true;
	
	watcher.thread_id.create(&internal_xwatcher_process, watcher)!!;
	
	if(!watcher.thread_id) {
		io::eprint("couldn't create a new thread...");
		watcher.alive = false;
		return false;
	}
	io::printfn("thread created...");
	return true;
}

fn void destroy_watcher(XWatcher* watcher) {
	watcher.alive = false;
	if(catch err = watcher.thread_id.join()) err?!!;
	foreach(XWatcherDirectory* dir : watcher.directories){
		foreach(XWatcherFile* file : dir.files){
			mem::free(file.name);
			mem::free(file);
		}
		$if env::LINUX :
		if(dir.event_buffer) mem::free(dir.event_buffer);
		$endif 
		dir.files.free();
		mem::free(dir.path);
		mem::free(dir);
	}
	watcher.directories.free();
	mem::free(watcher);
	io::printfn("watcher destroyed...");
}