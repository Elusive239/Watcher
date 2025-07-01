module main;
import xwatcher;
import std::io;
import libc;

fn void callback_func(XWatcherFileEvent event,
		ZString path, int context, void *data) {
			DString dstr;
			defer dstr.free();
			dstr.init(mem);
	switch(event) {
		case XWatcherFileEvent.UNSPECIFIED:
			dstr.append("Unspecified event for ");
			break;
		case XWatcherFileEvent.CREATED:
			dstr.append("File creation event for ");
			break;
		case XWatcherFileEvent.REMOVED:
			dstr.append("File removal event for ");
			break;
		case XWatcherFileEvent.OPENED:
			dstr.append("File open event for ");
			break;
		case XWatcherFileEvent.ATTRIBUTES_CHANGED:
			dstr.append("File attribute changed event for ");
			break;
		case XWatcherFileEvent.MODIFIED:
			dstr.append("File modification event for ");
			break;
		case XWatcherFileEvent.RENAMED:
			dstr.append("File renaming event for ");
			break;
		default:
			dstr.append("Unhandled event for ");
			break;
	}

	dstr.appendf("%s with context %d\n", path, context);
	file::save("output.test", dstr.str_view())!!;
}


fn int main(String[] args)
{
	io::printn("Hello, Watcher!");
	XWatcher* watcher =  xwatcher::xcreate();
	XWatcherReference ref;
	ref.path = "C:\\Users\\thoma\\Desktop\\XWatcherBindings\\.vscode\\";

	ref.callback_func = &callback_func;
	ref.context = 1;
	
	if(!xwatcher::xappend_reference(watcher, &ref)) return 1;
	io::printfn("appended something");
	if(!xwatcher::xstart(watcher)) return 1;
	libc::getchar();
	xwatcher::xdestroy(watcher);
	return 0;
}
