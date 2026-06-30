#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <wchar.h>

static void print_last_error(const wchar_t *message) {
    fwprintf(stderr, L"%ls: Windows error %lu\n", message, GetLastError());
}

static int normalize_dll_path(const wchar_t *input, wchar_t *output, size_t output_len) {
    size_t i = 0;

    if (input == NULL || input[0] == L'\0' || output_len == 0) {
        fwprintf(stderr, L"missing DLL path\n");
        return 1;
    }

    if (input[0] == L'/') {
        if (output_len < 4) {
            fwprintf(stderr, L"DLL path buffer is too small\n");
            return 1;
        }

        output[0] = L'Z';
        output[1] = L':';
        i = 2;
    }

    for (const wchar_t *cursor = input; *cursor != L'\0'; ++cursor) {
        if (i + 1 >= output_len) {
            fwprintf(stderr, L"DLL path is too long\n");
            return 1;
        }

        output[i++] = (*cursor == L'/') ? L'\\' : *cursor;
    }

    output[i] = L'\0';
    return 0;
}

static DWORD find_single_process_by_name(const wchar_t *process_name) {
    DWORD matched_pid = 0;
    DWORD match_count = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (snapshot == INVALID_HANDLE_VALUE) {
        print_last_error(L"CreateToolhelp32Snapshot failed");
        return 0;
    }

    PROCESSENTRY32W entry;
    ZeroMemory(&entry, sizeof(entry));
    entry.dwSize = sizeof(entry);

    if (!Process32FirstW(snapshot, &entry)) {
        print_last_error(L"Process32FirstW failed");
        CloseHandle(snapshot);
        return 0;
    }

    do {
        if (_wcsicmp(entry.szExeFile, process_name) == 0) {
            matched_pid = entry.th32ProcessID;
            match_count++;
        }
    } while (Process32NextW(snapshot, &entry));

    CloseHandle(snapshot);

    if (match_count == 0) {
        fwprintf(stderr, L"process not found: %ls\n", process_name);
        return 0;
    }

    if (match_count > 1) {
        fwprintf(stderr, L"multiple processes matched %ls; refusing ambiguous injection\n", process_name);
        return 0;
    }

    return matched_pid;
}

static int inject_library(DWORD pid, const wchar_t *dll_path) {
    size_t dll_path_size = (wcslen(dll_path) + 1) * sizeof(wchar_t);
    HANDLE process = OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION |
            PROCESS_VM_WRITE | PROCESS_VM_READ,
        FALSE,
        pid);

    if (process == NULL) {
        print_last_error(L"OpenProcess failed");
        return 1;
    }

    LPVOID remote_memory = VirtualAllocEx(
        process,
        NULL,
        dll_path_size,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_READWRITE);

    if (remote_memory == NULL) {
        print_last_error(L"VirtualAllocEx failed");
        CloseHandle(process);
        return 1;
    }

    SIZE_T bytes_written = 0;
    if (!WriteProcessMemory(process, remote_memory, dll_path, dll_path_size, &bytes_written)) {
        print_last_error(L"WriteProcessMemory failed");
        VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
        CloseHandle(process);
        return 1;
    }

    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (kernel32 == NULL) {
        print_last_error(L"GetModuleHandleW(kernel32.dll) failed");
        VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
        CloseHandle(process);
        return 1;
    }

    FARPROC load_library = GetProcAddress(kernel32, "LoadLibraryW");
    if (load_library == NULL) {
        print_last_error(L"GetProcAddress(LoadLibraryW) failed");
        VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
        CloseHandle(process);
        return 1;
    }

    HANDLE thread = CreateRemoteThread(
        process,
        NULL,
        0,
        (LPTHREAD_START_ROUTINE)load_library,
        remote_memory,
        0,
        NULL);

    if (thread == NULL) {
        print_last_error(L"CreateRemoteThread failed");
        VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
        CloseHandle(process);
        return 1;
    }

    WaitForSingleObject(thread, INFINITE);

    DWORD exit_code = 0;
    if (!GetExitCodeThread(thread, &exit_code)) {
        print_last_error(L"GetExitCodeThread failed");
        CloseHandle(thread);
        VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
        CloseHandle(process);
        return 1;
    }

    CloseHandle(thread);
    VirtualFreeEx(process, remote_memory, 0, MEM_RELEASE);
    CloseHandle(process);

    if (exit_code == 0) {
        fwprintf(stderr, L"LoadLibraryW returned NULL in remote process %lu\n", pid);
        return 1;
    }

    wprintf(L"kyber-wine-injector: injected %ls into PID %lu\n", dll_path, pid);
    return 0;
}

int wmain(int argc, wchar_t **argv) {
    wchar_t dll_path[MAX_PATH * 4];
    DWORD pid = 0;

    if (argc != 4) {
        fwprintf(
            stderr,
            L"usage: kyber-wine-injector.exe inject-name <process.exe> <dll-path>\n"
            L"   or: kyber-wine-injector.exe inject-pid <pid> <dll-path>\n");
        return 64;
    }

    if (normalize_dll_path(argv[3], dll_path, sizeof(dll_path) / sizeof(dll_path[0])) != 0) {
        return 64;
    }

    if (_wcsicmp(argv[1], L"inject-name") == 0) {
        pid = find_single_process_by_name(argv[2]);
        if (pid == 0) {
            return 66;
        }
    } else if (_wcsicmp(argv[1], L"inject-pid") == 0) {
        pid = wcstoul(argv[2], NULL, 10);
        if (pid == 0) {
            fwprintf(stderr, L"invalid PID: %ls\n", argv[2]);
            return 64;
        }
    } else {
        fwprintf(stderr, L"unknown command: %ls\n", argv[1]);
        return 64;
    }

    return inject_library(pid, dll_path);
}
