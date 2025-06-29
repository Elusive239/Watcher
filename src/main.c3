module main;
import xwatcher;
import std::io;

fn int main(String[] args)
{
	io::printn("Hello, World!");
	XWatcher* watcher =  xwatcher::xcreate();
	xwatcher::xdestroy(watcher);
	return 0;
}
