# Watcher

A filesystem watcher written in [C3](https://c3-lang.org/), based off of [x-watcher](https://github.com/nikp123/x-watcher/tree/main) (created by [nikp123](https://github.com/nikp123)), a filesystem watcher written in C. 

~~Currently only works with full paths (limitation carryover from x-watcher). Support for other kinds of paths is in progress.~~

Used a hacky solution but we have relative paths working! Feels good.

> [!WARNING]
> This is an experimental library, with possibly unstable features. Use at your own risk.

## Supported Platforms:  
[#] Windows!  
[#] Linux!  
[-] Anything Else!  

If someone wished to *add support* for another platform I would be obliged to add it here... 

## Dependencies:  
- C3 Standrd Library  
- Linux Only: gcc-multilib  
- Linux Only: inotify  

## To Use:

I recommend looking at the [example](src/example.c3), it's pretty simple!

If you don't want to look there:

<details>
<summary> <h3>Example Main</h3> </summary> 

```
fn int main()
{
    // we create a watcher object.
    Watcher* watcher =  watcher::create_watcher();

    // we set it up for cleanup and to stop watching files.
    defer watcher::destroy_watcher(watcher);

    // we watch a path, optionally adding a callback function.
    // the path can lead to a file or a directory, but it must be a full path.
    if(! watcher.watch("some_full_path_goes_here", &some_callback_fn)) return 1;

    // Then we start watching the files/directories.
    if(!watcher.start()) return 1;

    // Then, do whatever else you need to do in your app.
    ...
}
```

the watch function also takes 2 additonal optional arguments that can be used however you wish within the callback function:    
`context` -> an integer      
`data`    -> a void*         

</details>

<details>
<summary> <h3>Example Callback Function</h3> </summary>

```
fn void some_callback_fn(WatcherFileEvent event, ZString path, int context, void *data) {
    // when an event is triggered, perform some action defined here.
    switch(event) {
        switch(event) {
            	// List of events available for every OS
		case WatcherFileEvent.NONE:
			io::printf("Got no events!");

		case WatcherFileEvent.REMOVED:
		case WatcherFileEvent.CREATED:
		case WatcherFileEvent.MODIFIED:
			io::printf("Got an event related to %s", path);
		    
		// Linux only events
		case WatcherFileEvent.OPENED:
		case WatcherFileEvent.ATTRIBUTES_CHANGED:
			io::printf("Got a linux only event related to %s", path);
			    
		// Windows only events
		case WatcherFileEvent.RENAMED:
			io::printf("Got a windows only event related to %s", path);

		default:
		    	io::printf("Unhandled event!");
	}
    }
}
```
</details>

## Thanks!

Thanks to [@nikp123](https://github.com/nikp123) for creating x-watcher!

Thanks a bunch to [@ashindigo](https://github.com/ashindigo) for helping to debug the linux side of things.
