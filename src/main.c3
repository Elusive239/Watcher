module main;
import xwatcher;
import std::io;
import libc;

fn void callback_func(XWatcherFileEvent event,
		ZString path, int context, void *data) {

	switch(event) {
		case XWatcherFileEvent.UNSPECIFIED:
			io::printf("Unspecified event for ");
			break;
		case XWatcherFileEvent.CREATED:
			io::printf("File creation event for ");
			break;
		case XWatcherFileEvent.REMOVED:
			io::printf("File removal event for ");
			break;
		case XWatcherFileEvent.OPENED:
			io::printf("File open event for ");
			break;
		case XWatcherFileEvent.ATTRIBUTES_CHANGED:
			io::printf("File attribute changed event for ");
			break;
		case XWatcherFileEvent.MODIFIED:
			io::printf("File modification event for ");
			break;
		case XWatcherFileEvent.RENAMED:
			io::printf("File renaming event for ");
			break;
		default:
			io::printf("Unhandled event for ");
			break;
	}

	io::printf("%s with context %d\n", path, context);
}


fn int main(String[] args)
{
	io::printn("Hello, World!");
	XWatcher* watcher =  xwatcher::xcreate();
	XWatcherReference ref;
	ref.path = "C:\\Users\\thoma\\Desktop\\XWatcherBindings";

	ref.callback_func = &callback_func;
	ref.context = 1;
	// xwatcher::xappend_directory(watcher, &ref);
	xwatcher::xstart(watcher);
	libc::getchar();
	xwatcher::xdestroy(watcher);
	return 0;
}
