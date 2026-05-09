const __root = @This();
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
pub const __u_char = u8;
pub const __u_short = c_ushort;
pub const __u_int = c_uint;
pub const __u_long = c_ulong;
pub const __int8_t = i8;
pub const __uint8_t = u8;
pub const __int16_t = c_short;
pub const __uint16_t = c_ushort;
pub const __int32_t = c_int;
pub const __uint32_t = c_uint;
pub const __int64_t = c_long;
pub const __uint64_t = c_ulong;
pub const __int_least8_t = __int8_t;
pub const __uint_least8_t = __uint8_t;
pub const __int_least16_t = __int16_t;
pub const __uint_least16_t = __uint16_t;
pub const __int_least32_t = __int32_t;
pub const __uint_least32_t = __uint32_t;
pub const __int_least64_t = __int64_t;
pub const __uint_least64_t = __uint64_t;
pub const __quad_t = c_long;
pub const __u_quad_t = c_ulong;
pub const __intmax_t = c_long;
pub const __uintmax_t = c_ulong;
pub const __dev_t = c_ulong;
pub const __uid_t = c_uint;
pub const __gid_t = c_uint;
pub const __ino_t = c_ulong;
pub const __ino64_t = c_ulong;
pub const __mode_t = c_uint;
pub const __nlink_t = c_ulong;
pub const __off_t = c_long;
pub const __off64_t = c_long;
pub const __pid_t = c_int;
pub const __fsid_t = extern struct {
    __val: [2]c_int = @import("std").mem.zeroes([2]c_int),
};
pub const __clock_t = c_long;
pub const __rlim_t = c_ulong;
pub const __rlim64_t = c_ulong;
pub const __id_t = c_uint;
pub const __time_t = c_long;
pub const __useconds_t = c_uint;
pub const __suseconds_t = c_long;
pub const __suseconds64_t = c_long;
pub const __daddr_t = c_int;
pub const __key_t = c_int;
pub const __clockid_t = c_int;
pub const __timer_t = ?*anyopaque;
pub const __blksize_t = c_long;
pub const __blkcnt_t = c_long;
pub const __blkcnt64_t = c_long;
pub const __fsblkcnt_t = c_ulong;
pub const __fsblkcnt64_t = c_ulong;
pub const __fsfilcnt_t = c_ulong;
pub const __fsfilcnt64_t = c_ulong;
pub const __fsword_t = c_long;
pub const __ssize_t = c_long;
pub const __syscall_slong_t = c_long;
pub const __syscall_ulong_t = c_ulong;
pub const __loff_t = __off64_t;
pub const __caddr_t = [*c]u8;
pub const __intptr_t = c_long;
pub const __socklen_t = c_uint;
pub const __sig_atomic_t = c_int;
pub const u_char = __u_char;
pub const u_short = __u_short;
pub const u_int = __u_int;
pub const u_long = __u_long;
pub const quad_t = __quad_t;
pub const u_quad_t = __u_quad_t;
pub const fsid_t = __fsid_t;
pub const loff_t = __loff_t;
pub const ino_t = __ino_t;
pub const dev_t = __dev_t;
pub const gid_t = __gid_t;
pub const mode_t = __mode_t;
pub const nlink_t = __nlink_t;
pub const uid_t = __uid_t;
pub const off_t = __off_t;
pub const pid_t = __pid_t;
pub const id_t = __id_t;
pub const daddr_t = __daddr_t;
pub const caddr_t = __caddr_t;
pub const key_t = __key_t;
pub const clock_t = __clock_t;
pub const clockid_t = __clockid_t;
pub const time_t = __time_t;
pub const timer_t = __timer_t;
pub const ptrdiff_t = c_long;
pub const wchar_t = c_int;
pub const max_align_t = extern struct {
    __aro_max_align_ll: c_longlong = 0,
    __aro_max_align_ld: c_longdouble = 0,
};
pub const ulong = c_ulong;
pub const ushort = c_ushort;
pub const uint = c_uint;
pub const u_int8_t = __uint8_t;
pub const u_int16_t = __uint16_t;
pub const u_int32_t = __uint32_t;
pub const u_int64_t = __uint64_t;
pub const register_t = c_int;
pub fn __bswap_16(arg___bsx: __uint16_t) callconv(.c) __uint16_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @byteSwap(@as(__uint16_t, __bsx));
}
pub fn __bswap_32(arg___bsx: __uint32_t) callconv(.c) __uint32_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_int, @byteSwap(@as(c_int, @bitCast(@as(c_uint, @truncate(__bsx)))))));
}
pub fn __bswap_64(arg___bsx: __uint64_t) callconv(.c) __uint64_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_long, @byteSwap(@as(c_long, @bitCast(@as(c_ulong, @truncate(__bsx)))))));
}
pub fn __uint16_identity(arg___x: __uint16_t) callconv(.c) __uint16_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint32_identity(arg___x: __uint32_t) callconv(.c) __uint32_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint64_identity(arg___x: __uint64_t) callconv(.c) __uint64_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub const __sigset_t = extern struct {
    __val: [16]c_ulong = @import("std").mem.zeroes([16]c_ulong),
};
pub const sigset_t = __sigset_t;
pub const struct_timeval = extern struct {
    tv_sec: __time_t = 0,
    tv_usec: __suseconds_t = 0,
};
pub const struct_timespec = extern struct {
    tv_sec: __time_t = 0,
    tv_nsec: __syscall_slong_t = 0,
};
pub const suseconds_t = __suseconds_t;
pub const __fd_mask = c_long;
pub const fd_set = extern struct {
    __fds_bits: [16]__fd_mask = @import("std").mem.zeroes([16]__fd_mask),
};
pub const fd_mask = __fd_mask;
pub extern fn select(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]struct_timeval) c_int;
pub extern fn pselect(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]const struct_timespec, noalias __sigmask: [*c]const __sigset_t) c_int;
pub const blksize_t = __blksize_t;
pub const blkcnt_t = __blkcnt_t;
pub const fsblkcnt_t = __fsblkcnt_t;
pub const fsfilcnt_t = __fsfilcnt_t;
const struct_unnamed_1 = extern struct {
    __low: c_uint = 0,
    __high: c_uint = 0,
};
pub const __atomic_wide_counter = extern union {
    __value64: c_ulonglong,
    __value32: struct_unnamed_1,
};
pub const struct___pthread_internal_list = extern struct {
    __prev: [*c]struct___pthread_internal_list = null,
    __next: [*c]struct___pthread_internal_list = null,
};
pub const __pthread_list_t = struct___pthread_internal_list;
pub const struct___pthread_internal_slist = extern struct {
    __next: [*c]struct___pthread_internal_slist = null,
};
pub const __pthread_slist_t = struct___pthread_internal_slist;
pub const struct___pthread_mutex_s = extern struct {
    __lock: c_int = 0,
    __count: c_uint = 0,
    __owner: c_int = 0,
    __nusers: c_uint = 0,
    __kind: c_int = 0,
    __spins: c_short = 0,
    __unused: c_short = 0,
    __list: __pthread_list_t = @import("std").mem.zeroes(__pthread_list_t),
};
pub const struct___pthread_rwlock_arch_t = extern struct {
    __readers: c_uint = 0,
    __writers: c_uint = 0,
    __wrphase_futex: c_uint = 0,
    __writers_futex: c_uint = 0,
    __pad3: c_uint = 0,
    __pad4: c_uint = 0,
    __cur_writer: c_int = 0,
    __shared: c_int = 0,
    __pad1: c_ulong = 0,
    __pad2: c_ulong = 0,
    __flags: c_uint = 0,
};
pub const struct___pthread_cond_s = extern struct {
    __wseq: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g1_start: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g_size: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __g1_orig_size: c_uint = 0,
    __wrefs: c_uint = 0,
    __g_signals: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __unused_initialized_1: c_uint = 0,
    __unused_initialized_2: c_uint = 0,
};
pub const __tss_t = c_uint;
pub const __thrd_t = c_ulong;
pub const __once_flag = extern struct {
    __data: c_int = 0,
};
pub const pthread_t = c_ulong;
pub const pthread_mutexattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_condattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_key_t = c_uint;
pub const pthread_once_t = c_int;
pub const union_pthread_attr_t = extern union {
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_attr_t = union_pthread_attr_t;
pub const pthread_mutex_t = extern union {
    __data: struct___pthread_mutex_s,
    __size: [40]u8,
    __align: c_long,
};
pub const pthread_cond_t = extern union {
    __data: struct___pthread_cond_s,
    __size: [48]u8,
    __align: c_longlong,
};
pub const pthread_rwlock_t = extern union {
    __data: struct___pthread_rwlock_arch_t,
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_rwlockattr_t = extern union {
    __size: [8]u8,
    __align: c_long,
};
pub const pthread_spinlock_t = c_int;
pub const pthread_barrier_t = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const pthread_barrierattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const XID = c_ulong;
pub const Mask = c_ulong;
pub const Atom = c_ulong;
pub const VisualID = c_ulong;
pub const Time = c_ulong;
pub const Window = XID;
pub const Drawable = XID;
pub const Font = XID;
pub const Pixmap = XID;
pub const Cursor = XID;
pub const Colormap = XID;
pub const GContext = XID;
pub const KeySym = XID;
pub const KeyCode = u8;
pub extern fn _Xmblen(str: [*c]u8, len: c_int) c_int;
pub const XPointer = [*c]u8;
pub const struct__XExtData = extern struct {
    number: c_int = 0,
    next: [*c]struct__XExtData = null,
    free_private: ?*const fn (extension: [*c]struct__XExtData) callconv(.c) c_int = null,
    private_data: XPointer = null,
};
pub const XExtData = struct__XExtData;
pub const XExtCodes = extern struct {
    extension: c_int = 0,
    major_opcode: c_int = 0,
    first_event: c_int = 0,
    first_error: c_int = 0,
};
pub const XPixmapFormatValues = extern struct {
    depth: c_int = 0,
    bits_per_pixel: c_int = 0,
    scanline_pad: c_int = 0,
};
pub const XGCValues = extern struct {
    function: c_int = 0,
    plane_mask: c_ulong = 0,
    foreground: c_ulong = 0,
    background: c_ulong = 0,
    line_width: c_int = 0,
    line_style: c_int = 0,
    cap_style: c_int = 0,
    join_style: c_int = 0,
    fill_style: c_int = 0,
    fill_rule: c_int = 0,
    arc_mode: c_int = 0,
    tile: Pixmap = 0,
    stipple: Pixmap = 0,
    ts_x_origin: c_int = 0,
    ts_y_origin: c_int = 0,
    font: Font = 0,
    subwindow_mode: c_int = 0,
    graphics_exposures: c_int = 0,
    clip_x_origin: c_int = 0,
    clip_y_origin: c_int = 0,
    clip_mask: Pixmap = 0,
    dash_offset: c_int = 0,
    dashes: u8 = 0,
};
pub const struct__XGC = opaque {
    pub const XGContextFromGC = __root.XGContextFromGC;
};
pub const GC = ?*struct__XGC;
pub const Visual = extern struct {
    ext_data: [*c]XExtData = null,
    visualid: VisualID = 0,
    class: c_int = 0,
    red_mask: c_ulong = 0,
    green_mask: c_ulong = 0,
    blue_mask: c_ulong = 0,
    bits_per_rgb: c_int = 0,
    map_entries: c_int = 0,
    pub const XVisualIDFromVisual = __root.XVisualIDFromVisual;
};
pub const Depth = extern struct {
    depth: c_int = 0,
    nvisuals: c_int = 0,
    visuals: [*c]Visual = null,
};
pub const struct__XDisplay = opaque {
    pub const XLoadQueryFont = __root.XLoadQueryFont;
    pub const XQueryFont = __root.XQueryFont;
    pub const XGetMotionEvents = __root.XGetMotionEvents;
    pub const XGetModifierMapping = __root.XGetModifierMapping;
    pub const XCreateImage = __root.XCreateImage;
    pub const XGetImage = __root.XGetImage;
    pub const XGetSubImage = __root.XGetSubImage;
    pub const XFetchBytes = __root.XFetchBytes;
    pub const XFetchBuffer = __root.XFetchBuffer;
    pub const XGetAtomName = __root.XGetAtomName;
    pub const XGetAtomNames = __root.XGetAtomNames;
    pub const XGetDefault = __root.XGetDefault;
    pub const XSynchronize = __root.XSynchronize;
    pub const XSetAfterFunction = __root.XSetAfterFunction;
    pub const XInternAtom = __root.XInternAtom;
    pub const XInternAtoms = __root.XInternAtoms;
    pub const XCopyColormapAndFree = __root.XCopyColormapAndFree;
    pub const XCreateColormap = __root.XCreateColormap;
    pub const XCreatePixmapCursor = __root.XCreatePixmapCursor;
    pub const XCreateGlyphCursor = __root.XCreateGlyphCursor;
    pub const XCreateFontCursor = __root.XCreateFontCursor;
    pub const XLoadFont = __root.XLoadFont;
    pub const XCreateGC = __root.XCreateGC;
    pub const XFlushGC = __root.XFlushGC;
    pub const XCreatePixmap = __root.XCreatePixmap;
    pub const XCreateBitmapFromData = __root.XCreateBitmapFromData;
    pub const XCreatePixmapFromBitmapData = __root.XCreatePixmapFromBitmapData;
    pub const XCreateSimpleWindow = __root.XCreateSimpleWindow;
    pub const XGetSelectionOwner = __root.XGetSelectionOwner;
    pub const XCreateWindow = __root.XCreateWindow;
    pub const XListInstalledColormaps = __root.XListInstalledColormaps;
    pub const XListFonts = __root.XListFonts;
    pub const XListFontsWithInfo = __root.XListFontsWithInfo;
    pub const XGetFontPath = __root.XGetFontPath;
    pub const XListExtensions = __root.XListExtensions;
    pub const XListProperties = __root.XListProperties;
    pub const XListHosts = __root.XListHosts;
    pub const XKeycodeToKeysym = __root.XKeycodeToKeysym;
    pub const XGetKeyboardMapping = __root.XGetKeyboardMapping;
    pub const XMaxRequestSize = __root.XMaxRequestSize;
    pub const XExtendedMaxRequestSize = __root.XExtendedMaxRequestSize;
    pub const XResourceManagerString = __root.XResourceManagerString;
    pub const XDisplayMotionBufferSize = __root.XDisplayMotionBufferSize;
    pub const XLockDisplay = __root.XLockDisplay;
    pub const XUnlockDisplay = __root.XUnlockDisplay;
    pub const XInitExtension = __root.XInitExtension;
    pub const XAddExtension = __root.XAddExtension;
    pub const XRootWindow = __root.XRootWindow;
    pub const XDefaultRootWindow = __root.XDefaultRootWindow;
    pub const XDefaultVisual = __root.XDefaultVisual;
    pub const XDefaultGC = __root.XDefaultGC;
    pub const XBlackPixel = __root.XBlackPixel;
    pub const XWhitePixel = __root.XWhitePixel;
    pub const XNextRequest = __root.XNextRequest;
    pub const XLastKnownRequestProcessed = __root.XLastKnownRequestProcessed;
    pub const XServerVendor = __root.XServerVendor;
    pub const XDisplayString = __root.XDisplayString;
    pub const XDefaultColormap = __root.XDefaultColormap;
    pub const XScreenOfDisplay = __root.XScreenOfDisplay;
    pub const XDefaultScreenOfDisplay = __root.XDefaultScreenOfDisplay;
    pub const XSetIOErrorExitHandler = __root.XSetIOErrorExitHandler;
    pub const XListPixmapFormats = __root.XListPixmapFormats;
    pub const XListDepths = __root.XListDepths;
    pub const XReconfigureWMWindow = __root.XReconfigureWMWindow;
    pub const XGetWMProtocols = __root.XGetWMProtocols;
    pub const XSetWMProtocols = __root.XSetWMProtocols;
    pub const XIconifyWindow = __root.XIconifyWindow;
    pub const XWithdrawWindow = __root.XWithdrawWindow;
    pub const XGetCommand = __root.XGetCommand;
    pub const XGetWMColormapWindows = __root.XGetWMColormapWindows;
    pub const XSetWMColormapWindows = __root.XSetWMColormapWindows;
    pub const XSetTransientForHint = __root.XSetTransientForHint;
    pub const XActivateScreenSaver = __root.XActivateScreenSaver;
    pub const XAddHost = __root.XAddHost;
    pub const XAddHosts = __root.XAddHosts;
    pub const XAddToSaveSet = __root.XAddToSaveSet;
    pub const XAllocColor = __root.XAllocColor;
    pub const XAllocColorCells = __root.XAllocColorCells;
    pub const XAllocColorPlanes = __root.XAllocColorPlanes;
    pub const XAllocNamedColor = __root.XAllocNamedColor;
    pub const XAllowEvents = __root.XAllowEvents;
    pub const XAutoRepeatOff = __root.XAutoRepeatOff;
    pub const XAutoRepeatOn = __root.XAutoRepeatOn;
    pub const XBell = __root.XBell;
    pub const XBitmapBitOrder = __root.XBitmapBitOrder;
    pub const XBitmapPad = __root.XBitmapPad;
    pub const XBitmapUnit = __root.XBitmapUnit;
    pub const XChangeActivePointerGrab = __root.XChangeActivePointerGrab;
    pub const XChangeGC = __root.XChangeGC;
    pub const XChangeKeyboardControl = __root.XChangeKeyboardControl;
    pub const XChangeKeyboardMapping = __root.XChangeKeyboardMapping;
    pub const XChangePointerControl = __root.XChangePointerControl;
    pub const XChangeProperty = __root.XChangeProperty;
    pub const XChangeSaveSet = __root.XChangeSaveSet;
    pub const XChangeWindowAttributes = __root.XChangeWindowAttributes;
    pub const XCheckIfEvent = __root.XCheckIfEvent;
    pub const XCheckMaskEvent = __root.XCheckMaskEvent;
    pub const XCheckTypedEvent = __root.XCheckTypedEvent;
    pub const XCheckTypedWindowEvent = __root.XCheckTypedWindowEvent;
    pub const XCheckWindowEvent = __root.XCheckWindowEvent;
    pub const XCirculateSubwindows = __root.XCirculateSubwindows;
    pub const XCirculateSubwindowsDown = __root.XCirculateSubwindowsDown;
    pub const XCirculateSubwindowsUp = __root.XCirculateSubwindowsUp;
    pub const XClearArea = __root.XClearArea;
    pub const XClearWindow = __root.XClearWindow;
    pub const XCloseDisplay = __root.XCloseDisplay;
    pub const XConfigureWindow = __root.XConfigureWindow;
    pub const XConnectionNumber = __root.XConnectionNumber;
    pub const XConvertSelection = __root.XConvertSelection;
    pub const XCopyArea = __root.XCopyArea;
    pub const XCopyGC = __root.XCopyGC;
    pub const XCopyPlane = __root.XCopyPlane;
    pub const XDefaultDepth = __root.XDefaultDepth;
    pub const XDefaultScreen = __root.XDefaultScreen;
    pub const XDefineCursor = __root.XDefineCursor;
    pub const XDeleteProperty = __root.XDeleteProperty;
    pub const XDestroyWindow = __root.XDestroyWindow;
    pub const XDestroySubwindows = __root.XDestroySubwindows;
    pub const XDisableAccessControl = __root.XDisableAccessControl;
    pub const XDisplayCells = __root.XDisplayCells;
    pub const XDisplayHeight = __root.XDisplayHeight;
    pub const XDisplayHeightMM = __root.XDisplayHeightMM;
    pub const XDisplayKeycodes = __root.XDisplayKeycodes;
    pub const XDisplayPlanes = __root.XDisplayPlanes;
    pub const XDisplayWidth = __root.XDisplayWidth;
    pub const XDisplayWidthMM = __root.XDisplayWidthMM;
    pub const XDrawArc = __root.XDrawArc;
    pub const XDrawArcs = __root.XDrawArcs;
    pub const XDrawImageString = __root.XDrawImageString;
    pub const XDrawImageString16 = __root.XDrawImageString16;
    pub const XDrawLine = __root.XDrawLine;
    pub const XDrawLines = __root.XDrawLines;
    pub const XDrawPoint = __root.XDrawPoint;
    pub const XDrawPoints = __root.XDrawPoints;
    pub const XDrawRectangle = __root.XDrawRectangle;
    pub const XDrawRectangles = __root.XDrawRectangles;
    pub const XDrawSegments = __root.XDrawSegments;
    pub const XDrawString = __root.XDrawString;
    pub const XDrawString16 = __root.XDrawString16;
    pub const XDrawText = __root.XDrawText;
    pub const XDrawText16 = __root.XDrawText16;
    pub const XEnableAccessControl = __root.XEnableAccessControl;
    pub const XEventsQueued = __root.XEventsQueued;
    pub const XFetchName = __root.XFetchName;
    pub const XFillArc = __root.XFillArc;
    pub const XFillArcs = __root.XFillArcs;
    pub const XFillPolygon = __root.XFillPolygon;
    pub const XFillRectangle = __root.XFillRectangle;
    pub const XFillRectangles = __root.XFillRectangles;
    pub const XFlush = __root.XFlush;
    pub const XForceScreenSaver = __root.XForceScreenSaver;
    pub const XFreeColormap = __root.XFreeColormap;
    pub const XFreeColors = __root.XFreeColors;
    pub const XFreeCursor = __root.XFreeCursor;
    pub const XFreeFont = __root.XFreeFont;
    pub const XFreeGC = __root.XFreeGC;
    pub const XFreePixmap = __root.XFreePixmap;
    pub const XGeometry = __root.XGeometry;
    pub const XGetErrorDatabaseText = __root.XGetErrorDatabaseText;
    pub const XGetErrorText = __root.XGetErrorText;
    pub const XGetGCValues = __root.XGetGCValues;
    pub const XGetGeometry = __root.XGetGeometry;
    pub const XGetIconName = __root.XGetIconName;
    pub const XGetInputFocus = __root.XGetInputFocus;
    pub const XGetKeyboardControl = __root.XGetKeyboardControl;
    pub const XGetPointerControl = __root.XGetPointerControl;
    pub const XGetPointerMapping = __root.XGetPointerMapping;
    pub const XGetScreenSaver = __root.XGetScreenSaver;
    pub const XGetTransientForHint = __root.XGetTransientForHint;
    pub const XGetWindowProperty = __root.XGetWindowProperty;
    pub const XGetWindowAttributes = __root.XGetWindowAttributes;
    pub const XGrabButton = __root.XGrabButton;
    pub const XGrabKey = __root.XGrabKey;
    pub const XGrabKeyboard = __root.XGrabKeyboard;
    pub const XGrabPointer = __root.XGrabPointer;
    pub const XGrabServer = __root.XGrabServer;
    pub const XIfEvent = __root.XIfEvent;
    pub const XImageByteOrder = __root.XImageByteOrder;
    pub const XInstallColormap = __root.XInstallColormap;
    pub const XKeysymToKeycode = __root.XKeysymToKeycode;
    pub const XKillClient = __root.XKillClient;
    pub const XLookupColor = __root.XLookupColor;
    pub const XLowerWindow = __root.XLowerWindow;
    pub const XMapRaised = __root.XMapRaised;
    pub const XMapSubwindows = __root.XMapSubwindows;
    pub const XMapWindow = __root.XMapWindow;
    pub const XMaskEvent = __root.XMaskEvent;
    pub const XMoveResizeWindow = __root.XMoveResizeWindow;
    pub const XMoveWindow = __root.XMoveWindow;
    pub const XNextEvent = __root.XNextEvent;
    pub const XNoOp = __root.XNoOp;
    pub const XParseColor = __root.XParseColor;
    pub const XPeekEvent = __root.XPeekEvent;
    pub const XPeekIfEvent = __root.XPeekIfEvent;
    pub const XPending = __root.XPending;
    pub const XProtocolRevision = __root.XProtocolRevision;
    pub const XProtocolVersion = __root.XProtocolVersion;
    pub const XPutBackEvent = __root.XPutBackEvent;
    pub const XPutImage = __root.XPutImage;
    pub const XQLength = __root.XQLength;
    pub const XQueryBestCursor = __root.XQueryBestCursor;
    pub const XQueryBestSize = __root.XQueryBestSize;
    pub const XQueryBestStipple = __root.XQueryBestStipple;
    pub const XQueryBestTile = __root.XQueryBestTile;
    pub const XQueryColor = __root.XQueryColor;
    pub const XQueryColors = __root.XQueryColors;
    pub const XQueryExtension = __root.XQueryExtension;
    pub const XQueryKeymap = __root.XQueryKeymap;
    pub const XQueryPointer = __root.XQueryPointer;
    pub const XQueryTextExtents = __root.XQueryTextExtents;
    pub const XQueryTextExtents16 = __root.XQueryTextExtents16;
    pub const XQueryTree = __root.XQueryTree;
    pub const XRaiseWindow = __root.XRaiseWindow;
    pub const XReadBitmapFile = __root.XReadBitmapFile;
    pub const XRebindKeysym = __root.XRebindKeysym;
    pub const XRecolorCursor = __root.XRecolorCursor;
    pub const XRemoveFromSaveSet = __root.XRemoveFromSaveSet;
    pub const XRemoveHost = __root.XRemoveHost;
    pub const XRemoveHosts = __root.XRemoveHosts;
    pub const XReparentWindow = __root.XReparentWindow;
    pub const XResetScreenSaver = __root.XResetScreenSaver;
    pub const XResizeWindow = __root.XResizeWindow;
    pub const XRestackWindows = __root.XRestackWindows;
    pub const XRotateBuffers = __root.XRotateBuffers;
    pub const XRotateWindowProperties = __root.XRotateWindowProperties;
    pub const XScreenCount = __root.XScreenCount;
    pub const XSelectInput = __root.XSelectInput;
    pub const XSendEvent = __root.XSendEvent;
    pub const XSetAccessControl = __root.XSetAccessControl;
    pub const XSetArcMode = __root.XSetArcMode;
    pub const XSetBackground = __root.XSetBackground;
    pub const XSetClipMask = __root.XSetClipMask;
    pub const XSetClipOrigin = __root.XSetClipOrigin;
    pub const XSetClipRectangles = __root.XSetClipRectangles;
    pub const XSetCloseDownMode = __root.XSetCloseDownMode;
    pub const XSetCommand = __root.XSetCommand;
    pub const XSetDashes = __root.XSetDashes;
    pub const XSetFillRule = __root.XSetFillRule;
    pub const XSetFillStyle = __root.XSetFillStyle;
    pub const XSetFont = __root.XSetFont;
    pub const XSetFontPath = __root.XSetFontPath;
    pub const XSetForeground = __root.XSetForeground;
    pub const XSetFunction = __root.XSetFunction;
    pub const XSetGraphicsExposures = __root.XSetGraphicsExposures;
    pub const XSetIconName = __root.XSetIconName;
    pub const XSetInputFocus = __root.XSetInputFocus;
    pub const XSetLineAttributes = __root.XSetLineAttributes;
    pub const XSetModifierMapping = __root.XSetModifierMapping;
    pub const XSetPlaneMask = __root.XSetPlaneMask;
    pub const XSetPointerMapping = __root.XSetPointerMapping;
    pub const XSetScreenSaver = __root.XSetScreenSaver;
    pub const XSetSelectionOwner = __root.XSetSelectionOwner;
    pub const XSetState = __root.XSetState;
    pub const XSetStipple = __root.XSetStipple;
    pub const XSetSubwindowMode = __root.XSetSubwindowMode;
    pub const XSetTSOrigin = __root.XSetTSOrigin;
    pub const XSetTile = __root.XSetTile;
    pub const XSetWindowBackground = __root.XSetWindowBackground;
    pub const XSetWindowBackgroundPixmap = __root.XSetWindowBackgroundPixmap;
    pub const XSetWindowBorder = __root.XSetWindowBorder;
    pub const XSetWindowBorderPixmap = __root.XSetWindowBorderPixmap;
    pub const XSetWindowBorderWidth = __root.XSetWindowBorderWidth;
    pub const XSetWindowColormap = __root.XSetWindowColormap;
    pub const XStoreBuffer = __root.XStoreBuffer;
    pub const XStoreBytes = __root.XStoreBytes;
    pub const XStoreColor = __root.XStoreColor;
    pub const XStoreColors = __root.XStoreColors;
    pub const XStoreName = __root.XStoreName;
    pub const XStoreNamedColor = __root.XStoreNamedColor;
    pub const XSync = __root.XSync;
    pub const XTranslateCoordinates = __root.XTranslateCoordinates;
    pub const XUndefineCursor = __root.XUndefineCursor;
    pub const XUngrabButton = __root.XUngrabButton;
    pub const XUngrabKey = __root.XUngrabKey;
    pub const XUngrabKeyboard = __root.XUngrabKeyboard;
    pub const XUngrabPointer = __root.XUngrabPointer;
    pub const XUngrabServer = __root.XUngrabServer;
    pub const XUninstallColormap = __root.XUninstallColormap;
    pub const XUnloadFont = __root.XUnloadFont;
    pub const XUnmapSubwindows = __root.XUnmapSubwindows;
    pub const XUnmapWindow = __root.XUnmapWindow;
    pub const XVendorRelease = __root.XVendorRelease;
    pub const XWarpPointer = __root.XWarpPointer;
    pub const XWindowEvent = __root.XWindowEvent;
    pub const XWriteBitmapFile = __root.XWriteBitmapFile;
    pub const XOpenOM = __root.XOpenOM;
    pub const XCreateFontSet = __root.XCreateFontSet;
    pub const XFreeFontSet = __root.XFreeFontSet;
    pub const XmbDrawText = __root.XmbDrawText;
    pub const XwcDrawText = __root.XwcDrawText;
    pub const Xutf8DrawText = __root.Xutf8DrawText;
    pub const XmbDrawString = __root.XmbDrawString;
    pub const XwcDrawString = __root.XwcDrawString;
    pub const Xutf8DrawString = __root.Xutf8DrawString;
    pub const XmbDrawImageString = __root.XmbDrawImageString;
    pub const XwcDrawImageString = __root.XwcDrawImageString;
    pub const Xutf8DrawImageString = __root.Xutf8DrawImageString;
    pub const XOpenIM = __root.XOpenIM;
    pub const XRegisterIMInstantiateCallback = __root.XRegisterIMInstantiateCallback;
    pub const XUnregisterIMInstantiateCallback = __root.XUnregisterIMInstantiateCallback;
    pub const XInternalConnectionNumbers = __root.XInternalConnectionNumbers;
    pub const XProcessInternalConnection = __root.XProcessInternalConnection;
    pub const XAddConnectionWatch = __root.XAddConnectionWatch;
    pub const XRemoveConnectionWatch = __root.XRemoveConnectionWatch;
    pub const XGetEventData = __root.XGetEventData;
    pub const XFreeEventData = __root.XFreeEventData;
};
pub const Screen = extern struct {
    ext_data: [*c]XExtData = null,
    display: ?*struct__XDisplay = null,
    root: Window = 0,
    width: c_int = 0,
    height: c_int = 0,
    mwidth: c_int = 0,
    mheight: c_int = 0,
    ndepths: c_int = 0,
    depths: [*c]Depth = null,
    root_depth: c_int = 0,
    root_visual: [*c]Visual = null,
    default_gc: GC = null,
    cmap: Colormap = 0,
    white_pixel: c_ulong = 0,
    black_pixel: c_ulong = 0,
    max_maps: c_int = 0,
    min_maps: c_int = 0,
    backing_store: c_int = 0,
    save_unders: c_int = 0,
    root_input_mask: c_long = 0,
    pub const XScreenResourceString = __root.XScreenResourceString;
    pub const XRootWindowOfScreen = __root.XRootWindowOfScreen;
    pub const XDefaultVisualOfScreen = __root.XDefaultVisualOfScreen;
    pub const XDefaultGCOfScreen = __root.XDefaultGCOfScreen;
    pub const XBlackPixelOfScreen = __root.XBlackPixelOfScreen;
    pub const XWhitePixelOfScreen = __root.XWhitePixelOfScreen;
    pub const XDefaultColormapOfScreen = __root.XDefaultColormapOfScreen;
    pub const XDisplayOfScreen = __root.XDisplayOfScreen;
    pub const XEventMaskOfScreen = __root.XEventMaskOfScreen;
    pub const XScreenNumberOfScreen = __root.XScreenNumberOfScreen;
    pub const XCellsOfScreen = __root.XCellsOfScreen;
    pub const XDefaultDepthOfScreen = __root.XDefaultDepthOfScreen;
    pub const XDoesBackingStore = __root.XDoesBackingStore;
    pub const XDoesSaveUnders = __root.XDoesSaveUnders;
    pub const XHeightMMOfScreen = __root.XHeightMMOfScreen;
    pub const XHeightOfScreen = __root.XHeightOfScreen;
    pub const XMaxCmapsOfScreen = __root.XMaxCmapsOfScreen;
    pub const XMinCmapsOfScreen = __root.XMinCmapsOfScreen;
    pub const XPlanesOfScreen = __root.XPlanesOfScreen;
    pub const XWidthMMOfScreen = __root.XWidthMMOfScreen;
    pub const XWidthOfScreen = __root.XWidthOfScreen;
};
pub const ScreenFormat = extern struct {
    ext_data: [*c]XExtData = null,
    depth: c_int = 0,
    bits_per_pixel: c_int = 0,
    scanline_pad: c_int = 0,
};
pub const XSetWindowAttributes = extern struct {
    background_pixmap: Pixmap = 0,
    background_pixel: c_ulong = 0,
    border_pixmap: Pixmap = 0,
    border_pixel: c_ulong = 0,
    bit_gravity: c_int = 0,
    win_gravity: c_int = 0,
    backing_store: c_int = 0,
    backing_planes: c_ulong = 0,
    backing_pixel: c_ulong = 0,
    save_under: c_int = 0,
    event_mask: c_long = 0,
    do_not_propagate_mask: c_long = 0,
    override_redirect: c_int = 0,
    colormap: Colormap = 0,
    cursor: Cursor = 0,
};
pub const XWindowAttributes = extern struct {
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    depth: c_int = 0,
    visual: [*c]Visual = null,
    root: Window = 0,
    class: c_int = 0,
    bit_gravity: c_int = 0,
    win_gravity: c_int = 0,
    backing_store: c_int = 0,
    backing_planes: c_ulong = 0,
    backing_pixel: c_ulong = 0,
    save_under: c_int = 0,
    colormap: Colormap = 0,
    map_installed: c_int = 0,
    map_state: c_int = 0,
    all_event_masks: c_long = 0,
    your_event_mask: c_long = 0,
    do_not_propagate_mask: c_long = 0,
    override_redirect: c_int = 0,
    screen: [*c]Screen = null,
};
pub const XHostAddress = extern struct {
    family: c_int = 0,
    length: c_int = 0,
    address: [*c]u8 = null,
};
pub const XServerInterpretedAddress = extern struct {
    typelength: c_int = 0,
    valuelength: c_int = 0,
    type: [*c]u8 = null,
    value: [*c]u8 = null,
};
pub const struct_funcs_2 = extern struct {
    create_image: ?*const fn (?*struct__XDisplay, [*c]Visual, c_uint, c_int, c_int, [*c]u8, c_uint, c_uint, c_int, c_int) callconv(.c) [*c]struct__XImage = null,
    destroy_image: ?*const fn ([*c]struct__XImage) callconv(.c) c_int = null,
    get_pixel: ?*const fn ([*c]struct__XImage, c_int, c_int) callconv(.c) c_ulong = null,
    put_pixel: ?*const fn ([*c]struct__XImage, c_int, c_int, c_ulong) callconv(.c) c_int = null,
    sub_image: ?*const fn ([*c]struct__XImage, c_int, c_int, c_uint, c_uint) callconv(.c) [*c]struct__XImage = null,
    add_pixel: ?*const fn ([*c]struct__XImage, c_long) callconv(.c) c_int = null,
};
pub const struct__XImage = extern struct {
    width: c_int = 0,
    height: c_int = 0,
    xoffset: c_int = 0,
    format: c_int = 0,
    data: [*c]u8 = null,
    byte_order: c_int = 0,
    bitmap_unit: c_int = 0,
    bitmap_bit_order: c_int = 0,
    bitmap_pad: c_int = 0,
    depth: c_int = 0,
    bytes_per_line: c_int = 0,
    bits_per_pixel: c_int = 0,
    red_mask: c_ulong = 0,
    green_mask: c_ulong = 0,
    blue_mask: c_ulong = 0,
    obdata: XPointer = null,
    f: struct_funcs_2 = @import("std").mem.zeroes(struct_funcs_2),
    pub const XInitImage = __root.XInitImage;
};
pub const XImage = struct__XImage;
pub const XWindowChanges = extern struct {
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    sibling: Window = 0,
    stack_mode: c_int = 0,
};
pub const XColor = extern struct {
    pixel: c_ulong = 0,
    red: c_ushort = 0,
    green: c_ushort = 0,
    blue: c_ushort = 0,
    flags: u8 = 0,
    pad: u8 = 0,
};
pub const XSegment = extern struct {
    x1: c_short = 0,
    y1: c_short = 0,
    x2: c_short = 0,
    y2: c_short = 0,
};
pub const XPoint = extern struct {
    x: c_short = 0,
    y: c_short = 0,
};
pub const XRectangle = extern struct {
    x: c_short = 0,
    y: c_short = 0,
    width: c_ushort = 0,
    height: c_ushort = 0,
};
pub const XArc = extern struct {
    x: c_short = 0,
    y: c_short = 0,
    width: c_ushort = 0,
    height: c_ushort = 0,
    angle1: c_short = 0,
    angle2: c_short = 0,
};
pub const XKeyboardControl = extern struct {
    key_click_percent: c_int = 0,
    bell_percent: c_int = 0,
    bell_pitch: c_int = 0,
    bell_duration: c_int = 0,
    led: c_int = 0,
    led_mode: c_int = 0,
    key: c_int = 0,
    auto_repeat_mode: c_int = 0,
};
pub const XKeyboardState = extern struct {
    key_click_percent: c_int = 0,
    bell_percent: c_int = 0,
    bell_pitch: c_uint = 0,
    bell_duration: c_uint = 0,
    led_mask: c_ulong = 0,
    global_auto_repeat: c_int = 0,
    auto_repeats: [32]u8 = @import("std").mem.zeroes([32]u8),
};
pub const XTimeCoord = extern struct {
    time: Time = 0,
    x: c_short = 0,
    y: c_short = 0,
};
pub const XModifierKeymap = extern struct {
    max_keypermod: c_int = 0,
    modifiermap: [*c]KeyCode = null,
    pub const XDeleteModifiermapEntry = __root.XDeleteModifiermapEntry;
    pub const XInsertModifiermapEntry = __root.XInsertModifiermapEntry;
    pub const XFreeModifiermap = __root.XFreeModifiermap;
};
pub const Display = struct__XDisplay;
pub const struct__XPrivate = opaque {};
pub const struct__XrmHashBucketRec = opaque {};
const struct_unnamed_3 = extern struct {
    ext_data: [*c]XExtData = null,
    private1: ?*struct__XPrivate = null,
    fd: c_int = 0,
    private2: c_int = 0,
    proto_major_version: c_int = 0,
    proto_minor_version: c_int = 0,
    vendor: [*c]u8 = null,
    private3: XID = 0,
    private4: XID = 0,
    private5: XID = 0,
    private6: c_int = 0,
    resource_alloc: ?*const fn (?*struct__XDisplay) callconv(.c) XID = null,
    byte_order: c_int = 0,
    bitmap_unit: c_int = 0,
    bitmap_pad: c_int = 0,
    bitmap_bit_order: c_int = 0,
    nformats: c_int = 0,
    pixmap_format: [*c]ScreenFormat = null,
    private8: c_int = 0,
    release: c_int = 0,
    private9: ?*struct__XPrivate = null,
    private10: ?*struct__XPrivate = null,
    qlen: c_int = 0,
    last_request_read: c_ulong = 0,
    request: c_ulong = 0,
    private11: XPointer = null,
    private12: XPointer = null,
    private13: XPointer = null,
    private14: XPointer = null,
    max_request_size: c_uint = 0,
    db: ?*struct__XrmHashBucketRec = null,
    private15: ?*const fn (?*struct__XDisplay) callconv(.c) c_int = null,
    display_name: [*c]u8 = null,
    default_screen: c_int = 0,
    nscreens: c_int = 0,
    screens: [*c]Screen = null,
    motion_buffer: c_ulong = 0,
    private16: c_ulong = 0,
    min_keycode: c_int = 0,
    max_keycode: c_int = 0,
    private17: XPointer = null,
    private18: XPointer = null,
    private19: c_int = 0,
    xdefaults: [*c]u8 = null,
};
pub const _XPrivDisplay = [*c]struct_unnamed_3;
pub const XKeyEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    root: Window = 0,
    subwindow: Window = 0,
    time: Time = 0,
    x: c_int = 0,
    y: c_int = 0,
    x_root: c_int = 0,
    y_root: c_int = 0,
    state: c_uint = 0,
    keycode: c_uint = 0,
    same_screen: c_int = 0,
    pub const XLookupKeysym = __root.XLookupKeysym;
};
pub const XKeyPressedEvent = XKeyEvent;
pub const XKeyReleasedEvent = XKeyEvent;
pub const XButtonEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    root: Window = 0,
    subwindow: Window = 0,
    time: Time = 0,
    x: c_int = 0,
    y: c_int = 0,
    x_root: c_int = 0,
    y_root: c_int = 0,
    state: c_uint = 0,
    button: c_uint = 0,
    same_screen: c_int = 0,
};
pub const XButtonPressedEvent = XButtonEvent;
pub const XButtonReleasedEvent = XButtonEvent;
pub const XMotionEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    root: Window = 0,
    subwindow: Window = 0,
    time: Time = 0,
    x: c_int = 0,
    y: c_int = 0,
    x_root: c_int = 0,
    y_root: c_int = 0,
    state: c_uint = 0,
    is_hint: u8 = 0,
    same_screen: c_int = 0,
};
pub const XPointerMovedEvent = XMotionEvent;
pub const XCrossingEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    root: Window = 0,
    subwindow: Window = 0,
    time: Time = 0,
    x: c_int = 0,
    y: c_int = 0,
    x_root: c_int = 0,
    y_root: c_int = 0,
    mode: c_int = 0,
    detail: c_int = 0,
    same_screen: c_int = 0,
    focus: c_int = 0,
    state: c_uint = 0,
};
pub const XEnterWindowEvent = XCrossingEvent;
pub const XLeaveWindowEvent = XCrossingEvent;
pub const XFocusChangeEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    mode: c_int = 0,
    detail: c_int = 0,
};
pub const XFocusInEvent = XFocusChangeEvent;
pub const XFocusOutEvent = XFocusChangeEvent;
pub const XKeymapEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    key_vector: [32]u8 = @import("std").mem.zeroes([32]u8),
};
pub const XExposeEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    count: c_int = 0,
};
pub const XGraphicsExposeEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    drawable: Drawable = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    count: c_int = 0,
    major_code: c_int = 0,
    minor_code: c_int = 0,
};
pub const XNoExposeEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    drawable: Drawable = 0,
    major_code: c_int = 0,
    minor_code: c_int = 0,
};
pub const XVisibilityEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    state: c_int = 0,
};
pub const XCreateWindowEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    parent: Window = 0,
    window: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    override_redirect: c_int = 0,
};
pub const XDestroyWindowEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
};
pub const XUnmapEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    from_configure: c_int = 0,
};
pub const XMapEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    override_redirect: c_int = 0,
};
pub const XMapRequestEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    parent: Window = 0,
    window: Window = 0,
};
pub const XReparentEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    parent: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
    override_redirect: c_int = 0,
};
pub const XConfigureEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    above: Window = 0,
    override_redirect: c_int = 0,
};
pub const XGravityEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
};
pub const XResizeRequestEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    width: c_int = 0,
    height: c_int = 0,
};
pub const XConfigureRequestEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    parent: Window = 0,
    window: Window = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    above: Window = 0,
    detail: c_int = 0,
    value_mask: c_ulong = 0,
};
pub const XCirculateEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    event: Window = 0,
    window: Window = 0,
    place: c_int = 0,
};
pub const XCirculateRequestEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    parent: Window = 0,
    window: Window = 0,
    place: c_int = 0,
};
pub const XPropertyEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    atom: Atom = 0,
    time: Time = 0,
    state: c_int = 0,
};
pub const XSelectionClearEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    selection: Atom = 0,
    time: Time = 0,
};
pub const XSelectionRequestEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    owner: Window = 0,
    requestor: Window = 0,
    selection: Atom = 0,
    target: Atom = 0,
    property: Atom = 0,
    time: Time = 0,
};
pub const XSelectionEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    requestor: Window = 0,
    selection: Atom = 0,
    target: Atom = 0,
    property: Atom = 0,
    time: Time = 0,
};
pub const XColormapEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    colormap: Colormap = 0,
    new: c_int = 0,
    state: c_int = 0,
};
const union_unnamed_4 = extern union {
    b: [20]u8,
    s: [10]c_short,
    l: [5]c_long,
};
pub const XClientMessageEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    message_type: Atom = 0,
    format: c_int = 0,
    data: union_unnamed_4 = @import("std").mem.zeroes(union_unnamed_4),
};
pub const XMappingEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
    request: c_int = 0,
    first_keycode: c_int = 0,
    count: c_int = 0,
    pub const XRefreshKeyboardMapping = __root.XRefreshKeyboardMapping;
};
pub const XErrorEvent = extern struct {
    type: c_int = 0,
    display: ?*Display = null,
    resourceid: XID = 0,
    serial: c_ulong = 0,
    error_code: u8 = 0,
    request_code: u8 = 0,
    minor_code: u8 = 0,
};
pub const XAnyEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    window: Window = 0,
};
pub const XGenericEvent = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    extension: c_int = 0,
    evtype: c_int = 0,
};
pub const XGenericEventCookie = extern struct {
    type: c_int = 0,
    serial: c_ulong = 0,
    send_event: c_int = 0,
    display: ?*Display = null,
    extension: c_int = 0,
    evtype: c_int = 0,
    cookie: c_uint = 0,
    data: ?*anyopaque = null,
};
pub const union__XEvent = extern union {
    type: c_int,
    xany: XAnyEvent,
    xkey: XKeyEvent,
    xbutton: XButtonEvent,
    xmotion: XMotionEvent,
    xcrossing: XCrossingEvent,
    xfocus: XFocusChangeEvent,
    xexpose: XExposeEvent,
    xgraphicsexpose: XGraphicsExposeEvent,
    xnoexpose: XNoExposeEvent,
    xvisibility: XVisibilityEvent,
    xcreatewindow: XCreateWindowEvent,
    xdestroywindow: XDestroyWindowEvent,
    xunmap: XUnmapEvent,
    xmap: XMapEvent,
    xmaprequest: XMapRequestEvent,
    xreparent: XReparentEvent,
    xconfigure: XConfigureEvent,
    xgravity: XGravityEvent,
    xresizerequest: XResizeRequestEvent,
    xconfigurerequest: XConfigureRequestEvent,
    xcirculate: XCirculateEvent,
    xcirculaterequest: XCirculateRequestEvent,
    xproperty: XPropertyEvent,
    xselectionclear: XSelectionClearEvent,
    xselectionrequest: XSelectionRequestEvent,
    xselection: XSelectionEvent,
    xcolormap: XColormapEvent,
    xclient: XClientMessageEvent,
    xmapping: XMappingEvent,
    xerror: XErrorEvent,
    xkeymap: XKeymapEvent,
    xgeneric: XGenericEvent,
    xcookie: XGenericEventCookie,
    pad: [24]c_long,
    pub const XFilterEvent = __root.XFilterEvent;
};
pub const XEvent = union__XEvent;
pub const XCharStruct = extern struct {
    lbearing: c_short = 0,
    rbearing: c_short = 0,
    width: c_short = 0,
    ascent: c_short = 0,
    descent: c_short = 0,
    attributes: c_ushort = 0,
};
pub const XFontProp = extern struct {
    name: Atom = 0,
    card32: c_ulong = 0,
};
pub const XFontStruct = extern struct {
    ext_data: [*c]XExtData = null,
    fid: Font = 0,
    direction: c_uint = 0,
    min_char_or_byte2: c_uint = 0,
    max_char_or_byte2: c_uint = 0,
    min_byte1: c_uint = 0,
    max_byte1: c_uint = 0,
    all_chars_exist: c_int = 0,
    default_char: c_uint = 0,
    n_properties: c_int = 0,
    properties: [*c]XFontProp = null,
    min_bounds: XCharStruct = @import("std").mem.zeroes(XCharStruct),
    max_bounds: XCharStruct = @import("std").mem.zeroes(XCharStruct),
    per_char: [*c]XCharStruct = null,
    ascent: c_int = 0,
    descent: c_int = 0,
    pub const XGetFontProperty = __root.XGetFontProperty;
    pub const XTextExtents = __root.XTextExtents;
    pub const XTextExtents16 = __root.XTextExtents16;
    pub const XTextWidth = __root.XTextWidth;
    pub const XTextWidth16 = __root.XTextWidth16;
};
pub const XTextItem = extern struct {
    chars: [*c]u8 = null,
    nchars: c_int = 0,
    delta: c_int = 0,
    font: Font = 0,
};
pub const XChar2b = extern struct {
    byte1: u8 = 0,
    byte2: u8 = 0,
};
pub const XTextItem16 = extern struct {
    chars: [*c]XChar2b = null,
    nchars: c_int = 0,
    delta: c_int = 0,
    font: Font = 0,
};
pub const XEDataObject = extern union {
    display: ?*Display,
    gc: GC,
    visual: [*c]Visual,
    screen: [*c]Screen,
    pixmap_format: [*c]ScreenFormat,
    font: [*c]XFontStruct,
    pub const XEHeadOfExtensionList = __root.XEHeadOfExtensionList;
};
pub const XFontSetExtents = extern struct {
    max_ink_extent: XRectangle = @import("std").mem.zeroes(XRectangle),
    max_logical_extent: XRectangle = @import("std").mem.zeroes(XRectangle),
};
pub const struct__XOM = opaque {
    pub const XCloseOM = __root.XCloseOM;
    pub const XSetOMValues = __root.XSetOMValues;
    pub const XGetOMValues = __root.XGetOMValues;
    pub const XDisplayOfOM = __root.XDisplayOfOM;
    pub const XLocaleOfOM = __root.XLocaleOfOM;
    pub const XCreateOC = __root.XCreateOC;
};
pub const XOM = ?*struct__XOM;
pub const struct__XOC = opaque {
    pub const XDestroyOC = __root.XDestroyOC;
    pub const XOMOfOC = __root.XOMOfOC;
    pub const XSetOCValues = __root.XSetOCValues;
    pub const XGetOCValues = __root.XGetOCValues;
    pub const XFontsOfFontSet = __root.XFontsOfFontSet;
    pub const XBaseFontNameListOfFontSet = __root.XBaseFontNameListOfFontSet;
    pub const XLocaleOfFontSet = __root.XLocaleOfFontSet;
    pub const XContextDependentDrawing = __root.XContextDependentDrawing;
    pub const XDirectionalDependentDrawing = __root.XDirectionalDependentDrawing;
    pub const XContextualDrawing = __root.XContextualDrawing;
    pub const XExtentsOfFontSet = __root.XExtentsOfFontSet;
    pub const XmbTextEscapement = __root.XmbTextEscapement;
    pub const XwcTextEscapement = __root.XwcTextEscapement;
    pub const Xutf8TextEscapement = __root.Xutf8TextEscapement;
    pub const XmbTextExtents = __root.XmbTextExtents;
    pub const XwcTextExtents = __root.XwcTextExtents;
    pub const Xutf8TextExtents = __root.Xutf8TextExtents;
    pub const XmbTextPerCharExtents = __root.XmbTextPerCharExtents;
    pub const XwcTextPerCharExtents = __root.XwcTextPerCharExtents;
    pub const Xutf8TextPerCharExtents = __root.Xutf8TextPerCharExtents;
};
pub const XOC = ?*struct__XOC;
pub const XFontSet = ?*struct__XOC;
pub const XmbTextItem = extern struct {
    chars: [*c]u8 = null,
    nchars: c_int = 0,
    delta: c_int = 0,
    font_set: XFontSet = null,
};
pub const XwcTextItem = extern struct {
    chars: [*c]wchar_t = null,
    nchars: c_int = 0,
    delta: c_int = 0,
    font_set: XFontSet = null,
};
pub const XOMCharSetList = extern struct {
    charset_count: c_int = 0,
    charset_list: [*c][*c]u8 = null,
};
pub const XOMOrientation_LTR_TTB: c_int = 0;
pub const XOMOrientation_RTL_TTB: c_int = 1;
pub const XOMOrientation_TTB_LTR: c_int = 2;
pub const XOMOrientation_TTB_RTL: c_int = 3;
pub const XOMOrientation_Context: c_int = 4;
pub const XOrientation = c_uint;
pub const XOMOrientation = extern struct {
    num_orientation: c_int = 0,
    orientation: [*c]XOrientation = null,
};
pub const XOMFontInfo = extern struct {
    num_font: c_int = 0,
    font_struct_list: [*c][*c]XFontStruct = null,
    font_name_list: [*c][*c]u8 = null,
};
pub const struct__XIM = opaque {
    pub const XCloseIM = __root.XCloseIM;
    pub const XGetIMValues = __root.XGetIMValues;
    pub const XSetIMValues = __root.XSetIMValues;
    pub const XDisplayOfIM = __root.XDisplayOfIM;
    pub const XLocaleOfIM = __root.XLocaleOfIM;
    pub const XCreateIC = __root.XCreateIC;
};
pub const XIM = ?*struct__XIM;
pub const struct__XIC = opaque {
    pub const XDestroyIC = __root.XDestroyIC;
    pub const XSetICFocus = __root.XSetICFocus;
    pub const XUnsetICFocus = __root.XUnsetICFocus;
    pub const XwcResetIC = __root.XwcResetIC;
    pub const XmbResetIC = __root.XmbResetIC;
    pub const Xutf8ResetIC = __root.Xutf8ResetIC;
    pub const XSetICValues = __root.XSetICValues;
    pub const XGetICValues = __root.XGetICValues;
    pub const XIMOfIC = __root.XIMOfIC;
    pub const XmbLookupString = __root.XmbLookupString;
    pub const XwcLookupString = __root.XwcLookupString;
    pub const Xutf8LookupString = __root.Xutf8LookupString;
};
pub const XIC = ?*struct__XIC;
pub const XIMProc = ?*const fn (XIM, XPointer, XPointer) callconv(.c) void;
pub const XICProc = ?*const fn (XIC, XPointer, XPointer) callconv(.c) c_int;
pub const XIDProc = ?*const fn (?*Display, XPointer, XPointer) callconv(.c) void;
pub const XIMStyle = c_ulong;
pub const XIMStyles = extern struct {
    count_styles: c_ushort = 0,
    supported_styles: [*c]XIMStyle = null,
};
pub const XVaNestedList = ?*anyopaque;
pub const XIMCallback = extern struct {
    client_data: XPointer = null,
    callback: XIMProc = null,
};
pub const XICCallback = extern struct {
    client_data: XPointer = null,
    callback: XICProc = null,
};
pub const XIMFeedback = c_ulong;
const union_unnamed_5 = extern union {
    multi_byte: [*c]u8,
    wide_char: [*c]wchar_t,
};
pub const struct__XIMText = extern struct {
    length: c_ushort = 0,
    feedback: [*c]XIMFeedback = null,
    encoding_is_wchar: c_int = 0,
    string: union_unnamed_5 = @import("std").mem.zeroes(union_unnamed_5),
};
pub const XIMText = struct__XIMText;
pub const XIMPreeditState = c_ulong;
pub const struct__XIMPreeditStateNotifyCallbackStruct = extern struct {
    state: XIMPreeditState = 0,
};
pub const XIMPreeditStateNotifyCallbackStruct = struct__XIMPreeditStateNotifyCallbackStruct;
pub const XIMResetState = c_ulong;
pub const XIMStringConversionFeedback = c_ulong;
const union_unnamed_6 = extern union {
    mbs: [*c]u8,
    wcs: [*c]wchar_t,
};
pub const struct__XIMStringConversionText = extern struct {
    length: c_ushort = 0,
    feedback: [*c]XIMStringConversionFeedback = null,
    encoding_is_wchar: c_int = 0,
    string: union_unnamed_6 = @import("std").mem.zeroes(union_unnamed_6),
};
pub const XIMStringConversionText = struct__XIMStringConversionText;
pub const XIMStringConversionPosition = c_ushort;
pub const XIMStringConversionType = c_ushort;
pub const XIMStringConversionOperation = c_ushort;
pub const XIMForwardChar: c_int = 0;
pub const XIMBackwardChar: c_int = 1;
pub const XIMForwardWord: c_int = 2;
pub const XIMBackwardWord: c_int = 3;
pub const XIMCaretUp: c_int = 4;
pub const XIMCaretDown: c_int = 5;
pub const XIMNextLine: c_int = 6;
pub const XIMPreviousLine: c_int = 7;
pub const XIMLineStart: c_int = 8;
pub const XIMLineEnd: c_int = 9;
pub const XIMAbsolutePosition: c_int = 10;
pub const XIMDontChange: c_int = 11;
pub const XIMCaretDirection = c_uint;
pub const struct__XIMStringConversionCallbackStruct = extern struct {
    position: XIMStringConversionPosition = 0,
    direction: XIMCaretDirection = @import("std").mem.zeroes(XIMCaretDirection),
    operation: XIMStringConversionOperation = 0,
    factor: c_ushort = 0,
    text: [*c]XIMStringConversionText = null,
};
pub const XIMStringConversionCallbackStruct = struct__XIMStringConversionCallbackStruct;
pub const struct__XIMPreeditDrawCallbackStruct = extern struct {
    caret: c_int = 0,
    chg_first: c_int = 0,
    chg_length: c_int = 0,
    text: [*c]XIMText = null,
};
pub const XIMPreeditDrawCallbackStruct = struct__XIMPreeditDrawCallbackStruct;
pub const XIMIsInvisible: c_int = 0;
pub const XIMIsPrimary: c_int = 1;
pub const XIMIsSecondary: c_int = 2;
pub const XIMCaretStyle = c_uint;
pub const struct__XIMPreeditCaretCallbackStruct = extern struct {
    position: c_int = 0,
    direction: XIMCaretDirection = @import("std").mem.zeroes(XIMCaretDirection),
    style: XIMCaretStyle = @import("std").mem.zeroes(XIMCaretStyle),
};
pub const XIMPreeditCaretCallbackStruct = struct__XIMPreeditCaretCallbackStruct;
pub const XIMTextType: c_int = 0;
pub const XIMBitmapType: c_int = 1;
pub const XIMStatusDataType = c_uint;
const union_unnamed_7 = extern union {
    text: [*c]XIMText,
    bitmap: Pixmap,
};
pub const struct__XIMStatusDrawCallbackStruct = extern struct {
    type: XIMStatusDataType = @import("std").mem.zeroes(XIMStatusDataType),
    data: union_unnamed_7 = @import("std").mem.zeroes(union_unnamed_7),
};
pub const XIMStatusDrawCallbackStruct = struct__XIMStatusDrawCallbackStruct;
pub const struct__XIMHotKeyTrigger = extern struct {
    keysym: KeySym = 0,
    modifier: c_int = 0,
    modifier_mask: c_int = 0,
};
pub const XIMHotKeyTrigger = struct__XIMHotKeyTrigger;
pub const struct__XIMHotKeyTriggers = extern struct {
    num_hot_key: c_int = 0,
    key: [*c]XIMHotKeyTrigger = null,
};
pub const XIMHotKeyTriggers = struct__XIMHotKeyTriggers;
pub const XIMHotKeyState = c_ulong;
pub const XIMValuesList = extern struct {
    count_values: c_ushort = 0,
    supported_values: [*c][*c]u8 = null,
};
pub extern var _Xdebug: c_int;
pub extern fn XLoadQueryFont(?*Display, [*c]const u8) [*c]XFontStruct;
pub extern fn XQueryFont(?*Display, XID) [*c]XFontStruct;
pub extern fn XGetMotionEvents(?*Display, Window, Time, Time, [*c]c_int) [*c]XTimeCoord;
pub extern fn XDeleteModifiermapEntry([*c]XModifierKeymap, KeyCode, c_int) [*c]XModifierKeymap;
pub extern fn XGetModifierMapping(?*Display) [*c]XModifierKeymap;
pub extern fn XInsertModifiermapEntry([*c]XModifierKeymap, KeyCode, c_int) [*c]XModifierKeymap;
pub extern fn XNewModifiermap(c_int) [*c]XModifierKeymap;
pub extern fn XCreateImage(?*Display, [*c]Visual, c_uint, c_int, c_int, [*c]u8, c_uint, c_uint, c_int, c_int) [*c]XImage;
pub extern fn XInitImage([*c]XImage) c_int;
pub extern fn XGetImage(?*Display, Drawable, c_int, c_int, c_uint, c_uint, c_ulong, c_int) [*c]XImage;
pub extern fn XGetSubImage(?*Display, Drawable, c_int, c_int, c_uint, c_uint, c_ulong, c_int, [*c]XImage, c_int, c_int) [*c]XImage;
pub extern fn XOpenDisplay([*c]const u8) ?*Display;
pub extern fn XrmInitialize() void;
pub extern fn XFetchBytes(?*Display, [*c]c_int) [*c]u8;
pub extern fn XFetchBuffer(?*Display, [*c]c_int, c_int) [*c]u8;
pub extern fn XGetAtomName(?*Display, Atom) [*c]u8;
pub extern fn XGetAtomNames(?*Display, [*c]Atom, c_int, [*c][*c]u8) c_int;
pub extern fn XGetDefault(?*Display, [*c]const u8, [*c]const u8) [*c]u8;
pub extern fn XDisplayName([*c]const u8) [*c]u8;
pub extern fn XKeysymToString(KeySym) [*c]u8;
pub extern fn XSynchronize(?*Display, c_int) ?*const fn (?*Display) callconv(.c) c_int;
pub extern fn XSetAfterFunction(?*Display, ?*const fn (?*Display) callconv(.c) c_int) ?*const fn (?*Display) callconv(.c) c_int;
pub extern fn XInternAtom(?*Display, [*c]const u8, c_int) Atom;
pub extern fn XInternAtoms(?*Display, [*c][*c]u8, c_int, c_int, [*c]Atom) c_int;
pub extern fn XCopyColormapAndFree(?*Display, Colormap) Colormap;
pub extern fn XCreateColormap(?*Display, Window, [*c]Visual, c_int) Colormap;
pub extern fn XCreatePixmapCursor(?*Display, Pixmap, Pixmap, [*c]XColor, [*c]XColor, c_uint, c_uint) Cursor;
pub extern fn XCreateGlyphCursor(?*Display, Font, Font, c_uint, c_uint, [*c]const XColor, [*c]const XColor) Cursor;
pub extern fn XCreateFontCursor(?*Display, c_uint) Cursor;
pub extern fn XLoadFont(?*Display, [*c]const u8) Font;
pub extern fn XCreateGC(?*Display, Drawable, c_ulong, [*c]XGCValues) GC;
pub extern fn XGContextFromGC(GC) GContext;
pub extern fn XFlushGC(?*Display, GC) void;
pub extern fn XCreatePixmap(?*Display, Drawable, c_uint, c_uint, c_uint) Pixmap;
pub extern fn XCreateBitmapFromData(?*Display, Drawable, [*c]const u8, c_uint, c_uint) Pixmap;
pub extern fn XCreatePixmapFromBitmapData(?*Display, Drawable, [*c]u8, c_uint, c_uint, c_ulong, c_ulong, c_uint) Pixmap;
pub extern fn XCreateSimpleWindow(?*Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_ulong, c_ulong) Window;
pub extern fn XGetSelectionOwner(?*Display, Atom) Window;
pub extern fn XCreateWindow(?*Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_int, c_uint, [*c]Visual, c_ulong, [*c]XSetWindowAttributes) Window;
pub extern fn XListInstalledColormaps(?*Display, Window, [*c]c_int) [*c]Colormap;
pub extern fn XListFonts(?*Display, [*c]const u8, c_int, [*c]c_int) [*c][*c]u8;
pub extern fn XListFontsWithInfo(?*Display, [*c]const u8, c_int, [*c]c_int, [*c][*c]XFontStruct) [*c][*c]u8;
pub extern fn XGetFontPath(?*Display, [*c]c_int) [*c][*c]u8;
pub extern fn XListExtensions(?*Display, [*c]c_int) [*c][*c]u8;
pub extern fn XListProperties(?*Display, Window, [*c]c_int) [*c]Atom;
pub extern fn XListHosts(?*Display, [*c]c_int, [*c]c_int) [*c]XHostAddress;
pub extern fn XKeycodeToKeysym(?*Display, KeyCode, c_int) KeySym;
pub extern fn XLookupKeysym([*c]XKeyEvent, c_int) KeySym;
pub extern fn XGetKeyboardMapping(?*Display, KeyCode, c_int, [*c]c_int) [*c]KeySym;
pub extern fn XStringToKeysym([*c]const u8) KeySym;
pub extern fn XMaxRequestSize(?*Display) c_long;
pub extern fn XExtendedMaxRequestSize(?*Display) c_long;
pub extern fn XResourceManagerString(?*Display) [*c]u8;
pub extern fn XScreenResourceString([*c]Screen) [*c]u8;
pub extern fn XDisplayMotionBufferSize(?*Display) c_ulong;
pub extern fn XVisualIDFromVisual([*c]Visual) VisualID;
pub extern fn XInitThreads() c_int;
pub extern fn XFreeThreads() c_int;
pub extern fn XLockDisplay(?*Display) void;
pub extern fn XUnlockDisplay(?*Display) void;
pub extern fn XInitExtension(?*Display, [*c]const u8) [*c]XExtCodes;
pub extern fn XAddExtension(?*Display) [*c]XExtCodes;
pub extern fn XFindOnExtensionList([*c][*c]XExtData, c_int) [*c]XExtData;
pub extern fn XEHeadOfExtensionList(XEDataObject) [*c][*c]XExtData;
pub extern fn XRootWindow(?*Display, c_int) Window;
pub extern fn XDefaultRootWindow(?*Display) Window;
pub extern fn XRootWindowOfScreen([*c]Screen) Window;
pub extern fn XDefaultVisual(?*Display, c_int) [*c]Visual;
pub extern fn XDefaultVisualOfScreen([*c]Screen) [*c]Visual;
pub extern fn XDefaultGC(?*Display, c_int) GC;
pub extern fn XDefaultGCOfScreen([*c]Screen) GC;
pub extern fn XBlackPixel(?*Display, c_int) c_ulong;
pub extern fn XWhitePixel(?*Display, c_int) c_ulong;
pub extern fn XAllPlanes() c_ulong;
pub extern fn XBlackPixelOfScreen([*c]Screen) c_ulong;
pub extern fn XWhitePixelOfScreen([*c]Screen) c_ulong;
pub extern fn XNextRequest(?*Display) c_ulong;
pub extern fn XLastKnownRequestProcessed(?*Display) c_ulong;
pub extern fn XServerVendor(?*Display) [*c]u8;
pub extern fn XDisplayString(?*Display) [*c]u8;
pub extern fn XDefaultColormap(?*Display, c_int) Colormap;
pub extern fn XDefaultColormapOfScreen([*c]Screen) Colormap;
pub extern fn XDisplayOfScreen([*c]Screen) ?*Display;
pub extern fn XScreenOfDisplay(?*Display, c_int) [*c]Screen;
pub extern fn XDefaultScreenOfDisplay(?*Display) [*c]Screen;
pub extern fn XEventMaskOfScreen([*c]Screen) c_long;
pub extern fn XScreenNumberOfScreen([*c]Screen) c_int;
pub const XErrorHandler = ?*const fn (?*Display, [*c]XErrorEvent) callconv(.c) c_int;
pub extern fn XSetErrorHandler(XErrorHandler) XErrorHandler;
pub const XIOErrorHandler = ?*const fn (?*Display) callconv(.c) c_int;
pub extern fn XSetIOErrorHandler(XIOErrorHandler) XIOErrorHandler;
pub const XIOErrorExitHandler = ?*const fn (?*Display, ?*anyopaque) callconv(.c) void;
pub extern fn XSetIOErrorExitHandler(?*Display, XIOErrorExitHandler, ?*anyopaque) void;
pub extern fn XListPixmapFormats(?*Display, [*c]c_int) [*c]XPixmapFormatValues;
pub extern fn XListDepths(?*Display, c_int, [*c]c_int) [*c]c_int;
pub extern fn XReconfigureWMWindow(?*Display, Window, c_int, c_uint, [*c]XWindowChanges) c_int;
pub extern fn XGetWMProtocols(?*Display, Window, [*c][*c]Atom, [*c]c_int) c_int;
pub extern fn XSetWMProtocols(?*Display, Window, [*c]Atom, c_int) c_int;
pub extern fn XIconifyWindow(?*Display, Window, c_int) c_int;
pub extern fn XWithdrawWindow(?*Display, Window, c_int) c_int;
pub extern fn XGetCommand(?*Display, Window, [*c][*c][*c]u8, [*c]c_int) c_int;
pub extern fn XGetWMColormapWindows(?*Display, Window, [*c][*c]Window, [*c]c_int) c_int;
pub extern fn XSetWMColormapWindows(?*Display, Window, [*c]Window, c_int) c_int;
pub extern fn XFreeStringList([*c][*c]u8) void;
pub extern fn XSetTransientForHint(?*Display, Window, Window) c_int;
pub extern fn XActivateScreenSaver(?*Display) c_int;
pub extern fn XAddHost(?*Display, [*c]XHostAddress) c_int;
pub extern fn XAddHosts(?*Display, [*c]XHostAddress, c_int) c_int;
pub extern fn XAddToExtensionList([*c][*c]struct__XExtData, [*c]XExtData) c_int;
pub extern fn XAddToSaveSet(?*Display, Window) c_int;
pub extern fn XAllocColor(?*Display, Colormap, [*c]XColor) c_int;
pub extern fn XAllocColorCells(?*Display, Colormap, c_int, [*c]c_ulong, c_uint, [*c]c_ulong, c_uint) c_int;
pub extern fn XAllocColorPlanes(?*Display, Colormap, c_int, [*c]c_ulong, c_int, c_int, c_int, c_int, [*c]c_ulong, [*c]c_ulong, [*c]c_ulong) c_int;
pub extern fn XAllocNamedColor(?*Display, Colormap, [*c]const u8, [*c]XColor, [*c]XColor) c_int;
pub extern fn XAllowEvents(?*Display, c_int, Time) c_int;
pub extern fn XAutoRepeatOff(?*Display) c_int;
pub extern fn XAutoRepeatOn(?*Display) c_int;
pub extern fn XBell(?*Display, c_int) c_int;
pub extern fn XBitmapBitOrder(?*Display) c_int;
pub extern fn XBitmapPad(?*Display) c_int;
pub extern fn XBitmapUnit(?*Display) c_int;
pub extern fn XCellsOfScreen([*c]Screen) c_int;
pub extern fn XChangeActivePointerGrab(?*Display, c_uint, Cursor, Time) c_int;
pub extern fn XChangeGC(?*Display, GC, c_ulong, [*c]XGCValues) c_int;
pub extern fn XChangeKeyboardControl(?*Display, c_ulong, [*c]XKeyboardControl) c_int;
pub extern fn XChangeKeyboardMapping(?*Display, c_int, c_int, [*c]KeySym, c_int) c_int;
pub extern fn XChangePointerControl(?*Display, c_int, c_int, c_int, c_int, c_int) c_int;
pub extern fn XChangeProperty(?*Display, Window, Atom, Atom, c_int, c_int, [*c]const u8, c_int) c_int;
pub extern fn XChangeSaveSet(?*Display, Window, c_int) c_int;
pub extern fn XChangeWindowAttributes(?*Display, Window, c_ulong, [*c]XSetWindowAttributes) c_int;
pub extern fn XCheckIfEvent(?*Display, [*c]XEvent, ?*const fn (?*Display, [*c]XEvent, XPointer) callconv(.c) c_int, XPointer) c_int;
pub extern fn XCheckMaskEvent(?*Display, c_long, [*c]XEvent) c_int;
pub extern fn XCheckTypedEvent(?*Display, c_int, [*c]XEvent) c_int;
pub extern fn XCheckTypedWindowEvent(?*Display, Window, c_int, [*c]XEvent) c_int;
pub extern fn XCheckWindowEvent(?*Display, Window, c_long, [*c]XEvent) c_int;
pub extern fn XCirculateSubwindows(?*Display, Window, c_int) c_int;
pub extern fn XCirculateSubwindowsDown(?*Display, Window) c_int;
pub extern fn XCirculateSubwindowsUp(?*Display, Window) c_int;
pub extern fn XClearArea(?*Display, Window, c_int, c_int, c_uint, c_uint, c_int) c_int;
pub extern fn XClearWindow(?*Display, Window) c_int;
pub extern fn XCloseDisplay(?*Display) c_int;
pub extern fn XConfigureWindow(?*Display, Window, c_uint, [*c]XWindowChanges) c_int;
pub extern fn XConnectionNumber(?*Display) c_int;
pub extern fn XConvertSelection(?*Display, Atom, Atom, Atom, Window, Time) c_int;
pub extern fn XCopyArea(?*Display, Drawable, Drawable, GC, c_int, c_int, c_uint, c_uint, c_int, c_int) c_int;
pub extern fn XCopyGC(?*Display, GC, c_ulong, GC) c_int;
pub extern fn XCopyPlane(?*Display, Drawable, Drawable, GC, c_int, c_int, c_uint, c_uint, c_int, c_int, c_ulong) c_int;
pub extern fn XDefaultDepth(?*Display, c_int) c_int;
pub extern fn XDefaultDepthOfScreen([*c]Screen) c_int;
pub extern fn XDefaultScreen(?*Display) c_int;
pub extern fn XDefineCursor(?*Display, Window, Cursor) c_int;
pub extern fn XDeleteProperty(?*Display, Window, Atom) c_int;
pub extern fn XDestroyWindow(?*Display, Window) c_int;
pub extern fn XDestroySubwindows(?*Display, Window) c_int;
pub extern fn XDoesBackingStore([*c]Screen) c_int;
pub extern fn XDoesSaveUnders([*c]Screen) c_int;
pub extern fn XDisableAccessControl(?*Display) c_int;
pub extern fn XDisplayCells(?*Display, c_int) c_int;
pub extern fn XDisplayHeight(?*Display, c_int) c_int;
pub extern fn XDisplayHeightMM(?*Display, c_int) c_int;
pub extern fn XDisplayKeycodes(?*Display, [*c]c_int, [*c]c_int) c_int;
pub extern fn XDisplayPlanes(?*Display, c_int) c_int;
pub extern fn XDisplayWidth(?*Display, c_int) c_int;
pub extern fn XDisplayWidthMM(?*Display, c_int) c_int;
pub extern fn XDrawArc(?*Display, Drawable, GC, c_int, c_int, c_uint, c_uint, c_int, c_int) c_int;
pub extern fn XDrawArcs(?*Display, Drawable, GC, [*c]XArc, c_int) c_int;
pub extern fn XDrawImageString(?*Display, Drawable, GC, c_int, c_int, [*c]const u8, c_int) c_int;
pub extern fn XDrawImageString16(?*Display, Drawable, GC, c_int, c_int, [*c]const XChar2b, c_int) c_int;
pub extern fn XDrawLine(?*Display, Drawable, GC, c_int, c_int, c_int, c_int) c_int;
pub extern fn XDrawLines(?*Display, Drawable, GC, [*c]XPoint, c_int, c_int) c_int;
pub extern fn XDrawPoint(?*Display, Drawable, GC, c_int, c_int) c_int;
pub extern fn XDrawPoints(?*Display, Drawable, GC, [*c]XPoint, c_int, c_int) c_int;
pub extern fn XDrawRectangle(?*Display, Drawable, GC, c_int, c_int, c_uint, c_uint) c_int;
pub extern fn XDrawRectangles(?*Display, Drawable, GC, [*c]XRectangle, c_int) c_int;
pub extern fn XDrawSegments(?*Display, Drawable, GC, [*c]XSegment, c_int) c_int;
pub extern fn XDrawString(?*Display, Drawable, GC, c_int, c_int, [*c]const u8, c_int) c_int;
pub extern fn XDrawString16(?*Display, Drawable, GC, c_int, c_int, [*c]const XChar2b, c_int) c_int;
pub extern fn XDrawText(?*Display, Drawable, GC, c_int, c_int, [*c]XTextItem, c_int) c_int;
pub extern fn XDrawText16(?*Display, Drawable, GC, c_int, c_int, [*c]XTextItem16, c_int) c_int;
pub extern fn XEnableAccessControl(?*Display) c_int;
pub extern fn XEventsQueued(?*Display, c_int) c_int;
pub extern fn XFetchName(?*Display, Window, [*c][*c]u8) c_int;
pub extern fn XFillArc(?*Display, Drawable, GC, c_int, c_int, c_uint, c_uint, c_int, c_int) c_int;
pub extern fn XFillArcs(?*Display, Drawable, GC, [*c]XArc, c_int) c_int;
pub extern fn XFillPolygon(?*Display, Drawable, GC, [*c]XPoint, c_int, c_int, c_int) c_int;
pub extern fn XFillRectangle(?*Display, Drawable, GC, c_int, c_int, c_uint, c_uint) c_int;
pub extern fn XFillRectangles(?*Display, Drawable, GC, [*c]XRectangle, c_int) c_int;
pub extern fn XFlush(?*Display) c_int;
pub extern fn XForceScreenSaver(?*Display, c_int) c_int;
pub extern fn XFree(?*anyopaque) c_int;
pub extern fn XFreeColormap(?*Display, Colormap) c_int;
pub extern fn XFreeColors(?*Display, Colormap, [*c]c_ulong, c_int, c_ulong) c_int;
pub extern fn XFreeCursor(?*Display, Cursor) c_int;
pub extern fn XFreeExtensionList([*c][*c]u8) c_int;
pub extern fn XFreeFont(?*Display, [*c]XFontStruct) c_int;
pub extern fn XFreeFontInfo([*c][*c]u8, [*c]XFontStruct, c_int) c_int;
pub extern fn XFreeFontNames([*c][*c]u8) c_int;
pub extern fn XFreeFontPath([*c][*c]u8) c_int;
pub extern fn XFreeGC(?*Display, GC) c_int;
pub extern fn XFreeModifiermap([*c]XModifierKeymap) c_int;
pub extern fn XFreePixmap(?*Display, Pixmap) c_int;
pub extern fn XGeometry(?*Display, c_int, [*c]const u8, [*c]const u8, c_uint, c_uint, c_uint, c_int, c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int) c_int;
pub extern fn XGetErrorDatabaseText(?*Display, [*c]const u8, [*c]const u8, [*c]const u8, [*c]u8, c_int) c_int;
pub extern fn XGetErrorText(?*Display, c_int, [*c]u8, c_int) c_int;
pub extern fn XGetFontProperty([*c]XFontStruct, Atom, [*c]c_ulong) c_int;
pub extern fn XGetGCValues(?*Display, GC, c_ulong, [*c]XGCValues) c_int;
pub extern fn XGetGeometry(?*Display, Drawable, [*c]Window, [*c]c_int, [*c]c_int, [*c]c_uint, [*c]c_uint, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XGetIconName(?*Display, Window, [*c][*c]u8) c_int;
pub extern fn XGetInputFocus(?*Display, [*c]Window, [*c]c_int) c_int;
pub extern fn XGetKeyboardControl(?*Display, [*c]XKeyboardState) c_int;
pub extern fn XGetPointerControl(?*Display, [*c]c_int, [*c]c_int, [*c]c_int) c_int;
pub extern fn XGetPointerMapping(?*Display, [*c]u8, c_int) c_int;
pub extern fn XGetScreenSaver(?*Display, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int) c_int;
pub extern fn XGetTransientForHint(?*Display, Window, [*c]Window) c_int;
pub extern fn XGetWindowProperty(?*Display, Window, Atom, c_long, c_long, c_int, Atom, [*c]Atom, [*c]c_int, [*c]c_ulong, [*c]c_ulong, [*c][*c]u8) c_int;
pub extern fn XGetWindowAttributes(?*Display, Window, [*c]XWindowAttributes) c_int;
pub extern fn XGrabButton(?*Display, c_uint, c_uint, Window, c_int, c_uint, c_int, c_int, Window, Cursor) c_int;
pub extern fn XGrabKey(?*Display, c_int, c_uint, Window, c_int, c_int, c_int) c_int;
pub extern fn XGrabKeyboard(?*Display, Window, c_int, c_int, c_int, Time) c_int;
pub extern fn XGrabPointer(?*Display, Window, c_int, c_uint, c_int, c_int, Window, Cursor, Time) c_int;
pub extern fn XGrabServer(?*Display) c_int;
pub extern fn XHeightMMOfScreen([*c]Screen) c_int;
pub extern fn XHeightOfScreen([*c]Screen) c_int;
pub extern fn XIfEvent(?*Display, [*c]XEvent, ?*const fn (?*Display, [*c]XEvent, XPointer) callconv(.c) c_int, XPointer) c_int;
pub extern fn XImageByteOrder(?*Display) c_int;
pub extern fn XInstallColormap(?*Display, Colormap) c_int;
pub extern fn XKeysymToKeycode(?*Display, KeySym) KeyCode;
pub extern fn XKillClient(?*Display, XID) c_int;
pub extern fn XLookupColor(?*Display, Colormap, [*c]const u8, [*c]XColor, [*c]XColor) c_int;
pub extern fn XLowerWindow(?*Display, Window) c_int;
pub extern fn XMapRaised(?*Display, Window) c_int;
pub extern fn XMapSubwindows(?*Display, Window) c_int;
pub extern fn XMapWindow(?*Display, Window) c_int;
pub extern fn XMaskEvent(?*Display, c_long, [*c]XEvent) c_int;
pub extern fn XMaxCmapsOfScreen([*c]Screen) c_int;
pub extern fn XMinCmapsOfScreen([*c]Screen) c_int;
pub extern fn XMoveResizeWindow(?*Display, Window, c_int, c_int, c_uint, c_uint) c_int;
pub extern fn XMoveWindow(?*Display, Window, c_int, c_int) c_int;
pub extern fn XNextEvent(?*Display, [*c]XEvent) c_int;
pub extern fn XNoOp(?*Display) c_int;
pub extern fn XParseColor(?*Display, Colormap, [*c]const u8, [*c]XColor) c_int;
pub extern fn XParseGeometry([*c]const u8, [*c]c_int, [*c]c_int, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XPeekEvent(?*Display, [*c]XEvent) c_int;
pub extern fn XPeekIfEvent(?*Display, [*c]XEvent, ?*const fn (?*Display, [*c]XEvent, XPointer) callconv(.c) c_int, XPointer) c_int;
pub extern fn XPending(?*Display) c_int;
pub extern fn XPlanesOfScreen([*c]Screen) c_int;
pub extern fn XProtocolRevision(?*Display) c_int;
pub extern fn XProtocolVersion(?*Display) c_int;
pub extern fn XPutBackEvent(?*Display, [*c]XEvent) c_int;
pub extern fn XPutImage(?*Display, Drawable, GC, [*c]XImage, c_int, c_int, c_int, c_int, c_uint, c_uint) c_int;
pub extern fn XQLength(?*Display) c_int;
pub extern fn XQueryBestCursor(?*Display, Drawable, c_uint, c_uint, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XQueryBestSize(?*Display, c_int, Drawable, c_uint, c_uint, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XQueryBestStipple(?*Display, Drawable, c_uint, c_uint, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XQueryBestTile(?*Display, Drawable, c_uint, c_uint, [*c]c_uint, [*c]c_uint) c_int;
pub extern fn XQueryColor(?*Display, Colormap, [*c]XColor) c_int;
pub extern fn XQueryColors(?*Display, Colormap, [*c]XColor, c_int) c_int;
pub extern fn XQueryExtension(?*Display, [*c]const u8, [*c]c_int, [*c]c_int, [*c]c_int) c_int;
pub extern fn XQueryKeymap(?*Display, [*c]u8) c_int;
pub extern fn XQueryPointer(?*Display, Window, [*c]Window, [*c]Window, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_uint) c_int;
pub extern fn XQueryTextExtents(?*Display, XID, [*c]const u8, c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]XCharStruct) c_int;
pub extern fn XQueryTextExtents16(?*Display, XID, [*c]const XChar2b, c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]XCharStruct) c_int;
pub extern fn XQueryTree(?*Display, Window, [*c]Window, [*c]Window, [*c][*c]Window, [*c]c_uint) c_int;
pub extern fn XRaiseWindow(?*Display, Window) c_int;
pub extern fn XReadBitmapFile(?*Display, Drawable, [*c]const u8, [*c]c_uint, [*c]c_uint, [*c]Pixmap, [*c]c_int, [*c]c_int) c_int;
pub extern fn XReadBitmapFileData([*c]const u8, [*c]c_uint, [*c]c_uint, [*c][*c]u8, [*c]c_int, [*c]c_int) c_int;
pub extern fn XRebindKeysym(?*Display, KeySym, [*c]KeySym, c_int, [*c]const u8, c_int) c_int;
pub extern fn XRecolorCursor(?*Display, Cursor, [*c]XColor, [*c]XColor) c_int;
pub extern fn XRefreshKeyboardMapping([*c]XMappingEvent) c_int;
pub extern fn XRemoveFromSaveSet(?*Display, Window) c_int;
pub extern fn XRemoveHost(?*Display, [*c]XHostAddress) c_int;
pub extern fn XRemoveHosts(?*Display, [*c]XHostAddress, c_int) c_int;
pub extern fn XReparentWindow(?*Display, Window, Window, c_int, c_int) c_int;
pub extern fn XResetScreenSaver(?*Display) c_int;
pub extern fn XResizeWindow(?*Display, Window, c_uint, c_uint) c_int;
pub extern fn XRestackWindows(?*Display, [*c]Window, c_int) c_int;
pub extern fn XRotateBuffers(?*Display, c_int) c_int;
pub extern fn XRotateWindowProperties(?*Display, Window, [*c]Atom, c_int, c_int) c_int;
pub extern fn XScreenCount(?*Display) c_int;
pub extern fn XSelectInput(?*Display, Window, c_long) c_int;
pub extern fn XSendEvent(?*Display, Window, c_int, c_long, [*c]XEvent) c_int;
pub extern fn XSetAccessControl(?*Display, c_int) c_int;
pub extern fn XSetArcMode(?*Display, GC, c_int) c_int;
pub extern fn XSetBackground(?*Display, GC, c_ulong) c_int;
pub extern fn XSetClipMask(?*Display, GC, Pixmap) c_int;
pub extern fn XSetClipOrigin(?*Display, GC, c_int, c_int) c_int;
pub extern fn XSetClipRectangles(?*Display, GC, c_int, c_int, [*c]XRectangle, c_int, c_int) c_int;
pub extern fn XSetCloseDownMode(?*Display, c_int) c_int;
pub extern fn XSetCommand(?*Display, Window, [*c][*c]u8, c_int) c_int;
pub extern fn XSetDashes(?*Display, GC, c_int, [*c]const u8, c_int) c_int;
pub extern fn XSetFillRule(?*Display, GC, c_int) c_int;
pub extern fn XSetFillStyle(?*Display, GC, c_int) c_int;
pub extern fn XSetFont(?*Display, GC, Font) c_int;
pub extern fn XSetFontPath(?*Display, [*c][*c]u8, c_int) c_int;
pub extern fn XSetForeground(?*Display, GC, c_ulong) c_int;
pub extern fn XSetFunction(?*Display, GC, c_int) c_int;
pub extern fn XSetGraphicsExposures(?*Display, GC, c_int) c_int;
pub extern fn XSetIconName(?*Display, Window, [*c]const u8) c_int;
pub extern fn XSetInputFocus(?*Display, Window, c_int, Time) c_int;
pub extern fn XSetLineAttributes(?*Display, GC, c_uint, c_int, c_int, c_int) c_int;
pub extern fn XSetModifierMapping(?*Display, [*c]XModifierKeymap) c_int;
pub extern fn XSetPlaneMask(?*Display, GC, c_ulong) c_int;
pub extern fn XSetPointerMapping(?*Display, [*c]const u8, c_int) c_int;
pub extern fn XSetScreenSaver(?*Display, c_int, c_int, c_int, c_int) c_int;
pub extern fn XSetSelectionOwner(?*Display, Atom, Window, Time) c_int;
pub extern fn XSetState(?*Display, GC, c_ulong, c_ulong, c_int, c_ulong) c_int;
pub extern fn XSetStipple(?*Display, GC, Pixmap) c_int;
pub extern fn XSetSubwindowMode(?*Display, GC, c_int) c_int;
pub extern fn XSetTSOrigin(?*Display, GC, c_int, c_int) c_int;
pub extern fn XSetTile(?*Display, GC, Pixmap) c_int;
pub extern fn XSetWindowBackground(?*Display, Window, c_ulong) c_int;
pub extern fn XSetWindowBackgroundPixmap(?*Display, Window, Pixmap) c_int;
pub extern fn XSetWindowBorder(?*Display, Window, c_ulong) c_int;
pub extern fn XSetWindowBorderPixmap(?*Display, Window, Pixmap) c_int;
pub extern fn XSetWindowBorderWidth(?*Display, Window, c_uint) c_int;
pub extern fn XSetWindowColormap(?*Display, Window, Colormap) c_int;
pub extern fn XStoreBuffer(?*Display, [*c]const u8, c_int, c_int) c_int;
pub extern fn XStoreBytes(?*Display, [*c]const u8, c_int) c_int;
pub extern fn XStoreColor(?*Display, Colormap, [*c]XColor) c_int;
pub extern fn XStoreColors(?*Display, Colormap, [*c]XColor, c_int) c_int;
pub extern fn XStoreName(?*Display, Window, [*c]const u8) c_int;
pub extern fn XStoreNamedColor(?*Display, Colormap, [*c]const u8, c_ulong, c_int) c_int;
pub extern fn XSync(?*Display, c_int) c_int;
pub extern fn XTextExtents([*c]XFontStruct, [*c]const u8, c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]XCharStruct) c_int;
pub extern fn XTextExtents16([*c]XFontStruct, [*c]const XChar2b, c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]XCharStruct) c_int;
pub extern fn XTextWidth([*c]XFontStruct, [*c]const u8, c_int) c_int;
pub extern fn XTextWidth16([*c]XFontStruct, [*c]const XChar2b, c_int) c_int;
pub extern fn XTranslateCoordinates(?*Display, Window, Window, c_int, c_int, [*c]c_int, [*c]c_int, [*c]Window) c_int;
pub extern fn XUndefineCursor(?*Display, Window) c_int;
pub extern fn XUngrabButton(?*Display, c_uint, c_uint, Window) c_int;
pub extern fn XUngrabKey(?*Display, c_int, c_uint, Window) c_int;
pub extern fn XUngrabKeyboard(?*Display, Time) c_int;
pub extern fn XUngrabPointer(?*Display, Time) c_int;
pub extern fn XUngrabServer(?*Display) c_int;
pub extern fn XUninstallColormap(?*Display, Colormap) c_int;
pub extern fn XUnloadFont(?*Display, Font) c_int;
pub extern fn XUnmapSubwindows(?*Display, Window) c_int;
pub extern fn XUnmapWindow(?*Display, Window) c_int;
pub extern fn XVendorRelease(?*Display) c_int;
pub extern fn XWarpPointer(?*Display, Window, Window, c_int, c_int, c_uint, c_uint, c_int, c_int) c_int;
pub extern fn XWidthMMOfScreen([*c]Screen) c_int;
pub extern fn XWidthOfScreen([*c]Screen) c_int;
pub extern fn XWindowEvent(?*Display, Window, c_long, [*c]XEvent) c_int;
pub extern fn XWriteBitmapFile(?*Display, [*c]const u8, Pixmap, c_uint, c_uint, c_int, c_int) c_int;
pub extern fn XSupportsLocale() c_int;
pub extern fn XSetLocaleModifiers([*c]const u8) [*c]u8;
pub extern fn XOpenOM(?*Display, ?*struct__XrmHashBucketRec, [*c]const u8, [*c]const u8) XOM;
pub extern fn XCloseOM(XOM) c_int;
pub extern fn XSetOMValues(XOM, ...) [*c]u8;
pub extern fn XGetOMValues(XOM, ...) [*c]u8;
pub extern fn XDisplayOfOM(XOM) ?*Display;
pub extern fn XLocaleOfOM(XOM) [*c]u8;
pub extern fn XCreateOC(XOM, ...) XOC;
pub extern fn XDestroyOC(XOC) void;
pub extern fn XOMOfOC(XOC) XOM;
pub extern fn XSetOCValues(XOC, ...) [*c]u8;
pub extern fn XGetOCValues(XOC, ...) [*c]u8;
pub extern fn XCreateFontSet(?*Display, [*c]const u8, [*c][*c][*c]u8, [*c]c_int, [*c][*c]u8) XFontSet;
pub extern fn XFreeFontSet(?*Display, XFontSet) void;
pub extern fn XFontsOfFontSet(XFontSet, [*c][*c][*c]XFontStruct, [*c][*c][*c]u8) c_int;
pub extern fn XBaseFontNameListOfFontSet(XFontSet) [*c]u8;
pub extern fn XLocaleOfFontSet(XFontSet) [*c]u8;
pub extern fn XContextDependentDrawing(XFontSet) c_int;
pub extern fn XDirectionalDependentDrawing(XFontSet) c_int;
pub extern fn XContextualDrawing(XFontSet) c_int;
pub extern fn XExtentsOfFontSet(XFontSet) [*c]XFontSetExtents;
pub extern fn XmbTextEscapement(XFontSet, [*c]const u8, c_int) c_int;
pub extern fn XwcTextEscapement(XFontSet, [*c]const wchar_t, c_int) c_int;
pub extern fn Xutf8TextEscapement(XFontSet, [*c]const u8, c_int) c_int;
pub extern fn XmbTextExtents(XFontSet, [*c]const u8, c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn XwcTextExtents(XFontSet, [*c]const wchar_t, c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn Xutf8TextExtents(XFontSet, [*c]const u8, c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn XmbTextPerCharExtents(XFontSet, [*c]const u8, c_int, [*c]XRectangle, [*c]XRectangle, c_int, [*c]c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn XwcTextPerCharExtents(XFontSet, [*c]const wchar_t, c_int, [*c]XRectangle, [*c]XRectangle, c_int, [*c]c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn Xutf8TextPerCharExtents(XFontSet, [*c]const u8, c_int, [*c]XRectangle, [*c]XRectangle, c_int, [*c]c_int, [*c]XRectangle, [*c]XRectangle) c_int;
pub extern fn XmbDrawText(?*Display, Drawable, GC, c_int, c_int, [*c]XmbTextItem, c_int) void;
pub extern fn XwcDrawText(?*Display, Drawable, GC, c_int, c_int, [*c]XwcTextItem, c_int) void;
pub extern fn Xutf8DrawText(?*Display, Drawable, GC, c_int, c_int, [*c]XmbTextItem, c_int) void;
pub extern fn XmbDrawString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const u8, c_int) void;
pub extern fn XwcDrawString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const wchar_t, c_int) void;
pub extern fn Xutf8DrawString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const u8, c_int) void;
pub extern fn XmbDrawImageString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const u8, c_int) void;
pub extern fn XwcDrawImageString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const wchar_t, c_int) void;
pub extern fn Xutf8DrawImageString(?*Display, Drawable, XFontSet, GC, c_int, c_int, [*c]const u8, c_int) void;
pub extern fn XOpenIM(?*Display, ?*struct__XrmHashBucketRec, [*c]u8, [*c]u8) XIM;
pub extern fn XCloseIM(XIM) c_int;
pub extern fn XGetIMValues(XIM, ...) [*c]u8;
pub extern fn XSetIMValues(XIM, ...) [*c]u8;
pub extern fn XDisplayOfIM(XIM) ?*Display;
pub extern fn XLocaleOfIM(XIM) [*c]u8;
pub extern fn XCreateIC(XIM, ...) XIC;
pub extern fn XDestroyIC(XIC) void;
pub extern fn XSetICFocus(XIC) void;
pub extern fn XUnsetICFocus(XIC) void;
pub extern fn XwcResetIC(XIC) [*c]wchar_t;
pub extern fn XmbResetIC(XIC) [*c]u8;
pub extern fn Xutf8ResetIC(XIC) [*c]u8;
pub extern fn XSetICValues(XIC, ...) [*c]u8;
pub extern fn XGetICValues(XIC, ...) [*c]u8;
pub extern fn XIMOfIC(XIC) XIM;
pub extern fn XFilterEvent([*c]XEvent, Window) c_int;
pub extern fn XmbLookupString(XIC, [*c]XKeyPressedEvent, [*c]u8, c_int, [*c]KeySym, [*c]c_int) c_int;
pub extern fn XwcLookupString(XIC, [*c]XKeyPressedEvent, [*c]wchar_t, c_int, [*c]KeySym, [*c]c_int) c_int;
pub extern fn Xutf8LookupString(XIC, [*c]XKeyPressedEvent, [*c]u8, c_int, [*c]KeySym, [*c]c_int) c_int;
pub extern fn XVaCreateNestedList(c_int, ...) XVaNestedList;
pub extern fn XRegisterIMInstantiateCallback(?*Display, ?*struct__XrmHashBucketRec, [*c]u8, [*c]u8, XIDProc, XPointer) c_int;
pub extern fn XUnregisterIMInstantiateCallback(?*Display, ?*struct__XrmHashBucketRec, [*c]u8, [*c]u8, XIDProc, XPointer) c_int;
pub const XConnectionWatchProc = ?*const fn (?*Display, XPointer, c_int, c_int, [*c]XPointer) callconv(.c) void;
pub extern fn XInternalConnectionNumbers(?*Display, [*c][*c]c_int, [*c]c_int) c_int;
pub extern fn XProcessInternalConnection(?*Display, c_int) void;
pub extern fn XAddConnectionWatch(?*Display, XConnectionWatchProc, XPointer) c_int;
pub extern fn XRemoveConnectionWatch(?*Display, XConnectionWatchProc, XPointer) void;
pub extern fn XSetAuthorization([*c]u8, c_int, [*c]u8, c_int) void;
pub extern fn _Xmbtowc([*c]wchar_t, [*c]u8, c_int) c_int;
pub extern fn _Xwctomb([*c]u8, wchar_t) c_int;
pub extern fn XGetEventData(?*Display, [*c]XGenericEventCookie) c_int;
pub extern fn XFreeEventData(?*Display, [*c]XGenericEventCookie) void;
pub const div_t = extern struct {
    quot: c_int = 0,
    rem: c_int = 0,
};
pub const ldiv_t = extern struct {
    quot: c_long = 0,
    rem: c_long = 0,
};
pub const lldiv_t = extern struct {
    quot: c_longlong = 0,
    rem: c_longlong = 0,
};
pub extern fn __ctype_get_mb_cur_max() usize;
pub extern fn atof(__nptr: [*c]const u8) f64;
pub extern fn atoi(__nptr: [*c]const u8) c_int;
pub extern fn atol(__nptr: [*c]const u8) c_long;
pub extern fn atoll(__nptr: [*c]const u8) c_longlong;
pub extern fn strtod(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f64;
pub extern fn strtof(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f32;
pub extern fn strtold(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) c_longdouble;
pub extern fn strtol(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_long;
pub extern fn strtoul(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulong;
pub extern fn strtoq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtouq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn strtoll(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtoull(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn l64a(__n: c_long) [*c]u8;
pub extern fn a64l(__s: [*c]const u8) c_long;
pub extern fn random() c_long;
pub extern fn srandom(__seed: c_uint) void;
pub extern fn initstate(__seed: c_uint, __statebuf: [*c]u8, __statelen: usize) [*c]u8;
pub extern fn setstate(__statebuf: [*c]u8) [*c]u8;
pub const struct_random_data = extern struct {
    fptr: [*c]i32 = null,
    rptr: [*c]i32 = null,
    state: [*c]i32 = null,
    rand_type: c_int = 0,
    rand_deg: c_int = 0,
    rand_sep: c_int = 0,
    end_ptr: [*c]i32 = null,
    pub const random_r = __root.random_r;
    pub const r = __root.random_r;
};
pub extern fn random_r(noalias __buf: [*c]struct_random_data, noalias __result: [*c]i32) c_int;
pub extern fn srandom_r(__seed: c_uint, __buf: [*c]struct_random_data) c_int;
pub extern fn initstate_r(__seed: c_uint, noalias __statebuf: [*c]u8, __statelen: usize, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn setstate_r(noalias __statebuf: [*c]u8, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn rand() c_int;
pub extern fn srand(__seed: c_uint) void;
pub extern fn rand_r(__seed: [*c]c_uint) c_int;
pub extern fn drand48() f64;
pub extern fn erand48(__xsubi: [*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn srand48(__seedval: c_long) void;
pub extern fn seed48(__seed16v: [*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48(__param: [*c]c_ushort) void;
pub const struct_drand48_data = extern struct {
    __x: [3]c_ushort = @import("std").mem.zeroes([3]c_ushort),
    __old_x: [3]c_ushort = @import("std").mem.zeroes([3]c_ushort),
    __c: c_ushort = 0,
    __init: c_ushort = 0,
    __a: c_ulonglong = 0,
    pub const drand48_r = __root.drand48_r;
    pub const lrand48_r = __root.lrand48_r;
    pub const mrand48_r = __root.mrand48_r;
    pub const r = __root.drand48_r;
};
pub extern fn drand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn erand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn lrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn nrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn mrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn jrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn srand48_r(__seedval: c_long, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn seed48_r(__seed16v: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn lcong48_r(__param: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn arc4random() __uint32_t;
pub extern fn arc4random_buf(__buf: ?*anyopaque, __size: usize) void;
pub extern fn arc4random_uniform(__upper_bound: __uint32_t) __uint32_t;
pub extern fn malloc(__size: usize) ?*anyopaque;
pub extern fn calloc(__nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn realloc(__ptr: ?*anyopaque, __size: usize) ?*anyopaque;
pub extern fn free(__ptr: ?*anyopaque) void;
pub extern fn reallocarray(__ptr: ?*anyopaque, __nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn alloca(__size: usize) ?*anyopaque;
pub extern fn valloc(__size: usize) ?*anyopaque;
pub extern fn posix_memalign(__memptr: [*c]?*anyopaque, __alignment: usize, __size: usize) c_int;
pub extern fn aligned_alloc(__alignment: usize, __size: usize) ?*anyopaque;
pub extern fn abort() noreturn;
pub extern fn atexit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn at_quick_exit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn on_exit(__func: ?*const fn (__status: c_int, __arg: ?*anyopaque) callconv(.c) void, __arg: ?*anyopaque) c_int;
pub extern fn exit(__status: c_int) noreturn;
pub extern fn quick_exit(__status: c_int) noreturn;
pub extern fn _Exit(__status: c_int) noreturn;
pub extern fn getenv(__name: [*c]const u8) [*c]u8;
pub extern fn putenv(__string: [*c]u8) c_int;
pub extern fn setenv(__name: [*c]const u8, __value: [*c]const u8, __replace: c_int) c_int;
pub extern fn unsetenv(__name: [*c]const u8) c_int;
pub extern fn clearenv() c_int;
pub extern fn mktemp(__template: [*c]u8) [*c]u8;
pub extern fn mkstemp(__template: [*c]u8) c_int;
pub extern fn mkstemps(__template: [*c]u8, __suffixlen: c_int) c_int;
pub extern fn mkdtemp(__template: [*c]u8) [*c]u8;
pub extern fn system(__command: [*c]const u8) c_int;
pub extern fn realpath(noalias __name: [*c]const u8, noalias __resolved: [*c]u8) [*c]u8;
pub const __compar_fn_t = ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;
pub extern fn bsearch(__key: ?*const anyopaque, __base: ?*const anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) ?*anyopaque;
pub extern fn qsort(__base: ?*anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) void;
pub extern fn abs(__x: c_int) c_int;
pub extern fn labs(__x: c_long) c_long;
pub extern fn llabs(__x: c_longlong) c_longlong;
pub extern fn div(__numer: c_int, __denom: c_int) div_t;
pub extern fn ldiv(__numer: c_long, __denom: c_long) ldiv_t;
pub extern fn lldiv(__numer: c_longlong, __denom: c_longlong) lldiv_t;
pub extern fn ecvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn fcvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn gcvt(__value: f64, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn qecvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qfcvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qgcvt(__value: c_longdouble, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn ecvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn fcvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qecvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qfcvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn mblen(__s: [*c]const u8, __n: usize) c_int;
pub extern fn mbtowc(noalias __pwc: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) c_int;
pub extern fn wctomb(__s: [*c]u8, __wchar: wchar_t) c_int;
pub extern fn mbstowcs(noalias __pwcs: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) usize;
pub extern fn wcstombs(noalias __s: [*c]u8, noalias __pwcs: [*c]const wchar_t, __n: usize) usize;
pub extern fn rpmatch(__response: [*c]const u8) c_int;
pub extern fn getsubopt(noalias __optionp: [*c][*c]u8, noalias __tokens: [*c]const [*c]u8, noalias __valuep: [*c][*c]u8) c_int;
pub extern fn getloadavg(__loadavg: [*c]f64, __nelem: c_int) c_int;

pub const __VERSION__ = "Aro aro-zig";
pub const __Aro__ = "";
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __GNUC__ = @as(c_int, 7);
pub const __GNUC_MINOR__ = @as(c_int, 1);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 0);
pub const __ARO_EMULATE_NO__ = @as(c_int, 0);
pub const __ARO_EMULATE_CLANG__ = @as(c_int, 1);
pub const __ARO_EMULATE_GCC__ = @as(c_int, 2);
pub const __ARO_EMULATE_MSVC__ = @as(c_int, 3);
pub const __ARO_EMULATE__ = __ARO_EMULATE_GCC__;
pub inline fn __building_module(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const linux = @as(c_int, 1);
pub const __linux = @as(c_int, 1);
pub const __linux__ = @as(c_int, 1);
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const __code_model_small__ = @as(c_int, 1);
pub const __amd64__ = @as(c_int, 1);
pub const __amd64 = @as(c_int, 1);
pub const __x86_64__ = @as(c_int, 1);
pub const __x86_64 = @as(c_int, 1);
pub const __SEG_GS = @as(c_int, 1);
pub const __SEG_FS = @as(c_int, 1);
pub const __seg_gs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:33:9
pub const __seg_fs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:34:9
pub const __LAHF_SAHF__ = @as(c_int, 1);
pub const __AES__ = @as(c_int, 1);
pub const __VAES__ = @as(c_int, 1);
pub const __PCLMUL__ = @as(c_int, 1);
pub const __VPCLMULQDQ__ = @as(c_int, 1);
pub const __LZCNT__ = @as(c_int, 1);
pub const __RDRND__ = @as(c_int, 1);
pub const __FSGSBASE__ = @as(c_int, 1);
pub const __BMI__ = @as(c_int, 1);
pub const __BMI2__ = @as(c_int, 1);
pub const __POPCNT__ = @as(c_int, 1);
pub const __PRFCHW__ = @as(c_int, 1);
pub const __RDSEED__ = @as(c_int, 1);
pub const __ADX__ = @as(c_int, 1);
pub const __MOVBE__ = @as(c_int, 1);
pub const __FMA__ = @as(c_int, 1);
pub const __F16C__ = @as(c_int, 1);
pub const __GFNI__ = @as(c_int, 1);
pub const __SHA__ = @as(c_int, 1);
pub const __FXSR__ = @as(c_int, 1);
pub const __XSAVE__ = @as(c_int, 1);
pub const __XSAVEOPT__ = @as(c_int, 1);
pub const __XSAVEC__ = @as(c_int, 1);
pub const __XSAVES__ = @as(c_int, 1);
pub const __PKU__ = @as(c_int, 1);
pub const __CLFLUSHOPT__ = @as(c_int, 1);
pub const __CLWB__ = @as(c_int, 1);
pub const __SHSTK__ = @as(c_int, 1);
pub const __KL__ = @as(c_int, 1);
pub const __WIDEKL__ = @as(c_int, 1);
pub const __RDPID__ = @as(c_int, 1);
pub const __WAITPKG__ = @as(c_int, 1);
pub const __MOVDIRI__ = @as(c_int, 1);
pub const __MOVDIR64B__ = @as(c_int, 1);
pub const __PTWRITE__ = @as(c_int, 1);
pub const __INVPCID__ = @as(c_int, 1);
pub const __HRESET__ = @as(c_int, 1);
pub const __AVXVNNI__ = @as(c_int, 1);
pub const __SERIALIZE__ = @as(c_int, 1);
pub const __CRC32__ = @as(c_int, 1);
pub const __AVX2__ = @as(c_int, 1);
pub const __AVX__ = @as(c_int, 1);
pub const __SSE4_2__ = @as(c_int, 1);
pub const __SSE4_1__ = @as(c_int, 1);
pub const __SSSE3__ = @as(c_int, 1);
pub const __SSE3__ = @as(c_int, 1);
pub const __SSE2__ = @as(c_int, 1);
pub const __SSE__ = @as(c_int, 1);
pub const __SSE_MATH__ = @as(c_int, 1);
pub const __MMX__ = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __SIZEOF_FLOAT128__ = @as(c_int, 16);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __FLOAT128__ = @as(c_int, 1);
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const __ELF__ = @as(c_int, 1);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __ATOMIC_BOOL_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WINT_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_SHORT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_INT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LLONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_POINTER_LOCK_FREE = @as(c_int, 1);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SCHAR_WIDTH__ = @as(c_int, 8);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __LONG_LONG_WIDTH__ = @as(c_int, 64);
pub const __WCHAR_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIG_ATOMIC_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __BITINT_MAXWIDTH__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 10);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_WINT_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTPTR_TYPE__ = c_long;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:162:9
pub const __INTMAX_C = __helpers.L_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:165:9
pub const __UINTMAX_C = __helpers.UL_SUFFIX;
pub const __PTRDIFF_TYPE__ = c_long;
pub const __SIZE_TYPE__ = c_ulong;
pub const __WCHAR_TYPE__ = c_int;
pub const __WINT_TYPE__ = c_uint;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub inline fn __INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub inline fn __INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub inline fn __INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT64_TYPE__ = c_long;
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:191:9
pub const __INT64_C = __helpers.L_SUFFIX;
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub inline fn __UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub inline fn __UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // <builtin>:216:9
pub const __UINT32_C = __helpers.U_SUFFIX;
pub const __UINT32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:225:9
pub const __UINT64_C = __helpers.UL_SUFFIX;
pub const __UINT64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const INT_LEAST8_FMTd__ = "hhd";
pub const INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const UINT_LEAST8_FMTo__ = "hho";
pub const UINT_LEAST8_FMTu__ = "hhu";
pub const UINT_LEAST8_FMTx__ = "hhx";
pub const UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const INT_FAST8_FMTd__ = "hhd";
pub const INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const UINT_FAST8_FMTo__ = "hho";
pub const UINT_FAST8_FMTu__ = "hhu";
pub const UINT_FAST8_FMTx__ = "hhx";
pub const UINT_FAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const INT_LEAST16_FMTd__ = "hd";
pub const INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST16_FMTo__ = "ho";
pub const UINT_LEAST16_FMTu__ = "hu";
pub const UINT_LEAST16_FMTx__ = "hx";
pub const UINT_LEAST16_FMTX__ = "hX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const INT_FAST16_FMTd__ = "hd";
pub const INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_FAST16_FMTo__ = "ho";
pub const UINT_FAST16_FMTu__ = "hu";
pub const UINT_FAST16_FMTx__ = "hx";
pub const UINT_FAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const INT_LEAST32_FMTd__ = "d";
pub const INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST32_FMTo__ = "o";
pub const UINT_LEAST32_FMTu__ = "u";
pub const UINT_LEAST32_FMTx__ = "x";
pub const UINT_LEAST32_FMTX__ = "X";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const INT_FAST32_FMTd__ = "d";
pub const INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_FAST32_FMTo__ = "o";
pub const UINT_FAST32_FMTu__ = "u";
pub const UINT_FAST32_FMTx__ = "x";
pub const UINT_FAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const INT_LEAST64_FMTd__ = "ld";
pub const INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_LEAST64_FMTo__ = "lo";
pub const UINT_LEAST64_FMTu__ = "lu";
pub const UINT_LEAST64_FMTx__ = "lx";
pub const UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const INT_FAST64_FMTd__ = "ld";
pub const INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_FMTo__ = "lo";
pub const UINT_FAST64_FMTu__ = "lu";
pub const UINT_FAST64_FMTx__ = "lx";
pub const UINT_FAST64_FMTX__ = "lX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_HAS_DENORM__ = "";
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = "";
pub const __FLT16_HAS_QUIET_NAN__ = "";
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = "";
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = "";
pub const __FLT_HAS_QUIET_NAN__ = "";
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = "";
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = "";
pub const __DBL_HAS_QUIET_NAN__ = "";
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = "";
pub const __LDBL_DIG__ = @as(c_int, 18);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 21);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = "";
pub const __LDBL_HAS_QUIET_NAN__ = "";
pub const __LDBL_MANT_DIG__ = @as(c_int, 64);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __FLT_EVAL_METHOD__ = @as(c_int, 0);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __pic__ = @as(c_int, 2);
pub const __PIC__ = @as(c_int, 2);
pub const __GLIBC_MINOR__ = @as(c_int, 43);
pub const _X11_XLIB_H_ = "";
pub const XlibSpecificationRelease = @as(c_int, 6);
pub const _SYS_TYPES_H = @as(c_int, 1);
pub const _FEATURES_H = @as(c_int, 1);
pub const __KERNEL_STRICT_NAMES = "";
pub inline fn __GNUC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub inline fn __glibc_clang_prereq(maj: anytype, min: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &maj;
    _ = &min;
    return @as(c_int, 0);
}
pub const __GLIBC_USE = @compileError("unable to translate macro: undefined identifier `__GLIBC_USE_`"); // /usr/include/features.h:197:9
pub const _DEFAULT_SOURCE = @as(c_int, 1);
pub const __GLIBC_USE_ISOC2Y = @as(c_int, 0);
pub const __GLIBC_USE_ISOC23 = @as(c_int, 0);
pub const __USE_ISOC11 = @as(c_int, 1);
pub const __USE_POSIX_IMPLICITLY = @as(c_int, 1);
pub const _POSIX_SOURCE = @as(c_int, 1);
pub const _POSIX_C_SOURCE = @as(c_long, 202405);
pub const __USE_POSIX = @as(c_int, 1);
pub const __USE_POSIX2 = @as(c_int, 1);
pub const __USE_POSIX199309 = @as(c_int, 1);
pub const __USE_POSIX199506 = @as(c_int, 1);
pub const __USE_XOPEN2K = @as(c_int, 1);
pub const __USE_ISOC95 = @as(c_int, 1);
pub const __USE_ISOC99 = @as(c_int, 1);
pub const __USE_XOPEN2K8 = @as(c_int, 1);
pub const _ATFILE_SOURCE = @as(c_int, 1);
pub const __USE_XOPEN2K24 = @as(c_int, 1);
pub const __WORDSIZE = @as(c_int, 64);
pub const __WORDSIZE_TIME64_COMPAT32 = @as(c_int, 1);
pub const __SYSCALL_WORDSIZE = @as(c_int, 64);
pub const __TIMESIZE = __WORDSIZE;
pub const __USE_TIME_BITS64 = @as(c_int, 1);
pub const __USE_MISC = @as(c_int, 1);
pub const __USE_ATFILE = @as(c_int, 1);
pub const __USE_FORTIFY_LEVEL = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_GETS = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_SCANF = @as(c_int, 0);
pub const __GLIBC_USE_C23_STRTOL = @as(c_int, 0);
pub const _STDC_PREDEF_H = @as(c_int, 1);
pub const __STDC_IEC_559__ = @as(c_int, 1);
pub const __STDC_IEC_60559_BFP__ = @as(c_long, 201404);
pub const __STDC_IEC_559_COMPLEX__ = @as(c_int, 1);
pub const __STDC_IEC_60559_COMPLEX__ = @as(c_long, 201404);
pub const __STDC_ISO_10646__ = @as(c_long, 201706);
pub const __GNU_LIBRARY__ = @as(c_int, 6);
pub const __GLIBC__ = @as(c_int, 2);
pub inline fn __GLIBC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub const _SYS_CDEFS_H = @as(c_int, 1);
pub const __glibc_has_attribute = @compileError("unable to translate macro: undefined identifier `__has_attribute`"); // /usr/include/sys/cdefs.h:45:10
pub inline fn __glibc_has_builtin(name: anytype) @TypeOf(__builtin.has_builtin(name)) {
    _ = &name;
    return __builtin.has_builtin(name);
}
pub const __glibc_has_extension = @compileError("unable to translate macro: undefined identifier `__has_extension`"); // /usr/include/sys/cdefs.h:55:10
pub const __LEAF = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:65:11
pub const __LEAF_ATTR = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:66:11
pub const __THROW = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:79:11
pub const __THROWNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:80:11
pub const __NTH = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:81:11
pub const __NTHNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:82:11
pub const __COLD = @compileError("unable to translate macro: undefined identifier `__cold__`"); // /usr/include/sys/cdefs.h:102:11
pub inline fn __P(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub inline fn __PMT(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token '##'"); // /usr/include/sys/cdefs.h:131:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token ''"); // /usr/include/sys/cdefs.h:132:9
pub const __ptr_t = ?*anyopaque;
pub const __BEGIN_DECLS = "";
pub const __END_DECLS = "";
pub const __attribute_overloadable__ = "";
pub inline fn __bos(ptr: anytype) @TypeOf(__builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1))) {
    _ = &ptr;
    return __builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1));
}
pub inline fn __bos0(ptr: anytype) @TypeOf(__builtin.object_size(ptr, @as(c_int, 0))) {
    _ = &ptr;
    return __builtin.object_size(ptr, @as(c_int, 0));
}
pub inline fn __glibc_objsize0(__o: anytype) @TypeOf(__bos0(__o)) {
    _ = &__o;
    return __bos0(__o);
}
pub inline fn __glibc_objsize(__o: anytype) @TypeOf(__bos(__o)) {
    _ = &__o;
    return __bos(__o);
}
pub const __warnattr = @compileError("unable to translate macro: undefined identifier `__warning__`"); // /usr/include/sys/cdefs.h:366:10
pub const __errordecl = @compileError("unable to translate macro: undefined identifier `__error__`"); // /usr/include/sys/cdefs.h:367:10
pub const __flexarr = @compileError("unable to translate C expr: unexpected token '['"); // /usr/include/sys/cdefs.h:379:10
pub const __glibc_c99_flexarr_available = @as(c_int, 1);
pub const __REDIRECT = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:410:10
pub const __REDIRECT_NTH = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:417:11
pub const __REDIRECT_NTHNL = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:419:11
pub const __ASMNAME = @compileError("unable to translate macro: undefined identifier `__USER_LABEL_PREFIX__`"); // /usr/include/sys/cdefs.h:422:10
pub inline fn __ASMNAME2(prefix: anytype, cname: anytype) @TypeOf(__STRING(prefix) ++ cname) {
    _ = &prefix;
    _ = &cname;
    return __STRING(prefix) ++ cname;
}
pub const __REDIRECT_FORTIFY = __REDIRECT;
pub const __REDIRECT_FORTIFY_NTH = __REDIRECT_NTH;
pub const __attribute_malloc__ = @compileError("unable to translate macro: undefined identifier `__malloc__`"); // /usr/include/sys/cdefs.h:452:10
pub const __attribute_alloc_size__ = @compileError("unable to translate macro: undefined identifier `__alloc_size__`"); // /usr/include/sys/cdefs.h:460:10
pub const __attribute_alloc_align__ = @compileError("unable to translate macro: undefined identifier `__alloc_align__`"); // /usr/include/sys/cdefs.h:469:10
pub const __attribute_pure__ = @compileError("unable to translate macro: undefined identifier `__pure__`"); // /usr/include/sys/cdefs.h:479:10
pub const __attribute_const__ = @compileError("unable to translate C expr: unexpected token '__attribute__'"); // /usr/include/sys/cdefs.h:486:10
pub const __attribute_maybe_unused__ = @compileError("unable to translate macro: undefined identifier `__unused__`"); // /usr/include/sys/cdefs.h:492:10
pub const __attribute_used__ = @compileError("unable to translate macro: undefined identifier `__used__`"); // /usr/include/sys/cdefs.h:501:10
pub const __attribute_noinline__ = @compileError("unable to translate macro: undefined identifier `__noinline__`"); // /usr/include/sys/cdefs.h:502:10
pub const __attribute_deprecated__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:510:10
pub const __attribute_deprecated_msg__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:520:10
pub const __attribute_format_arg__ = @compileError("unable to translate macro: undefined identifier `__format_arg__`"); // /usr/include/sys/cdefs.h:533:10
pub const __attribute_format_strfmon__ = @compileError("unable to translate macro: undefined identifier `__format__`"); // /usr/include/sys/cdefs.h:543:10
pub const __attribute_nonnull__ = @compileError("unable to translate macro: undefined identifier `__nonnull__`"); // /usr/include/sys/cdefs.h:555:11
pub inline fn __nonnull(params: anytype) @TypeOf(__attribute_nonnull__(params)) {
    _ = &params;
    return __attribute_nonnull__(params);
}
pub const __returns_nonnull = @compileError("unable to translate macro: undefined identifier `__returns_nonnull__`"); // /usr/include/sys/cdefs.h:568:10
pub const __attribute_warn_unused_result__ = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // /usr/include/sys/cdefs.h:577:10
pub const __wur = "";
pub const __always_inline = @compileError("unable to translate macro: undefined identifier `__always_inline__`"); // /usr/include/sys/cdefs.h:595:10
pub const __attribute_artificial__ = @compileError("unable to translate macro: undefined identifier `__artificial__`"); // /usr/include/sys/cdefs.h:604:10
pub const __extern_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:626:11
pub const __extern_always_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:627:11
pub const __fortify_function = __extern_always_inline ++ __attribute_artificial__;
pub const __va_arg_pack = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack`"); // /usr/include/sys/cdefs.h:638:10
pub const __va_arg_pack_len = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack_len`"); // /usr/include/sys/cdefs.h:639:10
pub const __restrict_arr = @compileError("unable to translate C expr: unexpected token '__restrict'"); // /usr/include/sys/cdefs.h:666:10
pub inline fn __glibc_unlikely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 0))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 0));
}
pub inline fn __glibc_likely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 1))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 1));
}
pub const __attribute_nonstring__ = "";
pub inline fn __attribute_copy__(arg: anytype) void {
    _ = &arg;
    return;
}
pub const __LDOUBLE_REDIRECTS_TO_FLOAT128_ABI = @as(c_int, 0);
pub inline fn __LDBL_REDIR1(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR(name: anytype, proto: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR1_NTH(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR_NTH(name: anytype, proto: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR2_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __LDBL_REDIR_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __REDIRECT_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT(name, proto, alias);
}
pub inline fn __REDIRECT_NTH_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT_NTH(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT_NTH(name, proto, alias);
}
pub const __glibc_macro_warning1 = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /usr/include/sys/cdefs.h:807:10
pub const __glibc_macro_warning = @compileError("unable to translate macro: undefined identifier `GCC`"); // /usr/include/sys/cdefs.h:808:10
pub const __HAVE_GENERIC_SELECTION = @as(c_int, 1);
pub const __glibc_const_generic = @compileError("unable to translate C expr: expected type instead got 'const'"); // /usr/include/sys/cdefs.h:837:10
pub inline fn __fortified_attr_access(a: anytype, o: anytype, s: anytype) void {
    _ = &a;
    _ = &o;
    _ = &s;
    return;
}
pub inline fn __attr_access(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __attr_access_none(argno: anytype) void {
    _ = &argno;
    return;
}
pub inline fn __attr_dealloc(dealloc: anytype, argno: anytype) void {
    _ = &dealloc;
    _ = &argno;
    return;
}
pub const __attr_dealloc_free = "";
pub const __attribute_returns_twice__ = @compileError("unable to translate macro: undefined identifier `__returns_twice__`"); // /usr/include/sys/cdefs.h:884:10
pub const __attribute_struct_may_alias__ = @compileError("unable to translate macro: undefined identifier `__may_alias__`"); // /usr/include/sys/cdefs.h:893:10
pub const __stub___compat_bdflush = "";
pub const __stub_chflags = "";
pub const __stub_fchflags = "";
pub const __stub_gtty = "";
pub const __stub_revoke = "";
pub const __stub_setlogin = "";
pub const __stub_sigreturn = "";
pub const __stub_stty = "";
pub const _BITS_TYPES_H = @as(c_int, 1);
pub const __S16_TYPE = c_short;
pub const __U16_TYPE = c_ushort;
pub const __S32_TYPE = c_int;
pub const __U32_TYPE = c_uint;
pub const __SLONGWORD_TYPE = c_long;
pub const __ULONGWORD_TYPE = c_ulong;
pub const __SQUAD_TYPE = c_long;
pub const __UQUAD_TYPE = c_ulong;
pub const __SWORD_TYPE = c_long;
pub const __UWORD_TYPE = c_ulong;
pub const __SLONG32_TYPE = c_int;
pub const __ULONG32_TYPE = c_uint;
pub const __S64_TYPE = c_long;
pub const __U64_TYPE = c_ulong;
pub const _BITS_TYPESIZES_H = @as(c_int, 1);
pub const __SYSCALL_SLONG_TYPE = __SLONGWORD_TYPE;
pub const __SYSCALL_ULONG_TYPE = __ULONGWORD_TYPE;
pub const __DEV_T_TYPE = __UQUAD_TYPE;
pub const __UID_T_TYPE = __U32_TYPE;
pub const __GID_T_TYPE = __U32_TYPE;
pub const __INO_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __INO64_T_TYPE = __UQUAD_TYPE;
pub const __MODE_T_TYPE = __U32_TYPE;
pub const __NLINK_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSWORD_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF64_T_TYPE = __SQUAD_TYPE;
pub const __PID_T_TYPE = __S32_TYPE;
pub const __RLIM_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __RLIM64_T_TYPE = __UQUAD_TYPE;
pub const __BLKCNT_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __BLKCNT64_T_TYPE = __SQUAD_TYPE;
pub const __FSBLKCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSBLKCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSFILCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSFILCNT64_T_TYPE = __UQUAD_TYPE;
pub const __ID_T_TYPE = __U32_TYPE;
pub const __CLOCK_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __TIME_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __USECONDS_T_TYPE = __U32_TYPE;
pub const __SUSECONDS_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __SUSECONDS64_T_TYPE = __SQUAD_TYPE;
pub const __DADDR_T_TYPE = __S32_TYPE;
pub const __KEY_T_TYPE = __S32_TYPE;
pub const __CLOCKID_T_TYPE = __S32_TYPE;
pub const __TIMER_T_TYPE = ?*anyopaque;
pub const __BLKSIZE_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __FSID_T_TYPE = @compileError("unable to translate macro: undefined identifier `__val`"); // /usr/include/bits/typesizes.h:73:9
pub const __SSIZE_T_TYPE = __SWORD_TYPE;
pub const __CPU_MASK_TYPE = __SYSCALL_ULONG_TYPE;
pub const __OFF_T_MATCHES_OFF64_T = @as(c_int, 1);
pub const __INO_T_MATCHES_INO64_T = @as(c_int, 1);
pub const __RLIM_T_MATCHES_RLIM64_T = @as(c_int, 1);
pub const __STATFS_MATCHES_STATFS64 = @as(c_int, 1);
pub const __KERNEL_OLD_TIMEVAL_MATCHES_TIMEVAL64 = @as(c_int, 1);
pub const __FD_SETSIZE = @as(c_int, 1024);
pub const _BITS_TIME64_H = @as(c_int, 1);
pub const __TIME64_T_TYPE = __TIME_T_TYPE;
pub const __u_char_defined = "";
pub const __ino_t_defined = "";
pub const __dev_t_defined = "";
pub const __gid_t_defined = "";
pub const __mode_t_defined = "";
pub const __nlink_t_defined = "";
pub const __uid_t_defined = "";
pub const __off_t_defined = "";
pub const __pid_t_defined = "";
pub const __id_t_defined = "";
pub const __ssize_t_defined = "";
pub const __daddr_t_defined = "";
pub const __key_t_defined = "";
pub const __clock_t_defined = @as(c_int, 1);
pub const __clockid_t_defined = @as(c_int, 1);
pub const __time_t_defined = @as(c_int, 1);
pub const __timer_t_defined = @as(c_int, 1);
pub const __need_size_t = "";
pub const __STDC_VERSION_STDDEF_H__ = @as(c_long, 202311);
pub const NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // /usr/lib/zig/compiler/aro/include/stddef.h:18:9
pub const _BITS_STDINT_INTN_H = @as(c_int, 1);
pub const __BIT_TYPES_DEFINED__ = @as(c_int, 1);
pub const _ENDIAN_H = @as(c_int, 1);
pub const _BITS_ENDIAN_H = @as(c_int, 1);
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __PDP_ENDIAN = @as(c_int, 3412);
pub const _BITS_ENDIANNESS_H = @as(c_int, 1);
pub const __BYTE_ORDER = __LITTLE_ENDIAN;
pub const __FLOAT_WORD_ORDER = __BYTE_ORDER;
pub inline fn __LONG_LONG_PAIR(HI: anytype, LO: anytype) @TypeOf(HI) {
    _ = &HI;
    _ = &LO;
    return blk: {
        _ = &LO;
        break :blk HI;
    };
}
pub const LITTLE_ENDIAN = __LITTLE_ENDIAN;
pub const BIG_ENDIAN = __BIG_ENDIAN;
pub const PDP_ENDIAN = __PDP_ENDIAN;
pub const BYTE_ORDER = __BYTE_ORDER;
pub const _BITS_BYTESWAP_H = @as(c_int, 1);
pub inline fn __bswap_constant_16(x: anytype) __uint16_t {
    _ = &x;
    return __helpers.cast(__uint16_t, ((x >> @as(c_int, 8)) & @as(c_int, 0xff)) | ((x & @as(c_int, 0xff)) << @as(c_int, 8)));
}
pub inline fn __bswap_constant_32(x: anytype) @TypeOf(((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24))) {
    _ = &x;
    return ((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24));
}
pub inline fn __bswap_constant_64(x: anytype) @TypeOf(((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56))) {
    _ = &x;
    return ((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56));
}
pub const _BITS_UINTN_IDENTITY_H = @as(c_int, 1);
pub inline fn htobe16(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn htole16(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn be16toh(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn le16toh(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn htobe32(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn htole32(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn be32toh(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn le32toh(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn htobe64(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn htole64(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub inline fn be64toh(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn le64toh(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub const _SYS_SELECT_H = @as(c_int, 1);
pub const __FD_ZERO = @compileError("unable to translate macro: undefined identifier `__i`"); // /usr/include/bits/select.h:25:9
pub const __FD_SET = @compileError("unable to translate C expr: expected ')' instead got '|='"); // /usr/include/bits/select.h:32:9
pub const __FD_CLR = @compileError("unable to translate C expr: expected ')' instead got '&='"); // /usr/include/bits/select.h:34:9
pub inline fn __FD_ISSET(d: anytype, s: anytype) @TypeOf((__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0)) {
    _ = &d;
    _ = &s;
    return (__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0);
}
pub const __sigset_t_defined = @as(c_int, 1);
pub const ____sigset_t_defined = "";
pub const _SIGSET_NWORDS = __helpers.div(@as(c_int, 1024), @as(c_int, 8) * __helpers.sizeof(c_ulong));
pub const __timeval_defined = @as(c_int, 1);
pub const _STRUCT_TIMESPEC = @as(c_int, 1);
pub const __suseconds_t_defined = "";
pub const __NFDBITS = @as(c_int, 8) * __helpers.cast(c_int, __helpers.sizeof(__fd_mask));
pub inline fn __FD_ELT(d: anytype) @TypeOf(__helpers.div(d, __NFDBITS)) {
    _ = &d;
    return __helpers.div(d, __NFDBITS);
}
pub inline fn __FD_MASK(d: anytype) __fd_mask {
    _ = &d;
    return __helpers.cast(__fd_mask, @as(c_ulong, 1) << __helpers.rem(d, __NFDBITS));
}
pub inline fn __FDS_BITS(set: anytype) @TypeOf(set.*.__fds_bits) {
    _ = &set;
    return set.*.__fds_bits;
}
pub const FD_SETSIZE = __FD_SETSIZE;
pub const NFDBITS = __NFDBITS;
pub inline fn FD_SET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_SET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_SET(fd, fdsetp);
}
pub inline fn FD_CLR(fd: anytype, fdsetp: anytype) @TypeOf(__FD_CLR(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_CLR(fd, fdsetp);
}
pub inline fn FD_ISSET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_ISSET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_ISSET(fd, fdsetp);
}
pub inline fn FD_ZERO(fdsetp: anytype) @TypeOf(__FD_ZERO(fdsetp)) {
    _ = &fdsetp;
    return __FD_ZERO(fdsetp);
}
pub const __blksize_t_defined = "";
pub const __blkcnt_t_defined = "";
pub const __fsblkcnt_t_defined = "";
pub const __fsfilcnt_t_defined = "";
pub const _BITS_PTHREADTYPES_COMMON_H = @as(c_int, 1);
pub const _THREAD_SHARED_TYPES_H = @as(c_int, 1);
pub const _BITS_PTHREADTYPES_ARCH_H = @as(c_int, 1);
pub const __SIZEOF_PTHREAD_MUTEX_T = @as(c_int, 40);
pub const __SIZEOF_PTHREAD_ATTR_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_RWLOCK_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_BARRIER_T = @as(c_int, 32);
pub const __SIZEOF_PTHREAD_MUTEXATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_COND_T = @as(c_int, 48);
pub const __SIZEOF_PTHREAD_CONDATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_RWLOCKATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_BARRIERATTR_T = @as(c_int, 4);
pub const __LOCK_ALIGNMENT = "";
pub const __ONCE_ALIGNMENT = "";
pub const _BITS_ATOMIC_WIDE_COUNTER_H = "";
pub const _THREAD_MUTEX_INTERNAL_H = @as(c_int, 1);
pub const __PTHREAD_MUTEX_HAVE_PREV = @as(c_int, 1);
pub const __PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/struct_mutex.h:55:10
pub const _RWLOCK_INTERNAL_H = "";
pub inline fn __PTHREAD_RWLOCK_INITIALIZER(__flags: anytype) @TypeOf(__flags) {
    _ = &__flags;
    return blk: {
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        break :blk __flags;
    };
}
pub const __ONCE_FLAG_INIT = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/thread-shared-types.h:114:9
pub const __have_pthread_attr_t = @as(c_int, 1);
pub const X_H = "";
pub const X_PROTOCOL = @as(c_int, 11);
pub const X_PROTOCOL_REVISION = @as(c_int, 0);
pub const _XTYPEDEF_XID = "";
pub const _XTYPEDEF_MASK = "";
pub const _XTYPEDEF_ATOM = "";
pub const _XTYPEDEF_FONT = "";
pub const None = @as(c_long, 0);
pub const ParentRelative = @as(c_long, 1);
pub const CopyFromParent = @as(c_long, 0);
pub const PointerWindow = @as(c_long, 0);
pub const InputFocus = @as(c_long, 1);
pub const PointerRoot = @as(c_long, 1);
pub const AnyPropertyType = @as(c_long, 0);
pub const AnyKey = @as(c_long, 0);
pub const AnyButton = @as(c_long, 0);
pub const AllTemporary = @as(c_long, 0);
pub const CurrentTime = @as(c_long, 0);
pub const NoSymbol = @as(c_long, 0);
pub const NoEventMask = @as(c_long, 0);
pub const KeyPressMask = @as(c_long, 1) << @as(c_int, 0);
pub const KeyReleaseMask = @as(c_long, 1) << @as(c_int, 1);
pub const ButtonPressMask = @as(c_long, 1) << @as(c_int, 2);
pub const ButtonReleaseMask = @as(c_long, 1) << @as(c_int, 3);
pub const EnterWindowMask = @as(c_long, 1) << @as(c_int, 4);
pub const LeaveWindowMask = @as(c_long, 1) << @as(c_int, 5);
pub const PointerMotionMask = @as(c_long, 1) << @as(c_int, 6);
pub const PointerMotionHintMask = @as(c_long, 1) << @as(c_int, 7);
pub const Button1MotionMask = @as(c_long, 1) << @as(c_int, 8);
pub const Button2MotionMask = @as(c_long, 1) << @as(c_int, 9);
pub const Button3MotionMask = @as(c_long, 1) << @as(c_int, 10);
pub const Button4MotionMask = @as(c_long, 1) << @as(c_int, 11);
pub const Button5MotionMask = @as(c_long, 1) << @as(c_int, 12);
pub const ButtonMotionMask = @as(c_long, 1) << @as(c_int, 13);
pub const KeymapStateMask = @as(c_long, 1) << @as(c_int, 14);
pub const ExposureMask = @as(c_long, 1) << @as(c_int, 15);
pub const VisibilityChangeMask = @as(c_long, 1) << @as(c_int, 16);
pub const StructureNotifyMask = @as(c_long, 1) << @as(c_int, 17);
pub const ResizeRedirectMask = @as(c_long, 1) << @as(c_int, 18);
pub const SubstructureNotifyMask = @as(c_long, 1) << @as(c_int, 19);
pub const SubstructureRedirectMask = @as(c_long, 1) << @as(c_int, 20);
pub const FocusChangeMask = @as(c_long, 1) << @as(c_int, 21);
pub const PropertyChangeMask = @as(c_long, 1) << @as(c_int, 22);
pub const ColormapChangeMask = @as(c_long, 1) << @as(c_int, 23);
pub const OwnerGrabButtonMask = @as(c_long, 1) << @as(c_int, 24);
pub const KeyPress = @as(c_int, 2);
pub const KeyRelease = @as(c_int, 3);
pub const ButtonPress = @as(c_int, 4);
pub const ButtonRelease = @as(c_int, 5);
pub const MotionNotify = @as(c_int, 6);
pub const EnterNotify = @as(c_int, 7);
pub const LeaveNotify = @as(c_int, 8);
pub const FocusIn = @as(c_int, 9);
pub const FocusOut = @as(c_int, 10);
pub const KeymapNotify = @as(c_int, 11);
pub const Expose = @as(c_int, 12);
pub const GraphicsExpose = @as(c_int, 13);
pub const NoExpose = @as(c_int, 14);
pub const VisibilityNotify = @as(c_int, 15);
pub const CreateNotify = @as(c_int, 16);
pub const DestroyNotify = @as(c_int, 17);
pub const UnmapNotify = @as(c_int, 18);
pub const MapNotify = @as(c_int, 19);
pub const MapRequest = @as(c_int, 20);
pub const ReparentNotify = @as(c_int, 21);
pub const ConfigureNotify = @as(c_int, 22);
pub const ConfigureRequest = @as(c_int, 23);
pub const GravityNotify = @as(c_int, 24);
pub const ResizeRequest = @as(c_int, 25);
pub const CirculateNotify = @as(c_int, 26);
pub const CirculateRequest = @as(c_int, 27);
pub const PropertyNotify = @as(c_int, 28);
pub const SelectionClear = @as(c_int, 29);
pub const SelectionRequest = @as(c_int, 30);
pub const SelectionNotify = @as(c_int, 31);
pub const ColormapNotify = @as(c_int, 32);
pub const ClientMessage = @as(c_int, 33);
pub const MappingNotify = @as(c_int, 34);
pub const GenericEvent = @as(c_int, 35);
pub const LASTEvent = @as(c_int, 36);
pub const ShiftMask = @as(c_int, 1) << @as(c_int, 0);
pub const LockMask = @as(c_int, 1) << @as(c_int, 1);
pub const ControlMask = @as(c_int, 1) << @as(c_int, 2);
pub const Mod1Mask = @as(c_int, 1) << @as(c_int, 3);
pub const Mod2Mask = @as(c_int, 1) << @as(c_int, 4);
pub const Mod3Mask = @as(c_int, 1) << @as(c_int, 5);
pub const Mod4Mask = @as(c_int, 1) << @as(c_int, 6);
pub const Mod5Mask = @as(c_int, 1) << @as(c_int, 7);
pub const ShiftMapIndex = @as(c_int, 0);
pub const LockMapIndex = @as(c_int, 1);
pub const ControlMapIndex = @as(c_int, 2);
pub const Mod1MapIndex = @as(c_int, 3);
pub const Mod2MapIndex = @as(c_int, 4);
pub const Mod3MapIndex = @as(c_int, 5);
pub const Mod4MapIndex = @as(c_int, 6);
pub const Mod5MapIndex = @as(c_int, 7);
pub const Button1Mask = @as(c_int, 1) << @as(c_int, 8);
pub const Button2Mask = @as(c_int, 1) << @as(c_int, 9);
pub const Button3Mask = @as(c_int, 1) << @as(c_int, 10);
pub const Button4Mask = @as(c_int, 1) << @as(c_int, 11);
pub const Button5Mask = @as(c_int, 1) << @as(c_int, 12);
pub const AnyModifier = @as(c_int, 1) << @as(c_int, 15);
pub const Button1 = @as(c_int, 1);
pub const Button2 = @as(c_int, 2);
pub const Button3 = @as(c_int, 3);
pub const Button4 = @as(c_int, 4);
pub const Button5 = @as(c_int, 5);
pub const NotifyNormal = @as(c_int, 0);
pub const NotifyGrab = @as(c_int, 1);
pub const NotifyUngrab = @as(c_int, 2);
pub const NotifyWhileGrabbed = @as(c_int, 3);
pub const NotifyHint = @as(c_int, 1);
pub const NotifyAncestor = @as(c_int, 0);
pub const NotifyVirtual = @as(c_int, 1);
pub const NotifyInferior = @as(c_int, 2);
pub const NotifyNonlinear = @as(c_int, 3);
pub const NotifyNonlinearVirtual = @as(c_int, 4);
pub const NotifyPointer = @as(c_int, 5);
pub const NotifyPointerRoot = @as(c_int, 6);
pub const NotifyDetailNone = @as(c_int, 7);
pub const VisibilityUnobscured = @as(c_int, 0);
pub const VisibilityPartiallyObscured = @as(c_int, 1);
pub const VisibilityFullyObscured = @as(c_int, 2);
pub const PlaceOnTop = @as(c_int, 0);
pub const PlaceOnBottom = @as(c_int, 1);
pub const FamilyInternet = @as(c_int, 0);
pub const FamilyDECnet = @as(c_int, 1);
pub const FamilyChaos = @as(c_int, 2);
pub const FamilyInternet6 = @as(c_int, 6);
pub const FamilyServerInterpreted = @as(c_int, 5);
pub const PropertyNewValue = @as(c_int, 0);
pub const PropertyDelete = @as(c_int, 1);
pub const ColormapUninstalled = @as(c_int, 0);
pub const ColormapInstalled = @as(c_int, 1);
pub const GrabModeSync = @as(c_int, 0);
pub const GrabModeAsync = @as(c_int, 1);
pub const GrabSuccess = @as(c_int, 0);
pub const AlreadyGrabbed = @as(c_int, 1);
pub const GrabInvalidTime = @as(c_int, 2);
pub const GrabNotViewable = @as(c_int, 3);
pub const GrabFrozen = @as(c_int, 4);
pub const AsyncPointer = @as(c_int, 0);
pub const SyncPointer = @as(c_int, 1);
pub const ReplayPointer = @as(c_int, 2);
pub const AsyncKeyboard = @as(c_int, 3);
pub const SyncKeyboard = @as(c_int, 4);
pub const ReplayKeyboard = @as(c_int, 5);
pub const AsyncBoth = @as(c_int, 6);
pub const SyncBoth = @as(c_int, 7);
pub const RevertToNone = __helpers.cast(c_int, None);
pub const RevertToPointerRoot = __helpers.cast(c_int, PointerRoot);
pub const RevertToParent = @as(c_int, 2);
pub const Success = @as(c_int, 0);
pub const BadRequest = @as(c_int, 1);
pub const BadValue = @as(c_int, 2);
pub const BadWindow = @as(c_int, 3);
pub const BadPixmap = @as(c_int, 4);
pub const BadAtom = @as(c_int, 5);
pub const BadCursor = @as(c_int, 6);
pub const BadFont = @as(c_int, 7);
pub const BadMatch = @as(c_int, 8);
pub const BadDrawable = @as(c_int, 9);
pub const BadAccess = @as(c_int, 10);
pub const BadAlloc = @as(c_int, 11);
pub const BadColor = @as(c_int, 12);
pub const BadGC = @as(c_int, 13);
pub const BadIDChoice = @as(c_int, 14);
pub const BadName = @as(c_int, 15);
pub const BadLength = @as(c_int, 16);
pub const BadImplementation = @as(c_int, 17);
pub const FirstExtensionError = @as(c_int, 128);
pub const LastExtensionError = @as(c_int, 255);
pub const InputOutput = @as(c_int, 1);
pub const InputOnly = @as(c_int, 2);
pub const CWBackPixmap = @as(c_long, 1) << @as(c_int, 0);
pub const CWBackPixel = @as(c_long, 1) << @as(c_int, 1);
pub const CWBorderPixmap = @as(c_long, 1) << @as(c_int, 2);
pub const CWBorderPixel = @as(c_long, 1) << @as(c_int, 3);
pub const CWBitGravity = @as(c_long, 1) << @as(c_int, 4);
pub const CWWinGravity = @as(c_long, 1) << @as(c_int, 5);
pub const CWBackingStore = @as(c_long, 1) << @as(c_int, 6);
pub const CWBackingPlanes = @as(c_long, 1) << @as(c_int, 7);
pub const CWBackingPixel = @as(c_long, 1) << @as(c_int, 8);
pub const CWOverrideRedirect = @as(c_long, 1) << @as(c_int, 9);
pub const CWSaveUnder = @as(c_long, 1) << @as(c_int, 10);
pub const CWEventMask = @as(c_long, 1) << @as(c_int, 11);
pub const CWDontPropagate = @as(c_long, 1) << @as(c_int, 12);
pub const CWColormap = @as(c_long, 1) << @as(c_int, 13);
pub const CWCursor = @as(c_long, 1) << @as(c_int, 14);
pub const CWX = @as(c_int, 1) << @as(c_int, 0);
pub const CWY = @as(c_int, 1) << @as(c_int, 1);
pub const CWWidth = @as(c_int, 1) << @as(c_int, 2);
pub const CWHeight = @as(c_int, 1) << @as(c_int, 3);
pub const CWBorderWidth = @as(c_int, 1) << @as(c_int, 4);
pub const CWSibling = @as(c_int, 1) << @as(c_int, 5);
pub const CWStackMode = @as(c_int, 1) << @as(c_int, 6);
pub const ForgetGravity = @as(c_int, 0);
pub const NorthWestGravity = @as(c_int, 1);
pub const NorthGravity = @as(c_int, 2);
pub const NorthEastGravity = @as(c_int, 3);
pub const WestGravity = @as(c_int, 4);
pub const CenterGravity = @as(c_int, 5);
pub const EastGravity = @as(c_int, 6);
pub const SouthWestGravity = @as(c_int, 7);
pub const SouthGravity = @as(c_int, 8);
pub const SouthEastGravity = @as(c_int, 9);
pub const StaticGravity = @as(c_int, 10);
pub const UnmapGravity = @as(c_int, 0);
pub const NotUseful = @as(c_int, 0);
pub const WhenMapped = @as(c_int, 1);
pub const Always = @as(c_int, 2);
pub const IsUnmapped = @as(c_int, 0);
pub const IsUnviewable = @as(c_int, 1);
pub const IsViewable = @as(c_int, 2);
pub const SetModeInsert = @as(c_int, 0);
pub const SetModeDelete = @as(c_int, 1);
pub const DestroyAll = @as(c_int, 0);
pub const RetainPermanent = @as(c_int, 1);
pub const RetainTemporary = @as(c_int, 2);
pub const Above = @as(c_int, 0);
pub const Below = @as(c_int, 1);
pub const TopIf = @as(c_int, 2);
pub const BottomIf = @as(c_int, 3);
pub const Opposite = @as(c_int, 4);
pub const RaiseLowest = @as(c_int, 0);
pub const LowerHighest = @as(c_int, 1);
pub const PropModeReplace = @as(c_int, 0);
pub const PropModePrepend = @as(c_int, 1);
pub const PropModeAppend = @as(c_int, 2);
pub const GXclear = @as(c_int, 0x0);
pub const GXand = @as(c_int, 0x1);
pub const GXandReverse = @as(c_int, 0x2);
pub const GXcopy = @as(c_int, 0x3);
pub const GXandInverted = @as(c_int, 0x4);
pub const GXnoop = @as(c_int, 0x5);
pub const GXxor = @as(c_int, 0x6);
pub const GXor = @as(c_int, 0x7);
pub const GXnor = @as(c_int, 0x8);
pub const GXequiv = @as(c_int, 0x9);
pub const GXinvert = @as(c_int, 0xa);
pub const GXorReverse = @as(c_int, 0xb);
pub const GXcopyInverted = @as(c_int, 0xc);
pub const GXorInverted = @as(c_int, 0xd);
pub const GXnand = @as(c_int, 0xe);
pub const GXset = @as(c_int, 0xf);
pub const LineSolid = @as(c_int, 0);
pub const LineOnOffDash = @as(c_int, 1);
pub const LineDoubleDash = @as(c_int, 2);
pub const CapNotLast = @as(c_int, 0);
pub const CapButt = @as(c_int, 1);
pub const CapRound = @as(c_int, 2);
pub const CapProjecting = @as(c_int, 3);
pub const JoinMiter = @as(c_int, 0);
pub const JoinRound = @as(c_int, 1);
pub const JoinBevel = @as(c_int, 2);
pub const FillSolid = @as(c_int, 0);
pub const FillTiled = @as(c_int, 1);
pub const FillStippled = @as(c_int, 2);
pub const FillOpaqueStippled = @as(c_int, 3);
pub const EvenOddRule = @as(c_int, 0);
pub const WindingRule = @as(c_int, 1);
pub const ClipByChildren = @as(c_int, 0);
pub const IncludeInferiors = @as(c_int, 1);
pub const Unsorted = @as(c_int, 0);
pub const YSorted = @as(c_int, 1);
pub const YXSorted = @as(c_int, 2);
pub const YXBanded = @as(c_int, 3);
pub const CoordModeOrigin = @as(c_int, 0);
pub const CoordModePrevious = @as(c_int, 1);
pub const Complex = @as(c_int, 0);
pub const Nonconvex = @as(c_int, 1);
pub const Convex = @as(c_int, 2);
pub const ArcChord = @as(c_int, 0);
pub const ArcPieSlice = @as(c_int, 1);
pub const GCFunction = @as(c_long, 1) << @as(c_int, 0);
pub const GCPlaneMask = @as(c_long, 1) << @as(c_int, 1);
pub const GCForeground = @as(c_long, 1) << @as(c_int, 2);
pub const GCBackground = @as(c_long, 1) << @as(c_int, 3);
pub const GCLineWidth = @as(c_long, 1) << @as(c_int, 4);
pub const GCLineStyle = @as(c_long, 1) << @as(c_int, 5);
pub const GCCapStyle = @as(c_long, 1) << @as(c_int, 6);
pub const GCJoinStyle = @as(c_long, 1) << @as(c_int, 7);
pub const GCFillStyle = @as(c_long, 1) << @as(c_int, 8);
pub const GCFillRule = @as(c_long, 1) << @as(c_int, 9);
pub const GCTile = @as(c_long, 1) << @as(c_int, 10);
pub const GCStipple = @as(c_long, 1) << @as(c_int, 11);
pub const GCTileStipXOrigin = @as(c_long, 1) << @as(c_int, 12);
pub const GCTileStipYOrigin = @as(c_long, 1) << @as(c_int, 13);
pub const GCFont = @as(c_long, 1) << @as(c_int, 14);
pub const GCSubwindowMode = @as(c_long, 1) << @as(c_int, 15);
pub const GCGraphicsExposures = @as(c_long, 1) << @as(c_int, 16);
pub const GCClipXOrigin = @as(c_long, 1) << @as(c_int, 17);
pub const GCClipYOrigin = @as(c_long, 1) << @as(c_int, 18);
pub const GCClipMask = @as(c_long, 1) << @as(c_int, 19);
pub const GCDashOffset = @as(c_long, 1) << @as(c_int, 20);
pub const GCDashList = @as(c_long, 1) << @as(c_int, 21);
pub const GCArcMode = @as(c_long, 1) << @as(c_int, 22);
pub const GCLastBit = @as(c_int, 22);
pub const FontLeftToRight = @as(c_int, 0);
pub const FontRightToLeft = @as(c_int, 1);
pub const FontChange = @as(c_int, 255);
pub const XYBitmap = @as(c_int, 0);
pub const XYPixmap = @as(c_int, 1);
pub const ZPixmap = @as(c_int, 2);
pub const AllocNone = @as(c_int, 0);
pub const AllocAll = @as(c_int, 1);
pub const DoRed = @as(c_int, 1) << @as(c_int, 0);
pub const DoGreen = @as(c_int, 1) << @as(c_int, 1);
pub const DoBlue = @as(c_int, 1) << @as(c_int, 2);
pub const CursorShape = @as(c_int, 0);
pub const TileShape = @as(c_int, 1);
pub const StippleShape = @as(c_int, 2);
pub const AutoRepeatModeOff = @as(c_int, 0);
pub const AutoRepeatModeOn = @as(c_int, 1);
pub const AutoRepeatModeDefault = @as(c_int, 2);
pub const LedModeOff = @as(c_int, 0);
pub const LedModeOn = @as(c_int, 1);
pub const KBKeyClickPercent = @as(c_long, 1) << @as(c_int, 0);
pub const KBBellPercent = @as(c_long, 1) << @as(c_int, 1);
pub const KBBellPitch = @as(c_long, 1) << @as(c_int, 2);
pub const KBBellDuration = @as(c_long, 1) << @as(c_int, 3);
pub const KBLed = @as(c_long, 1) << @as(c_int, 4);
pub const KBLedMode = @as(c_long, 1) << @as(c_int, 5);
pub const KBKey = @as(c_long, 1) << @as(c_int, 6);
pub const KBAutoRepeatMode = @as(c_long, 1) << @as(c_int, 7);
pub const MappingSuccess = @as(c_int, 0);
pub const MappingBusy = @as(c_int, 1);
pub const MappingFailed = @as(c_int, 2);
pub const MappingModifier = @as(c_int, 0);
pub const MappingKeyboard = @as(c_int, 1);
pub const MappingPointer = @as(c_int, 2);
pub const DontPreferBlanking = @as(c_int, 0);
pub const PreferBlanking = @as(c_int, 1);
pub const DefaultBlanking = @as(c_int, 2);
pub const DisableScreenSaver = @as(c_int, 0);
pub const DisableScreenInterval = @as(c_int, 0);
pub const DontAllowExposures = @as(c_int, 0);
pub const AllowExposures = @as(c_int, 1);
pub const DefaultExposures = @as(c_int, 2);
pub const ScreenSaverReset = @as(c_int, 0);
pub const ScreenSaverActive = @as(c_int, 1);
pub const HostInsert = @as(c_int, 0);
pub const HostDelete = @as(c_int, 1);
pub const EnableAccess = @as(c_int, 1);
pub const DisableAccess = @as(c_int, 0);
pub const StaticGray = @as(c_int, 0);
pub const GrayScale = @as(c_int, 1);
pub const StaticColor = @as(c_int, 2);
pub const PseudoColor = @as(c_int, 3);
pub const TrueColor = @as(c_int, 4);
pub const DirectColor = @as(c_int, 5);
pub const LSBFirst = @as(c_int, 0);
pub const MSBFirst = @as(c_int, 1);
pub const _XFUNCPROTO_H_ = "";
pub const NeedFunctionPrototypes = @as(c_int, 1);
pub const NeedVarargsPrototypes = @as(c_int, 1);
pub const NeedNestedPrototypes = @as(c_int, 1);
pub const _Xconst = @compileError("unable to translate C expr: unexpected token 'const'"); // /usr/include/X11/Xfuncproto.h:47:9
pub const NARROWPROTO = "";
pub const FUNCPROTO = @as(c_int, 15);
pub const NeedWidePrototypes = @as(c_int, 0);
pub const _XFUNCPROTOBEGIN = "";
pub const _XFUNCPROTOEND = "";
pub const _X_SENTINEL = @compileError("unable to translate macro: undefined identifier `__sentinel__`"); // /usr/include/X11/Xfuncproto.h:95:10
pub const _X_EXPORT = @compileError("unable to translate macro: undefined identifier `visibility`"); // /usr/include/X11/Xfuncproto.h:103:10
pub const _X_HIDDEN = @compileError("unable to translate macro: undefined identifier `visibility`"); // /usr/include/X11/Xfuncproto.h:104:10
pub const _X_INTERNAL = @compileError("unable to translate macro: undefined identifier `visibility`"); // /usr/include/X11/Xfuncproto.h:105:10
pub inline fn _X_LIKELY(x: anytype) @TypeOf(__builtin.expect(!!(x != 0), @as(c_int, 1))) {
    _ = &x;
    return __builtin.expect(!!(x != 0), @as(c_int, 1));
}
pub inline fn _X_UNLIKELY(x: anytype) @TypeOf(__builtin.expect(!!(x != 0), @as(c_int, 0))) {
    _ = &x;
    return __builtin.expect(!!(x != 0), @as(c_int, 0));
}
pub const _X_COLD = @compileError("unable to translate macro: undefined identifier `__cold__`"); // /usr/include/X11/Xfuncproto.h:130:10
pub const _X_DEPRECATED = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /usr/include/X11/Xfuncproto.h:139:10
pub const _X_DEPRECATED_MSG = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /usr/include/X11/Xfuncproto.h:147:10
pub const _X_NORETURN = @compileError("unable to translate macro: undefined identifier `noreturn`"); // /usr/include/X11/Xfuncproto.h:156:10
pub const _X_ATTRIBUTE_PRINTF = @compileError("unable to translate macro: undefined identifier `__format__`"); // /usr/include/X11/Xfuncproto.h:164:10
pub const _X_UNUSED = @compileError("unable to translate macro: undefined identifier `__unused__`"); // /usr/include/X11/Xfuncproto.h:172:9
pub const _X_INLINE = @compileError("unable to translate C expr: unexpected token 'inline'"); // /usr/include/X11/Xfuncproto.h:183:10
pub const _X_RESTRICT_KYWD = @compileError("unable to translate C expr: unexpected token 'restrict'"); // /usr/include/X11/Xfuncproto.h:196:11
pub const _X_NOTSAN = @compileError("unable to translate macro: undefined identifier `no_sanitize_thread`"); // /usr/include/X11/Xfuncproto.h:206:10
pub const _X_NONSTRING = @compileError("unable to translate macro: undefined identifier `nonstring`"); // /usr/include/X11/Xfuncproto.h:214:10
pub const _X_FALLTHROUGH = @compileError("unable to translate macro: undefined identifier `fallthrough`"); // /usr/include/X11/Xfuncproto.h:226:9
pub const _XOSDEFS_H_ = "";
pub const X_HAVE_UTF8_STRING = @as(c_int, 1);
pub const Bool = c_int;
pub const Status = c_int;
pub const True = @as(c_int, 1);
pub const False = @as(c_int, 0);
pub const QueuedAlready = @as(c_int, 0);
pub const QueuedAfterReading = @as(c_int, 1);
pub const QueuedAfterFlush = @as(c_int, 2);
pub inline fn ConnectionNumber(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.fd) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.fd;
}
pub inline fn RootWindow(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.root) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.root;
}
pub inline fn DefaultScreen(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.default_screen) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.default_screen;
}
pub inline fn DefaultRootWindow(dpy: anytype) @TypeOf(ScreenOfDisplay(dpy, DefaultScreen(dpy)).*.root) {
    _ = &dpy;
    return ScreenOfDisplay(dpy, DefaultScreen(dpy)).*.root;
}
pub inline fn DefaultVisual(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.root_visual) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.root_visual;
}
pub inline fn DefaultGC(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.default_gc) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.default_gc;
}
pub inline fn BlackPixel(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.black_pixel) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.black_pixel;
}
pub inline fn WhitePixel(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.white_pixel) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.white_pixel;
}
pub const AllPlanes = __helpers.cast(c_ulong, ~@as(c_long, 0));
pub inline fn QLength(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.qlen) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.qlen;
}
pub inline fn DisplayWidth(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.width) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.width;
}
pub inline fn DisplayHeight(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.height) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.height;
}
pub inline fn DisplayWidthMM(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.mwidth) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.mwidth;
}
pub inline fn DisplayHeightMM(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.mheight) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.mheight;
}
pub inline fn DisplayPlanes(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.root_depth) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.root_depth;
}
pub inline fn DisplayCells(dpy: anytype, scr: anytype) @TypeOf(DefaultVisual(dpy, scr).*.map_entries) {
    _ = &dpy;
    _ = &scr;
    return DefaultVisual(dpy, scr).*.map_entries;
}
pub inline fn ScreenCount(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.nscreens) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.nscreens;
}
pub inline fn ServerVendor(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.vendor) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.vendor;
}
pub inline fn ProtocolVersion(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.proto_major_version) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.proto_major_version;
}
pub inline fn ProtocolRevision(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.proto_minor_version) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.proto_minor_version;
}
pub inline fn VendorRelease(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.release) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.release;
}
pub inline fn DisplayString(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.display_name) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.display_name;
}
pub inline fn DefaultDepth(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.root_depth) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.root_depth;
}
pub inline fn DefaultColormap(dpy: anytype, scr: anytype) @TypeOf(ScreenOfDisplay(dpy, scr).*.cmap) {
    _ = &dpy;
    _ = &scr;
    return ScreenOfDisplay(dpy, scr).*.cmap;
}
pub inline fn BitmapUnit(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.bitmap_unit) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.bitmap_unit;
}
pub inline fn BitmapBitOrder(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.bitmap_bit_order) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.bitmap_bit_order;
}
pub inline fn BitmapPad(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.bitmap_pad) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.bitmap_pad;
}
pub inline fn ImageByteOrder(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.byte_order) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.byte_order;
}
pub inline fn NextRequest(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.request + @as(c_int, 1)) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.request + @as(c_int, 1);
}
pub inline fn LastKnownRequestProcessed(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.last_request_read) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.last_request_read;
}
pub inline fn ScreenOfDisplay(dpy: anytype, scr: anytype) @TypeOf(&__helpers.cast(_XPrivDisplay, dpy).*.screens[@as(usize, @intCast(scr))]) {
    _ = &dpy;
    _ = &scr;
    return &__helpers.cast(_XPrivDisplay, dpy).*.screens[@as(usize, @intCast(scr))];
}
pub inline fn DefaultScreenOfDisplay(dpy: anytype) @TypeOf(ScreenOfDisplay(dpy, DefaultScreen(dpy))) {
    _ = &dpy;
    return ScreenOfDisplay(dpy, DefaultScreen(dpy));
}
pub inline fn DisplayOfScreen(s: anytype) @TypeOf(s.*.display) {
    _ = &s;
    return s.*.display;
}
pub inline fn RootWindowOfScreen(s: anytype) @TypeOf(s.*.root) {
    _ = &s;
    return s.*.root;
}
pub inline fn BlackPixelOfScreen(s: anytype) @TypeOf(s.*.black_pixel) {
    _ = &s;
    return s.*.black_pixel;
}
pub inline fn WhitePixelOfScreen(s: anytype) @TypeOf(s.*.white_pixel) {
    _ = &s;
    return s.*.white_pixel;
}
pub inline fn DefaultColormapOfScreen(s: anytype) @TypeOf(s.*.cmap) {
    _ = &s;
    return s.*.cmap;
}
pub inline fn DefaultDepthOfScreen(s: anytype) @TypeOf(s.*.root_depth) {
    _ = &s;
    return s.*.root_depth;
}
pub inline fn DefaultGCOfScreen(s: anytype) @TypeOf(s.*.default_gc) {
    _ = &s;
    return s.*.default_gc;
}
pub inline fn DefaultVisualOfScreen(s: anytype) @TypeOf(s.*.root_visual) {
    _ = &s;
    return s.*.root_visual;
}
pub inline fn WidthOfScreen(s: anytype) @TypeOf(s.*.width) {
    _ = &s;
    return s.*.width;
}
pub inline fn HeightOfScreen(s: anytype) @TypeOf(s.*.height) {
    _ = &s;
    return s.*.height;
}
pub inline fn WidthMMOfScreen(s: anytype) @TypeOf(s.*.mwidth) {
    _ = &s;
    return s.*.mwidth;
}
pub inline fn HeightMMOfScreen(s: anytype) @TypeOf(s.*.mheight) {
    _ = &s;
    return s.*.mheight;
}
pub inline fn PlanesOfScreen(s: anytype) @TypeOf(s.*.root_depth) {
    _ = &s;
    return s.*.root_depth;
}
pub inline fn CellsOfScreen(s: anytype) @TypeOf(DefaultVisualOfScreen(s).*.map_entries) {
    _ = &s;
    return DefaultVisualOfScreen(s).*.map_entries;
}
pub inline fn MinCmapsOfScreen(s: anytype) @TypeOf(s.*.min_maps) {
    _ = &s;
    return s.*.min_maps;
}
pub inline fn MaxCmapsOfScreen(s: anytype) @TypeOf(s.*.max_maps) {
    _ = &s;
    return s.*.max_maps;
}
pub inline fn DoesSaveUnders(s: anytype) @TypeOf(s.*.save_unders) {
    _ = &s;
    return s.*.save_unders;
}
pub inline fn DoesBackingStore(s: anytype) @TypeOf(s.*.backing_store) {
    _ = &s;
    return s.*.backing_store;
}
pub inline fn EventMaskOfScreen(s: anytype) @TypeOf(s.*.root_input_mask) {
    _ = &s;
    return s.*.root_input_mask;
}
pub inline fn XAllocID(dpy: anytype) @TypeOf(__helpers.cast(_XPrivDisplay, dpy).*.resource_alloc.*(dpy)) {
    _ = &dpy;
    return __helpers.cast(_XPrivDisplay, dpy).*.resource_alloc.*(dpy);
}
pub const XNRequiredCharSet = "requiredCharSet";
pub const XNQueryOrientation = "queryOrientation";
pub const XNBaseFontName = "baseFontName";
pub const XNOMAutomatic = "omAutomatic";
pub const XNMissingCharSet = "missingCharSet";
pub const XNDefaultString = "defaultString";
pub const XNOrientation = "orientation";
pub const XNDirectionalDependentDrawing = "directionalDependentDrawing";
pub const XNContextualDrawing = "contextualDrawing";
pub const XNFontInfo = "fontInfo";
pub const XIMPreeditArea = @as(c_long, 0x0001);
pub const XIMPreeditCallbacks = @as(c_long, 0x0002);
pub const XIMPreeditPosition = @as(c_long, 0x0004);
pub const XIMPreeditNothing = @as(c_long, 0x0008);
pub const XIMPreeditNone = @as(c_long, 0x0010);
pub const XIMStatusArea = @as(c_long, 0x0100);
pub const XIMStatusCallbacks = @as(c_long, 0x0200);
pub const XIMStatusNothing = @as(c_long, 0x0400);
pub const XIMStatusNone = @as(c_long, 0x0800);
pub const XNVaNestedList = "XNVaNestedList";
pub const XNQueryInputStyle = "queryInputStyle";
pub const XNClientWindow = "clientWindow";
pub const XNInputStyle = "inputStyle";
pub const XNFocusWindow = "focusWindow";
pub const XNResourceName = "resourceName";
pub const XNResourceClass = "resourceClass";
pub const XNGeometryCallback = "geometryCallback";
pub const XNDestroyCallback = "destroyCallback";
pub const XNFilterEvents = "filterEvents";
pub const XNPreeditStartCallback = "preeditStartCallback";
pub const XNPreeditDoneCallback = "preeditDoneCallback";
pub const XNPreeditDrawCallback = "preeditDrawCallback";
pub const XNPreeditCaretCallback = "preeditCaretCallback";
pub const XNPreeditStateNotifyCallback = "preeditStateNotifyCallback";
pub const XNPreeditAttributes = "preeditAttributes";
pub const XNStatusStartCallback = "statusStartCallback";
pub const XNStatusDoneCallback = "statusDoneCallback";
pub const XNStatusDrawCallback = "statusDrawCallback";
pub const XNStatusAttributes = "statusAttributes";
pub const XNArea = "area";
pub const XNAreaNeeded = "areaNeeded";
pub const XNSpotLocation = "spotLocation";
pub const XNColormap = "colorMap";
pub const XNStdColormap = "stdColorMap";
pub const XNForeground = "foreground";
pub const XNBackground = "background";
pub const XNBackgroundPixmap = "backgroundPixmap";
pub const XNFontSet = "fontSet";
pub const XNLineSpace = "lineSpace";
pub const XNCursor = "cursor";
pub const XNQueryIMValuesList = "queryIMValuesList";
pub const XNQueryICValuesList = "queryICValuesList";
pub const XNVisiblePosition = "visiblePosition";
pub const XNR6PreeditCallback = "r6PreeditCallback";
pub const XNStringConversionCallback = "stringConversionCallback";
pub const XNStringConversion = "stringConversion";
pub const XNResetState = "resetState";
pub const XNHotKey = "hotKey";
pub const XNHotKeyState = "hotKeyState";
pub const XNPreeditState = "preeditState";
pub const XNSeparatorofNestedList = "separatorofNestedList";
pub const XBufferOverflow = -@as(c_int, 1);
pub const XLookupNone = @as(c_int, 1);
pub const XLookupChars = @as(c_int, 2);
pub const XLookupKeySym = @as(c_int, 3);
pub const XLookupBoth = @as(c_int, 4);
pub const XIMReverse = @as(c_long, 1);
pub const XIMUnderline = @as(c_long, 1) << @as(c_int, 1);
pub const XIMHighlight = @as(c_long, 1) << @as(c_int, 2);
pub const XIMPrimary = @as(c_long, 1) << @as(c_int, 5);
pub const XIMSecondary = @as(c_long, 1) << @as(c_int, 6);
pub const XIMTertiary = @as(c_long, 1) << @as(c_int, 7);
pub const XIMVisibleToForward = @as(c_long, 1) << @as(c_int, 8);
pub const XIMVisibleToBackword = @as(c_long, 1) << @as(c_int, 9);
pub const XIMVisibleToCenter = @as(c_long, 1) << @as(c_int, 10);
pub const XIMPreeditUnKnown = @as(c_long, 0);
pub const XIMPreeditEnable = @as(c_long, 1);
pub const XIMPreeditDisable = @as(c_long, 1) << @as(c_int, 1);
pub const XIMInitialState = @as(c_long, 1);
pub const XIMPreserveState = @as(c_long, 1) << @as(c_int, 1);
pub const XIMStringConversionLeftEdge = @as(c_int, 0x00000001);
pub const XIMStringConversionRightEdge = @as(c_int, 0x00000002);
pub const XIMStringConversionTopEdge = @as(c_int, 0x00000004);
pub const XIMStringConversionBottomEdge = @as(c_int, 0x00000008);
pub const XIMStringConversionConcealed = @as(c_int, 0x00000010);
pub const XIMStringConversionWrapped = @as(c_int, 0x00000020);
pub const XIMStringConversionBuffer = @as(c_int, 0x0001);
pub const XIMStringConversionLine = @as(c_int, 0x0002);
pub const XIMStringConversionWord = @as(c_int, 0x0003);
pub const XIMStringConversionChar = @as(c_int, 0x0004);
pub const XIMStringConversionSubstitution = @as(c_int, 0x0001);
pub const XIMStringConversionRetrieval = @as(c_int, 0x0002);
pub const XIMHotKeyStateON = @as(c_long, 0x0001);
pub const XIMHotKeyStateOFF = @as(c_long, 0x0002);
pub const __GLIBC_USE_LIB_EXT2 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_TYPES_EXT = @as(c_int, 0);
pub const __need_wchar_t = "";
pub const __need_NULL = "";
pub const _STDLIB_H = @as(c_int, 1);
pub const WNOHANG = @as(c_int, 1);
pub const WUNTRACED = @as(c_int, 2);
pub const WSTOPPED = @as(c_int, 2);
pub const WEXITED = @as(c_int, 4);
pub const WCONTINUED = @as(c_int, 8);
pub const WNOWAIT = __helpers.promoteIntLiteral(c_int, 0x01000000, .hex);
pub const __WNOTHREAD = __helpers.promoteIntLiteral(c_int, 0x20000000, .hex);
pub const __WALL = __helpers.promoteIntLiteral(c_int, 0x40000000, .hex);
pub const __WCLONE = __helpers.promoteIntLiteral(c_int, 0x80000000, .hex);
pub inline fn __WEXITSTATUS(status: anytype) @TypeOf((status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &status;
    return (status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn __WTERMSIG(status: anytype) @TypeOf(status & @as(c_int, 0x7f)) {
    _ = &status;
    return status & @as(c_int, 0x7f);
}
pub inline fn __WSTOPSIG(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn __WIFEXITED(status: anytype) @TypeOf(__WTERMSIG(status) == @as(c_int, 0)) {
    _ = &status;
    return __WTERMSIG(status) == @as(c_int, 0);
}
pub inline fn __WIFSIGNALED(status: anytype) @TypeOf((__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0)) {
    _ = &status;
    return (__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0);
}
pub inline fn __WIFSTOPPED(status: anytype) @TypeOf((status & @as(c_int, 0xff)) == @as(c_int, 0x7f)) {
    _ = &status;
    return (status & @as(c_int, 0xff)) == @as(c_int, 0x7f);
}
pub inline fn __WIFCONTINUED(status: anytype) @TypeOf(status == __W_CONTINUED) {
    _ = &status;
    return status == __W_CONTINUED;
}
pub inline fn __WCOREDUMP(status: anytype) @TypeOf(status & __WCOREFLAG) {
    _ = &status;
    return status & __WCOREFLAG;
}
pub inline fn __W_EXITCODE(ret: anytype, sig: anytype) @TypeOf((ret << @as(c_int, 8)) | sig) {
    _ = &ret;
    _ = &sig;
    return (ret << @as(c_int, 8)) | sig;
}
pub inline fn __W_STOPCODE(sig: anytype) @TypeOf((sig << @as(c_int, 8)) | @as(c_int, 0x7f)) {
    _ = &sig;
    return (sig << @as(c_int, 8)) | @as(c_int, 0x7f);
}
pub const __W_CONTINUED = __helpers.promoteIntLiteral(c_int, 0xffff, .hex);
pub const __WCOREFLAG = @as(c_int, 0x80);
pub inline fn WEXITSTATUS(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn WTERMSIG(status: anytype) @TypeOf(__WTERMSIG(status)) {
    _ = &status;
    return __WTERMSIG(status);
}
pub inline fn WSTOPSIG(status: anytype) @TypeOf(__WSTOPSIG(status)) {
    _ = &status;
    return __WSTOPSIG(status);
}
pub inline fn WIFEXITED(status: anytype) @TypeOf(__WIFEXITED(status)) {
    _ = &status;
    return __WIFEXITED(status);
}
pub inline fn WIFSIGNALED(status: anytype) @TypeOf(__WIFSIGNALED(status)) {
    _ = &status;
    return __WIFSIGNALED(status);
}
pub inline fn WIFSTOPPED(status: anytype) @TypeOf(__WIFSTOPPED(status)) {
    _ = &status;
    return __WIFSTOPPED(status);
}
pub inline fn WIFCONTINUED(status: anytype) @TypeOf(__WIFCONTINUED(status)) {
    _ = &status;
    return __WIFCONTINUED(status);
}
pub const _BITS_FLOATN_H = "";
pub const __HAVE_FLOAT128 = @as(c_int, 1);
pub const __HAVE_DISTINCT_FLOAT128 = @as(c_int, 1);
pub const __HAVE_FLOAT64X = @as(c_int, 1);
pub const __HAVE_FLOAT64X_LONG_DOUBLE = @as(c_int, 1);
pub const __f128 = @compileError("unable to translate macro: undefined identifier `f128`"); // /usr/include/bits/floatn.h:72:12
pub const __CFLOAT128 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn.h:86:12
pub const _BITS_FLOATN_COMMON_H = "";
pub const __HAVE_FLOAT16 = @as(c_int, 0);
pub const __HAVE_FLOAT32 = @as(c_int, 1);
pub const __HAVE_FLOAT64 = @as(c_int, 1);
pub const __HAVE_FLOAT32X = @as(c_int, 1);
pub const __HAVE_FLOAT128X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT16 = __HAVE_FLOAT16;
pub const __HAVE_DISTINCT_FLOAT32 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT32X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT128X = __HAVE_FLOAT128X;
pub const __HAVE_FLOAT128_UNLIKE_LDBL = (__HAVE_DISTINCT_FLOAT128 != 0) and (__LDBL_MANT_DIG__ != @as(c_int, 113));
pub const __HAVE_FLOATN_NOT_TYPEDEF = @as(c_int, 1);
pub const __f32 = @compileError("unable to translate macro: undefined identifier `f32`"); // /usr/include/bits/floatn-common.h:93:12
pub const __f64 = @compileError("unable to translate macro: undefined identifier `f64`"); // /usr/include/bits/floatn-common.h:105:12
pub const __f32x = @compileError("unable to translate macro: undefined identifier `f32x`"); // /usr/include/bits/floatn-common.h:113:12
pub const __f64x = @compileError("unable to translate macro: undefined identifier `f64x`"); // /usr/include/bits/floatn-common.h:125:12
pub const __CFLOAT32 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:151:12
pub const __CFLOAT64 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:163:12
pub const __CFLOAT32X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:171:12
pub const __CFLOAT64X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:183:12
pub const __ldiv_t_defined = @as(c_int, 1);
pub const __lldiv_t_defined = @as(c_int, 1);
pub const RAND_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const EXIT_FAILURE = @as(c_int, 1);
pub const EXIT_SUCCESS = @as(c_int, 0);
pub const MB_CUR_MAX = __ctype_get_mb_cur_max();
pub const _ALLOCA_H = @as(c_int, 1);
pub const __COMPAR_FN_T = "";
pub const timeval = struct_timeval;
pub const timespec = struct_timespec;
pub const __pthread_internal_list = struct___pthread_internal_list;
pub const __pthread_internal_slist = struct___pthread_internal_slist;
pub const __pthread_mutex_s = struct___pthread_mutex_s;
pub const __pthread_rwlock_arch_t = struct___pthread_rwlock_arch_t;
pub const __pthread_cond_s = struct___pthread_cond_s;
pub const _XExtData = struct__XExtData;
pub const _XGC = struct__XGC;
pub const _XDisplay = struct__XDisplay;
pub const _XImage = struct__XImage;
pub const _XPrivate = struct__XPrivate;
pub const _XrmHashBucketRec = struct__XrmHashBucketRec;
pub const _XEvent = union__XEvent;
pub const _XOM = struct__XOM;
pub const _XOC = struct__XOC;
pub const _XIM = struct__XIM;
pub const _XIC = struct__XIC;
pub const _XIMText = struct__XIMText;
pub const _XIMPreeditStateNotifyCallbackStruct = struct__XIMPreeditStateNotifyCallbackStruct;
pub const _XIMStringConversionText = struct__XIMStringConversionText;
pub const _XIMStringConversionCallbackStruct = struct__XIMStringConversionCallbackStruct;
pub const _XIMPreeditDrawCallbackStruct = struct__XIMPreeditDrawCallbackStruct;
pub const _XIMPreeditCaretCallbackStruct = struct__XIMPreeditCaretCallbackStruct;
pub const _XIMStatusDrawCallbackStruct = struct__XIMStatusDrawCallbackStruct;
pub const _XIMHotKeyTrigger = struct__XIMHotKeyTrigger;
pub const _XIMHotKeyTriggers = struct__XIMHotKeyTriggers;
pub const random_data = struct_random_data;
pub const drand48_data = struct_drand48_data;
