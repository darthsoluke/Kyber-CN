#include <windows.h>
#include <stdlib.h>
#include <string.h>

static void trace(const char* message)
{
    const char* path = getenv("KYBER_EARLY_TRACE");
    if (path == NULL || path[0] == '\0')
    {
        path = "Z:\\home\\kyber\\kyber-smoke-dll.log";
    }

    HANDLE file = CreateFileA(
        path,
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        return;
    }

    DWORD written = 0;
    WriteFile(file, message, (DWORD)strlen(message), &written, NULL);
    WriteFile(file, "\r\n", 2, &written, NULL);
    CloseHandle(file);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)instance;
    (void)reserved;

    if (reason == DLL_PROCESS_ATTACH)
    {
        trace("smoke.dll.process_attach");
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        trace("smoke.dll.process_detach");
    }

    return TRUE;
}
