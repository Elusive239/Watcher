module main;
import watcher;
import std::io;

fn void callback_func(WatcherFileEvent event,
		ZString path, int context, void *data) {
	switch(event) {
		case WatcherFileEvent.UNSPECIFIED:
			io::printf("Unspecified event for ");
			break;
		case WatcherFileEvent.CREATED:
			io::printf("File creation event for ");
			break;
		case WatcherFileEvent.REMOVED:
			io::printf("File removal event for ");
			break;
		case WatcherFileEvent.OPENED:
			io::printf("File open event for ");
			break;
		case WatcherFileEvent.ATTRIBUTES_CHANGED:
			io::printf("File attribute changed event for ");
			break;
		case WatcherFileEvent.MODIFIED:
			io::printf("File modification event for ");
			break;
		case WatcherFileEvent.RENAMED:
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
	Watcher* watcher =  watcher::create_watcher();
	defer watcher::destroy_watcher(watcher);
	if(!watcher.watch( args.len < 2 ? "C:\\Users\\thoma\\Desktop\\XWatcherBindings\\.vscode\\settings.json" : args[1], &callback_func, 1)) return 1;
	if(!watcher.start()) return 1;
	if(args.len != 0) (void) io::stdin().read_byte();
	return 0;
}

//just checks and sees if the example doesn't free all of the memory
fn void test_mem() @test => main({});