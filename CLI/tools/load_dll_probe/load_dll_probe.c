#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <stdio.h>
#include <wchar.h>

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

int wmain(int argc, wchar_t **argv) {
    wchar_t dll_path[MAX_PATH * 4];

    if (argc != 2) {
        fwprintf(stderr, L"usage: load-dll-probe.exe <dll-path>\n");
        return 64;
    }

    if (normalize_dll_path(argv[1], dll_path, sizeof(dll_path) / sizeof(dll_path[0])) != 0) {
        return 64;
    }

    SetLastError(0);
    HMODULE module = LoadLibraryExW(dll_path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    DWORD error = GetLastError();

    if (module == NULL) {
        fwprintf(stderr, L"LoadLibraryExW failed: path=%ls error=%lu\n", dll_path, error);
        return 1;
    }

    wprintf(L"LoadLibraryExW succeeded: path=%ls module=%p error=%lu\n", dll_path, module, error);
    FreeLibrary(module);
    return 0;
}
