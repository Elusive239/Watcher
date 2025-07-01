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
	io::printf("%s",dstr);
}


fn int main(String[] args) 
{
	io::printn("Hello, Watcher!");
	XWatcher* watcher =  xwatcher::create_watcher();
	defer xwatcher::destroy_watcher(watcher);
	if(!watcher.watch("C:\\Users\\thoma\\Desktop\\XWatcherBindings\\.vscode\\settings.json", &callback_func, 1)) return 1;
	io::printfn("appended something");
	if(!watcher.start()) return 1;
	if(args.len != 0) libc::getchar();
	return 0;
}

//just checks and sees if the example doesn't free all of the memory
fn void test_mem() @test => main({});