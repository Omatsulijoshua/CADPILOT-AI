#include "cadpilot_engine.h"
#include <new>

namespace { struct Session { uint64_t revision = 0; }; }
uint32_t cadpilot_abi_version() { return 1; }
CadPilotSession cadpilot_session_create() { return new (std::nothrow) Session(); }
void cadpilot_session_destroy(CadPilotSession session) { delete static_cast<Session*>(session); }
CadPilotResult cadpilot_apply_command(CadPilotSession session, const char* json_utf8) {
  if (!session || !json_utf8) return {1, "invalid argument"};
  return {2, "Geometry commands begin in Phase 2/3"};
}
