module xwatcher @if(env::LINUX);
import inotify;
import std::io;
import std::net::os;
import libc;

const CInt EVENT_SIZE  = (INotifyEvent.sizeof);
const CInt BUF_LEN     = (1024 * (EVENT_SIZE + 16));
const char DIRBRK      = '/';

fn int internal_xwatcher_process(void *argument) {
	XWatcher* watcher = (XWatcher*) argument;
	char[BUF_LEN] buffer;
	usz length;
	XWatcherDirectory*[] directories = watcher.directories.array_view();
	while(watcher.alive){
		Posix_pollfd pfd = {.fd = watcher.inotify_fd,.events = os::POLLIN, .revents = 0};
		int ret = os::poll(&pfd, 1, 50);  // timeout of 50ms
		if (ret < 0) {
			// oops
			io::eprintf("poll failed: %d\n", ret);
			break;
		} else if (ret == 0) {
			// Timeout with no events, move on.
			continue;
		}

		// wait for the kernel to do it's thing
		length = libc::read(watcher.inotify_fd, (void*)(&buffer[0]), BUF_LEN);

		usz i;
		while(i < length){
			// the event list itself
			INotifyEvent *event = (INotifyEvent*) &buffer[i];

			// find directory for which this even matches via the descriptor
			XWatcherDirectory *directory = null;
			for(usz j = 0; j < directories.len; j++) {
				if(directories[j].inotify_watch_fd == event.wd) {
					directory = directories[j];
				}
			}

			if(!directory){
				io::eprintn("MATCHING FILE DESCRIPTOR NOT FOUND! ERROR!");
				// BAIL????
					//me. do we bail tho?
			}

			// find matching file (if any)
			XWatcherFile *file = null;
			for(usz j = 0; j < directory.files.len(); j++) {
				usz test_file_name_len = directory.files[j].name.len();
				if(event.len != test_file_name_len) {continue;}
				else if(directory.files[j].name[0:test_file_name_len] == event.name[0:test_file_name_len] ) {
					file = directory.files[j];
					break;
				}
			}

			XWatcherFileEvent send_event = XWatcherFileEvent.NONE;
			switch{
				case (bool) (event.mask & inotify::IN_CREATE):
					send_event = XWatcherFileEvent.CREATED;
				case  (bool) (event.mask & inotify::IN_MODIFY):
					send_event = XWatcherFileEvent.MODIFIED;
				case  (bool) (event.mask & inotify::IN_DELETE):
					send_event = XWatcherFileEvent.REMOVED;
				case  (bool) (event.mask & inotify::IN_CLOSE_WRITE):
				case  (bool) (event.mask & inotify::IN_CLOSE_NOWRITE):
					send_event = XWatcherFileEvent.REMOVED;
				case  (bool) (event.mask & inotify::IN_ATTRIB):
					send_event = XWatcherFileEvent.ATTRIBUTES_CHANGED;
				case  (bool) (event.mask & inotify::IN_OPEN):
					send_event = XWatcherFileEvent.OPENED;
			}

			// file found(?)
			if(file != null) {
				if(send_event != XWatcherFileEvent.NONE) {
					// figure out the file path size
					usz filepath_size = directory.path.len() + file.name.len() + 2;
					// create file path string
					char *filepath = (char*)malloc(filepath_size);
					defer mem::free(filepath);
					libc::snprintf(filepath, filepath_size, "%s/%s",
							directory.path, file.name);
					// callback
					file.callback_func(send_event,
										(ZString)filepath,
										file.context,
										file.additional_data);
				}
			}else {
				// Cannot find file, lets try directory
				if(directory.callback_func != null &&
						send_event != XWatcherFileEvent.NONE) {
					directory.callback_func(send_event,
							directory.path,
							directory.context,
							directory.additional_data);
				}
			}

			i += (ulong) EVENT_SIZE + event.len;
		}
	}	
	foreach(XWatcherDirectory *directory : watcher.directories){
		inotify::inotify_rm_watch(watcher.inotify_fd, directory.inotify_watch_fd);
	}
	libc::close(watcher.inotify_fd);

	return 0;
}
