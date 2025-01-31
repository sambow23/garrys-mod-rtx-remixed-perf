#include <windows.h>
#include <string>
#include <vector>
#include <CommCtrl.h>
#include <Uxtheme.h>
#include <regex>
#include <shellscalingapi.h>

// Link required libraries
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "Shcore.lib")
#pragma comment(lib, "uxtheme.lib")
#pragma comment(linker,"\"/manifestdependency:type='win32' \
name='Microsoft.Windows.Common-Controls' version='6.0.0.0' \
processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

// Define control IDs
#define ID_COMBOBOX 101
#define ID_LAUNCH_BUTTON 102
#define ID_WIDTH_EDIT 103
#define ID_HEIGHT_EDIT 104
#define ID_RESOLUTION_GROUP 105
#define ID_CUSTOM_RES_CHECK 106

struct Resolution {
    int width;
    int height;
    std::wstring toString() const {
        return std::to_wstring(width) + L"x" + std::to_wstring(height);
    }
};

// Global variables
float g_dpiScale = 1.0f;
HWND g_hComboBox = NULL;
HWND g_hButton = NULL;
HWND g_hStatus = NULL;
HWND g_hWidthEdit = NULL;
HWND g_hHeightEdit = NULL;
HWND g_hGroupBox = NULL;
HFONT g_hFont = NULL;
HWND g_hCustomCheck = NULL;
bool g_useCustomResolution = false;
std::vector<Resolution> g_resolutions = {
    {1920, 1080},
    {2560, 1440},
    {3440, 1440},
    {3840, 2160},
    {1600, 900},
    {1366, 768},
    {1280, 720}
};

// Helper function to scale dimensions
int Scale(int value) {
    return static_cast<int>(value * g_dpiScale);
}

// Forward declarations
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
std::wstring FindGameDirectory();

// Create a modern font
HFONT CreateModernFont() {
    return CreateFontW(
        Scale(-14),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI"
    );
}

// DPI awareness helper function
void SetDPIAwareness() {
    // Set DPI awareness
    SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);

    // Get the DPI for the main monitor
    HWND hWnd = GetDesktopWindow();
    UINT dpi = GetDpiForWindow(hWnd);
    g_dpiScale = static_cast<float>(dpi) / 96.0f;
}

bool ParseResolution(const std::wstring& input, int& width, int& height) {
    std::wregex resolution_pattern(L"\\s*(\\d+)\\s*[x,]\\s*(\\d+)\\s*");
    std::wsmatch matches;
    
    if (std::regex_match(input, matches, resolution_pattern)) {
        width = std::stoi(matches[1].str());
        height = std::stoi(matches[2].str());
        return width > 0 && height > 0;
    }
    return false;
}

void UpdateControlStates() {
    // Enable/disable controls based on checkbox state
    EnableWindow(g_hComboBox, !g_useCustomResolution);
    EnableWindow(g_hWidthEdit, g_useCustomResolution);
    EnableWindow(g_hHeightEdit, g_useCustomResolution);

    // Update visual state
    if (g_useCustomResolution) {
        SendMessageW(g_hComboBox, CB_SETCURSEL, -1, 0); // Deselect combo box item
    } else {
        // If no item is selected, select the first one
        if (SendMessageW(g_hComboBox, CB_GETCURSEL, 0, 0) == CB_ERR) {
            SendMessageW(g_hComboBox, CB_SETCURSEL, 0, 0);
        }
        // Update custom resolution fields with selected preset
        int index = SendMessageW(g_hComboBox, CB_GETCURSEL, 0, 0);
        if (index != CB_ERR) {
            SetWindowTextW(g_hWidthEdit, std::to_wstring(g_resolutions[index].width).c_str());
            SetWindowTextW(g_hHeightEdit, std::to_wstring(g_resolutions[index].height).c_str());
        }
    }
}

void GetCurrentResolution(int& width, int& height) {
    if (g_useCustomResolution) {
        // Use custom resolution
        wchar_t widthBuffer[16], heightBuffer[16];
        GetWindowTextW(g_hWidthEdit, widthBuffer, 16);
        GetWindowTextW(g_hHeightEdit, heightBuffer, 16);
        
        width = _wtoi(widthBuffer);
        height = _wtoi(heightBuffer);
        
        // Validate input
        if (width <= 0 || height <= 0) {
            width = 1920;  // Default fallback
            height = 1080;
        }
    } else {
        // Use preset resolution
        int selectedIndex = SendMessageW(g_hComboBox, CB_GETCURSEL, 0, 0);
        if (selectedIndex != CB_ERR) {
            width = g_resolutions[selectedIndex].width;
            height = g_resolutions[selectedIndex].height;
        } else {
            width = 1920;  // Default fallback
            height = 1080;
        }
    }
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow) {
    // Set DPI awareness before creating any windows
    SetDPIAwareness();

    // Initialize Common Controls with visual styles
    INITCOMMONCONTROLSEX icex = { sizeof(INITCOMMONCONTROLSEX) };
    icex.dwICC = ICC_WIN95_CLASSES | ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icex);

    // Register window class
    const wchar_t CLASS_NAME[] = L"LauncherWindow";
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassW(&wc);

    // Create main window with scaled dimensions
    HWND hwnd = CreateWindowExW(
        0,
        CLASS_NAME,
        L"GarrysMod RTX Launcher",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT,
        Scale(300), Scale(270), // Scale the window size
        NULL,
        NULL,
        hInstance,
        NULL
    );

    if (hwnd == NULL) return 0;

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    // Message loop
    MSG msg = {};
    while (GetMessage(&msg, NULL, 0, 0)) {
        if (!IsDialogMessage(hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    // Cleanup
    if (g_hFont) DeleteObject(g_hFont);
    return 0;
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        g_hFont = CreateModernFont();

        // Create Group Box for resolution settings
        g_hGroupBox = CreateWindowW(L"BUTTON", L"Resolution",
            WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
            Scale(10), Scale(10), Scale(265), Scale(140),
            hwnd, (HMENU)ID_RESOLUTION_GROUP, NULL, NULL);
        SendMessageW(g_hGroupBox, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Create ComboBox for preset resolutions
        g_hComboBox = CreateWindowW(L"COMBOBOX", NULL,
            WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
            Scale(20), Scale(30), Scale(245), Scale(200),
            hwnd, (HMENU)ID_COMBOBOX, NULL, NULL);
        SendMessageW(g_hComboBox, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Add resolutions to ComboBox
        for (const auto& res : g_resolutions) {
            SendMessageW(g_hComboBox, CB_ADDSTRING, 0, (LPARAM)res.toString().c_str());
        }
        SendMessageW(g_hComboBox, CB_SETCURSEL, 0, 0);

        // Create checkbox for custom resolution
        g_hCustomCheck = CreateWindowW(L"BUTTON", L"Use Custom Resolution",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            Scale(20), Scale(60), Scale(245), Scale(20),
            hwnd, (HMENU)ID_CUSTOM_RES_CHECK, NULL, NULL);
        SendMessageW(g_hCustomCheck, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Create custom resolution controls
        CreateWindowW(L"STATIC", L"Custom Resolution:",
            WS_CHILD | WS_VISIBLE,
            Scale(20), Scale(85), Scale(120), Scale(20),
            hwnd, NULL, NULL, NULL);
        SendMessageW(GetWindow(hwnd, GW_CHILD), WM_SETFONT, (WPARAM)g_hFont, TRUE);

        g_hWidthEdit = CreateWindowW(L"EDIT", L"1920",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_NUMBER,
            Scale(20), Scale(105), Scale(60), Scale(23),
            hwnd, (HMENU)ID_WIDTH_EDIT, NULL, NULL);
        SendMessageW(g_hWidthEdit, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        CreateWindowW(L"STATIC", L"x",
            WS_CHILD | WS_VISIBLE,
            Scale(85), Scale(108), Scale(15), Scale(20),
            hwnd, NULL, NULL, NULL);
        SendMessageW(GetWindow(hwnd, GW_CHILD), WM_SETFONT, (WPARAM)g_hFont, TRUE);

        g_hHeightEdit = CreateWindowW(L"EDIT", L"1080",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_NUMBER,
            Scale(100), Scale(105), Scale(60), Scale(23),
            hwnd, (HMENU)ID_HEIGHT_EDIT, NULL, NULL);
        SendMessageW(g_hHeightEdit, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Create Launch Button
        g_hButton = CreateWindowW(L"BUTTON", L"Launch Game",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            Scale(10), Scale(160), Scale(265), Scale(30),
            hwnd, (HMENU)ID_LAUNCH_BUTTON, NULL, NULL);
        SendMessageW(g_hButton, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Create Status Text
        g_hStatus = CreateWindowW(L"STATIC", L"",
            WS_CHILD | WS_VISIBLE | SS_CENTER,
            Scale(10), Scale(200), Scale(265), Scale(20),
            hwnd, NULL, NULL, NULL);
        SendMessageW(g_hStatus, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        // Initialize control states
        UpdateControlStates();
        break;
    }

        case WM_COMMAND: {
            if (LOWORD(wParam) == ID_CUSTOM_RES_CHECK) {
                // Toggle custom resolution mode
                g_useCustomResolution = (SendMessageW(g_hCustomCheck, BM_GETCHECK, 0, 0) == BST_CHECKED);
                UpdateControlStates();
            }
            else if (LOWORD(wParam) == ID_COMBOBOX && HIWORD(wParam) == CBN_SELCHANGE) {
                if (!g_useCustomResolution) {
                    int index = SendMessageW(g_hComboBox, CB_GETCURSEL, 0, 0);
                    if (index != CB_ERR) {
                        SetWindowTextW(g_hWidthEdit, std::to_wstring(g_resolutions[index].width).c_str());
                        SetWindowTextW(g_hHeightEdit, std::to_wstring(g_resolutions[index].height).c_str());
                    }
                }
            }
            else if (LOWORD(wParam) == ID_LAUNCH_BUTTON) {
                int width, height;
                GetCurrentResolution(width, height);

                // Find game directory
                std::wstring workingDir = FindGameDirectory();
                if (workingDir.empty()) {
                    SetWindowTextW(g_hStatus, L"Error: Game directory not found!");
                    return 0;
                }

                std::wstring exePath = workingDir + L"\\bin\\win64\\gmod.exe";
                if (GetFileAttributesW(exePath.c_str()) == INVALID_FILE_ATTRIBUTES) {
                    SetWindowTextW(g_hStatus, L"Error: Game executable not found!");
                    return 0;
                }

                // Build command line
                std::wstring cmdLine = L"\"" + exePath + L"\"" +
                    L" -console -dxlevel 90 +mat_disable_d3d9ex 1 -windowed -noborder" +
                    L" -w " + std::to_wstring(width) +
                    L" -h " + std::to_wstring(height);

                // Launch process
                STARTUPINFOW si = { sizeof(si) };
                PROCESS_INFORMATION pi;

                if (CreateProcessW(NULL, (LPWSTR)cmdLine.c_str(),
                    NULL, NULL, FALSE, 0, NULL,
                    workingDir.c_str(), &si, &pi)) {
                    CloseHandle(pi.hProcess);
                    CloseHandle(pi.hThread);
                    SetWindowTextW(g_hStatus, L"Game launched successfully!");
                }
                else {
                    SetWindowTextW(g_hStatus, L"Error: Failed to launch game!");
                }
            }
            else if (LOWORD(wParam) == ID_COMBOBOX) {
                if (HIWORD(wParam) == CBN_SELCHANGE) {
                    // When a preset is selected, update the custom resolution fields
                    int index = SendMessageW(g_hComboBox, CB_GETCURSEL, 0, 0);
                    if (index != CB_ERR) {
                        SetWindowTextW(g_hWidthEdit, std::to_wstring(g_resolutions[index].width).c_str());
                        SetWindowTextW(g_hHeightEdit, std::to_wstring(g_resolutions[index].height).c_str());
                    }
                }
            }
            break;
        }

        case WM_CTLCOLORSTATIC: {
            HDC hdcStatic = (HDC)wParam;
            SetTextColor(hdcStatic, RGB(0, 0, 0));
            SetBkColor(hdcStatic, GetSysColor(COLOR_WINDOW));
            return (LRESULT)GetSysColorBrush(COLOR_WINDOW);
        }

        case WM_DESTROY: {
            PostQuitMessage(0);
            return 0;
        }
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// FindGameDirectory implementation remains the same
std::wstring FindGameDirectory() {
    wchar_t buffer[MAX_PATH];
    GetModuleFileNameW(NULL, buffer, MAX_PATH);
    std::wstring currentPath = buffer;
    
    size_t lastSlash = currentPath.find_last_of(L"\\");
    if (lastSlash != std::wstring::npos) {
        currentPath = currentPath.substr(0, lastSlash);
    }

    for (int i = 0; i < 3; i++) {
        std::wstring testPath = currentPath + L"\\bin\\win64\\gmod.exe";
        if (GetFileAttributesW(testPath.c_str()) != INVALID_FILE_ATTRIBUTES) {
            return currentPath;
        }

        lastSlash = currentPath.find_last_of(L"\\");
        if (lastSlash != std::wstring::npos) {
            currentPath = currentPath.substr(0, lastSlash);
        }
    }

    return L"";
}