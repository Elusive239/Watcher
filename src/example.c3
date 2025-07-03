module main;
import watcher;
import std::io;

fn void callback_func(WatcherFileEvent event,
		ZString path, int context, void *data) {
	switch(event) {
		case WatcherFileEvent.UNSPECIFIED:
			io::printf("Unspecified event for ");
		case WatcherFileEvent.CREATED:
			io::printf("File creation event for ");
		case WatcherFileEvent.REMOVED:
			io::printf("File removal event for ");
		case WatcherFileEvent.OPENED:
			io::printf("File open event for ");
		case WatcherFileEvent.ATTRIBUTES_CHANGED:
			io::printf("File attribute changed event for ");
		case WatcherFileEvent.MODIFIED:
			io::printf("File modification event for ");
		case WatcherFileEvent.RENAMED:
			io::printf("File renaming event for ");
		default:
			io::printf("Unhandled event for ");
	}

	io::printf("%s with context %d\n", path, context);
}


fn int main(String[] args)
{
	String full_path = args.len < 2 ? ".\\.vscode\\" : args[1];

	Watcher* watcher = watcher::create_watcher();
	defer watcher::destroy_watcher(watcher);
	if(!watcher.watch(full_path, &callback_func,0, null)) return 1;
	if(!watcher.start()) return 1;
	if(args.len != 0) (void) io::stdin().read_byte();
	return 0;
}

// just checks and sees if the example doesn't free all of the memory
// run with "c3c test"!
fn void test_mem() @test => main({});