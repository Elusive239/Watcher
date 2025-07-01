module xwatcher @if(env::LINUX);
import inotify;
import std::io;

const CInt EVENT_SIZE  = (INotifyEvent.sizeof);
const CInt BUF_LEN     = (1024 * (EVENT_SIZE + 16));
const char DIRBRK      = '/';


fn int internal_xwatcher_process(void *argument) {
	XWatcher* watcher = (XWatcher*) argument;
	XWatcherDirectory*[] directories = watcher.directories.array_view();

	todo("IN PROGRESS");
	
	return 0;
}
