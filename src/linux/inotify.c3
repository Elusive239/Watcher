module inotify @if(env::POSIX);

typedef INotifyEventFlag = CInt;
const INotifyEventFlag IN_CLOEXEC   = 02000000;
const INotifyEventFlag IN_NONBLOCK  = 04000;

/* Structure describing an inotify event.  */
struct INotifyEvent{
  CInt wd;                /* Watch descriptor.  */
  CUInt mask;        /* Watch mask.  */
  CUInt cookie;        /* Cookie to synchronize two events.  */
  CUInt len;                /* Length (including NULs) of name.  */
  char[1] name;        /* Name.  */ //was "char name __flexarr"
}

// (void)
extern fn CInt inotify_init ();
//int __flags
extern fn CInt inotify_init1 (CInt);
//int __fd, const char *__name, uint32_t __mask
extern fn CInt inotify_add_watch (CInt , ZString, CUInt );
// int __fd, int __wd
extern fn int inotify_rm_watch (CInt, CInt);

/* Supported events suitable for MASK parameter of INOTIFY_ADD_WATCH.  */
const CUInt IN_ACCESS      =   0x00000001;        /* File was accessed.  */
const CUInt IN_MODIFY     =    0x00000002;        /* File was modified.  */
const CUInt IN_ATTRIB       =  0x00000004;        /* Metadata changed.  */
const CUInt IN_CLOSE_WRITE   =      0x00000008;        /* Writtable file was closed.  */
const CUInt IN_CLOSE_NOWRITE= 0x00000010;        /* Unwrittable file closed.  */
const CUInt IN_CLOSE       =  (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE); /* Close.  */
const CUInt IN_OPEN         =        0x00000020;        /* File was opened.  */
const CUInt IN_MOVED_FROM   =      0x00000040;        /* File was moved from X.  */
const CUInt IN_MOVED_TO    =  0x00000080;        /* File was moved to Y.  */
const CUInt IN_MOVE        =         (IN_MOVED_FROM | IN_MOVED_TO); /* Moves.  */
const CUInt IN_CREATE      =   0x00000100;        /* Subfile was created.  */
const CUInt IN_DELETE       =  0x00000200;        /* Subfile was deleted.  */
const CUInt IN_DELETE_SELF   =      0x00000400;        /* Self was deleted.  */
const CUInt IN_MOVE_SELF    =     0x00000800;        /* Self was moved.  */

/* Events sent by the kernel.  */
const CUInt IN_UNMOUNT     =    0x00002000;        /* Backing fs was unmounted.  */
const CUInt IN_Q_OVERFLOW  =       0x00004000;        /* Event queued overflowed.  */
const CUInt IN_IGNORED  =       0x00008000;        /* File was ignored.  */

/* Helper events.  */
const CUInt HIN_CLOSE    =     (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);        /* Close.  */
const CUInt HIN_MOVE     =            (IN_MOVED_FROM | IN_MOVED_TO);                /* Moves.  */

/* Special flags.  */
const CUInt IN_ONLYDIR   =      0x01000000;        /* Only watch the path if it is a;
                                           directory.  */
const CUInt IN_DONT_FOLLOW   =      0x02000000;        /* Do not follow a sym link.  */
const CUInt IN_MASK_ADD      =   0x20000000;        /* Add to the mask of an already;
                                           existing watch.  */
const CUInt IN_ISDIR   =      0x40000000;        /* Event occurred against dir.  */
const CUInt IN_ONESHOT     =    0x80000000;        /* Only send event once.  */

/* All events which a program can wait on.  */
const CUInt IN_ALL_EVENTS   =      (IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE
                          | IN_CLOSE_NOWRITE | IN_OPEN | IN_MOVED_FROM           
                          | IN_MOVED_TO | IN_CREATE | IN_DELETE );               