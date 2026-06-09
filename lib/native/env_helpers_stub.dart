// Web stub for env_helpers.dart — libc setenv() is unavailable on web.
// All functions are no-ops.

bool setEnv(String name, String value) => false;

void applyKokoroMetalWorkaround() {}

void applyKokoroEspeakDataPath({String? explicitOverride}) {}
