// Web stub for disk_space.dart — FFI-based free-space probing is
// unavailable on web; always returns -1 (skip precheck).

int getAvailableDiskSpace(String path) => -1;
