module xwatcher;
import inotify;
import std::io;

macro bool XWatcherDirectory.inotify_add_watch(&dir) {
	dir.inotify_watch_fd = inotify::inotify_add_watch( watcher.inotify_fd, dir.path, IN_ALL_EVENTS);
	if(dir.inotify_watch_fd == -1) {
		io::eprintn("inotify_watch_fd -1, failed to add dir to inotify!");
		return false;
	}
	return true;
}