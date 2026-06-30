// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <Base/Log.h>
#include <Base/Platform.h>
#include <Core/Program.h>

#include <string>
#include <cstring>

#define EASTL_USER_DEFINED_ALLOCATOR

static void KyberEarlyTrace(const char* message)
{
    const char* path = std::getenv("KYBER_EARLY_TRACE");
    if (path == nullptr || path[0] == '\0')
    {
        return;
    }

    HANDLE file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE)
    {
        DWORD written = 0;
        WriteFile(file, message, static_cast<DWORD>(strlen(message)), &written, nullptr);
        WriteFile(file, "\r\n", 2, &written, nullptr);
        CloseHandle(file);
    }
}

void* operator new[](
    size_t size, size_t alignment, size_t alignmentOffset, const char* pName, int flags, unsigned debugFlags, const char* file, int line)
{
    return new uint8_t[size];
}

void* operator new[](size_t size, const char* name, int flags, unsigned debugFlags, const char* file, int line)
{
    return new uint8_t[size];
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD dwReason, LPVOID lpReserved)
{
    if (dwReason == DLL_PROCESS_ATTACH)
    {
        KyberEarlyTrace("dllmain.process_attach.before_program");
        Kyber::g_program = new Kyber::Program(hModule);
        KyberEarlyTrace("dllmain.process_attach.after_program");
    }
    else if (dwReason == DLL_PROCESS_DETACH)
    {
        KyberEarlyTrace("dllmain.process_detach");
        KYBER_LOG(Info, "Kyber unloaded");
        delete Kyber::g_program;
    }

    return TRUE;
}
