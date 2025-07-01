module xwatcher @if(env::WIN32);
import std::io;
import std::os::win32;

macro bool XWatcherDirectory.createFile(&dir) {
	// add directory path
	dir.handle = win32::createFileA(
			(ichar*)dir.path, //probably unsafe....
			FILE_LIST_DIRECTORY,
			FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
			null,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
			null);
	if(dir.handle == win32::INVALID_HANDLE_VALUE) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("CreateFile failed: Windows Error %d\n", error);
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.create_event(&dir) {
	// create event structure
	dir.overlapped.hEvent = win32::createEventA(null, (Win32_BOOL) false, 0, null);
	if(dir.overlapped.hEvent == null) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("CreateEvent failed: Windows Error %d\n",error);
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.allocate_event_buffer(&dir) {
	// allocate the event buffer
	dir.event_buffer = mem::calloc(BUF_LEN);
	if(dir.event_buffer == null) {
		io::eprintf( "calloc failed at %s:$s!\n", $$FILE, $$LINE);
		return false;
	}
	return true;
}

macro bool XWatcherDirectory.set_reading_params(&dir) {
	// set reading params
	bool success = (bool) readDirectoryChangesW(
			dir.handle, dir.event_buffer, BUF_LEN, (Win32_BOOL) true,
			FILE_NOTIFY_CHANGE_FILE_NAME  |
			FILE_NOTIFY_CHANGE_DIR_NAME   |
			FILE_NOTIFY_CHANGE_LAST_WRITE,
			null, &dir.overlapped, null);
	if(!success) {
		// get error code
		Win32_DWORD error = win32::getLastError();
		io::eprintf("ReadDirectoryChangesW failed: %d\n", error);
	}
	return success;
}