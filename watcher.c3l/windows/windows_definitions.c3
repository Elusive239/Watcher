module watcher @if(env::WIN32);
import std::os::win32;

//Winnt.h // https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-file_notify_information
struct FileNotifyInformation {
  Win32_DWORD nextEntryOffset;
  Win32_DWORD action;
  Win32_DWORD fileNameLength;
  Win32_WCHAR[1] fileName;
} 

const CUInt FILE_ACTION_ADDED            = 0x00000001;
const CUInt FILE_ACTION_REMOVED          = 0x00000002;
const CUInt FILE_ACTION_MODIFIED         = 0x00000003;
const CUInt FILE_ACTION_RENAMED_OLD_NAME = 0x00000004;
const CUInt FILE_ACTION_RENAMED_NEW_NAME = 0x00000005;

//Winbase.h
const CUInt FILE_NOTIFY_CHANGE_FILE_NAME   = 0x00000001;
const CUInt FILE_NOTIFY_CHANGE_DIR_NAME    = 0x00000002;
const CUInt FILE_NOTIFY_CHANGE_ATTRIBUTES  = 0x00000004;
const CUInt FILE_NOTIFY_CHANGE_SIZE        = 0x00000008;
const CUInt FILE_NOTIFY_CHANGE_LAST_WRITE  = 0x00000010;
const CUInt FILE_NOTIFY_CHANGE_LAST_ACCESS = 0x00000020;
const CUInt FILE_NOTIFY_CHANGE_CREATION    = 0x00000040;
const CUInt FILE_NOTIFY_CHANGE_SECURITY    = 0x00000100;

// https://learn.microsoft.com/en-us/windows/win32/fileio/file-access-rights-constants
const CUInt FILE_LIST_DIRECTORY = 1;

const CUInt FILE_SHARE_DELETE = 0x00000004;
const CUInt FILE_SHARE_READ   = 0x00000001;
const CUInt FILE_SHARE_WRITE  = 0x00000002;

const CUInt CREATE_ALWAYS     = 2;
const CUInt CREATE_NEW        = 1;
const CUInt OPEN_ALWAYS       = 4;
const CUInt OPEN_EXISTING     = 3;
const CUInt TRUNCATE_EXISTING = 5;

const CUInt FILE_FLAG_BACKUP_SEMANTICS  = 0x02000000;
const CUInt FILE_FLAG_DELETE_ON_CLOSE   = 0x04000000;
const CUInt FILE_FLAG_NO_BUFFERING      = 0x20000000;
const CUInt FILE_FLAG_OPEN_NO_RECALL    = 0x00100000;
const CUInt FILE_FLAG_OPEN_REPARSE_POINT= 0x00200000;
const CUInt FILE_FLAG_OVERLAPPED        = 0x40000000;
const CUInt FILE_FLAG_POSIX_SEMANTICS   = 0x01000000;
const CUInt FILE_FLAG_RANDOM_ACCESS     = 0x10000000;
const CUInt FILE_FLAG_SESSION_AWARE     = 0x00800000;
const CUInt FILE_FLAG_SEQUENTIAL_SCAN   = 0x08000000;
const CUInt FILE_FLAG_WRITE_THROUGH     = 0x80000000;

// https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilea

// https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-readdirectorychangesw
extern fn Win32_BOOL readDirectoryChangesW(
	Win32_HANDLE, 
	Win32_LPVOID, 
	Win32_DWORD,
	Win32_BOOL,
	Win32_DWORD,
	Win32_LPDWORD,
	Win32_LPOVERLAPPED,
	void* // <- this is wrong... but what *is* 'LPOVERLAPPED_COMPLETION_ROUTINE' ?
) @extern("ReadDirectoryChangesW");