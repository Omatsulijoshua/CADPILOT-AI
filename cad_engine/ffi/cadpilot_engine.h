#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define CADPILOT_API __declspec(dllexport)
#else
#define CADPILOT_API __attribute__((visibility("default")))
#endif

extern "C" {
typedef void* CadPilotSession;
typedef struct { int32_t code; const char* message; } CadPilotResult;
CADPILOT_API uint32_t cadpilot_abi_version();
CADPILOT_API CadPilotSession cadpilot_session_create();
CADPILOT_API void cadpilot_session_destroy(CadPilotSession session);
CADPILOT_API CadPilotResult cadpilot_apply_command(CadPilotSession session, const char* json_utf8);
}
