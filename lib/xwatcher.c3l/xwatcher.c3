module xwatcher;

alias PThread @if(!$defined(PThread)) = ulong;

alias XWatcherCallbackFn = fn void( XWatcherFileEvent event, ZString path, int context, void* additional_data);

enum XWatcherFileEvent : char {
	XWATCHER_FILE_UNSPECIFIED,
	XWATCHER_FILE_REMOVED,
	XWATCHER_FILE_CREATED,
	XWATCHER_FILE_MODIFIED,
	XWATCHER_FILE_OPENED,
	XWATCHER_FILE_ATTRIBUTES_CHANGED,
	XWATCHER_FILE_NONE,
	XWATCHER_FILE_RENAMED,
	// probs more but i couldn't care much
}

struct XWatcherReference {
	ZString path;
	XWatcherCallbackFn callback_func;
	int context;
	void *additional_data;
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

extern fn XWatcher *xcreate() @extern("xWatcher_create");
extern fn bool xappend_file(XWatcher*, XWatcherReference*) @extern("xWatcher_appendFile");
extern fn bool xappend_directory(XWatcher*, XWatcherReference*) @extern("xWatcher_appendDir");
extern fn bool xstart(XWatcher*) @extern("xWatcher_start");
extern fn void xdestroy(XWatcher*) @extern("xWatcher_destroy");

module xwatcher @if(env::WIN32);
import std::os::win32;

struct XWatcherDirectory {
	// list of files
	XWatcherFile   *files;

	ZString         path;
	// used for adding (additional) context in the handler (if needed)
	int            context;
	// in case you'd like to avoid global variables
	void          *additional_data;

	XWatcherCallbackFn callback_func;

	Win32_PHANDLE     handle;
	Win32_LPOVERLAPPED overlapped;
	char    *event_buffer;
}

struct XWatcher {
	XWatcherDirectory *directories;
	PThread  thread;
	int        thread_id;
	bool       alive;
}

module xwatcher @if(env::LINUX);

struct XWatcherDirectory {
	// list of files
	XWatcherFile   *files;

	ZString         path;
	// used for adding (additional) context in the handler (if needed)
	int            context;
	// in case you'd like to avoid global variables
	void          *additional_data;

	XWatcherCallbackFn callback_func;

	// we need additional file descriptors (per directory basis)
	int inotify_watch_fd;
}

struct XWatcher {
	XWatcherDirectory *directories;
	PThread  thread;
	int        thread_id;
	bool       alive;

	int inotify_fd; // fd == file descriptor (a common UNIX thing)
}

// module xwatcher @if(!env::WIN32 && !env::LINUX);

// struct XWatcherDirectory  {
// 	// list of files
// 	XWatcherFile   *files;
// 	ZString         path;
// 	// used for adding (additional) context in the handler (if needed)
// 	int            context;
// 	// in case you'd like to avoid global variables
// 	void          *additional_data;
// 	XWatcherCallbackFn callback_func;

// 	void* dummy;
// }

// struct XWatcher {
// 	XWatcherDirectory *directories;
// 	PThread    thread;
// 	int        thread_id;
// 	bool       alive;

// 	void* dummy;
// }