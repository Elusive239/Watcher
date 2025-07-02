module main;
import watcher;
import std::io;
import libc;

fn void callback_func(WatcherFileEvent event,
		ZString path, int context, void *data) {
			DString dstr;
			defer dstr.free();
			dstr.init(mem);
	switch(event) {
		case WatcherFileEvent.UNSPECIFIED:
			dstr.append("Unspecified event for ");
			break;
		case WatcherFileEvent.CREATED:
			dstr.append("File creation event for ");
			break;
		case WatcherFileEvent.REMOVED:
			dstr.append("File removal event for ");
			break;
		case WatcherFileEvent.OPENED:
			dstr.append("File open event for ");
			break;
		case WatcherFileEvent.ATTRIBUTES_CHANGED:
			dstr.append("File attribute changed event for ");
			break;
		case WatcherFileEvent.MODIFIED:
			dstr.append("File modification event for ");
			break;
		case WatcherFileEvent.RENAMED:
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
	Watcher* watcher =  watcher::create_watcher();
	defer watcher::destroy_watcher(watcher);
	if(!watcher.watch( args.len < 2 ? "C:\\Users\\thoma\\Desktop\\XWatcherBindings\\.vscode\\settings.json" : args[1], &callback_func, 1)) return 1;
	if(!watcher.watch( "C:\\Users\\thoma\\Desktop\\XWatcherBindings\\src", &callback_func, 2)) return 1;
	// if(!watcher.watch_path( ".\\.gitignore".to_path(tmem)!!, &callback_func, 1)) return 1;
	io::printfn("appended something");
	if(!watcher.start()) return 1;
	if(args.len != 0) libc::getchar();
	return 0;
}

//just checks and sees if the example doesn't free all of the memory
fn void test_mem() @test => main({});