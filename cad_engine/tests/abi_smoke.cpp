#include "../ffi/cadpilot_engine.h"
#include <cassert>
int main() { assert(cadpilot_abi_version() == 1); auto session = cadpilot_session_create(); assert(session); cadpilot_session_destroy(session); }
