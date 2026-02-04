#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <flutter_windows.h>

#include "flutter_window.h"
#include "utils.h"

// Registry key for saving window position
constexpr const wchar_t kWindowPosRegKey[] = L"Software\\AuokBrowser";

// Default window size (logical pixels for 96 DPI)
constexpr int kDefaultWidth = 450;
constexpr int kDefaultHeight = 850;

// Load window position from registry (physical pixels), returns true if found
bool LoadWindowPosition(int& x, int& y, int& width, int& height) {
  HKEY hKey;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowPosRegKey, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
    DWORD size = sizeof(DWORD);
    DWORD dwX, dwY, dwW, dwH;
    bool success = true;
    
    success &= (RegQueryValueExW(hKey, L"WindowX", nullptr, nullptr, (LPBYTE)&dwX, &size) == ERROR_SUCCESS);
    success &= (RegQueryValueExW(hKey, L"WindowY", nullptr, nullptr, (LPBYTE)&dwY, &size) == ERROR_SUCCESS);
    success &= (RegQueryValueExW(hKey, L"WindowWidth", nullptr, nullptr, (LPBYTE)&dwW, &size) == ERROR_SUCCESS);
    success &= (RegQueryValueExW(hKey, L"WindowHeight", nullptr, nullptr, (LPBYTE)&dwH, &size) == ERROR_SUCCESS);
    
    RegCloseKey(hKey);
    
    if (success && dwW > 100 && dwH > 100) {
      x = static_cast<int>(dwX);
      y = static_cast<int>(dwY);
      width = static_cast<int>(dwW);
      height = static_cast<int>(dwH);
      return true;
    }
  }
  return false;
}

// Save window position to registry (physical pixels)
void SaveWindowPosition(HWND hwnd) {
  if (!hwnd || !IsWindow(hwnd)) return;
  
  // Don't save if minimized
  if (IsIconic(hwnd)) return;
  
  RECT rect;
  if (GetWindowRect(hwnd, &rect)) {
    HKEY hKey;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowPosRegKey, 0, nullptr, 
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
      DWORD x = static_cast<DWORD>(rect.left);
      DWORD y = static_cast<DWORD>(rect.top);
      DWORD w = static_cast<DWORD>(rect.right - rect.left);
      DWORD h = static_cast<DWORD>(rect.bottom - rect.top);
      
      RegSetValueExW(hKey, L"WindowX", 0, REG_DWORD, (LPBYTE)&x, sizeof(DWORD));
      RegSetValueExW(hKey, L"WindowY", 0, REG_DWORD, (LPBYTE)&y, sizeof(DWORD));
      RegSetValueExW(hKey, L"WindowWidth", 0, REG_DWORD, (LPBYTE)&w, sizeof(DWORD));
      RegSetValueExW(hKey, L"WindowHeight", 0, REG_DWORD, (LPBYTE)&h, sizeof(DWORD));
      
      RegCloseKey(hKey);
    }
  }
}

// Global window handle for saving position
static HWND g_main_window = nullptr;

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  int frame_x, frame_y, frame_w, frame_h;
  bool has_saved_pos = LoadWindowPosition(frame_x, frame_y, frame_w, frame_h);

  FlutterWindow window(project);
  
  if (has_saved_pos) {
    // Use saved position directly (already in physical pixels)
    // We need to convert to logical pixels since Win32Window::Create applies DPI scaling
    POINT pt = {frame_x, frame_y};
    HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
    double scale = dpi / 96.0;
    
    // Convert physical pixels back to logical pixels
    int logical_x = static_cast<int>(frame_x / scale);
    int logical_y = static_cast<int>(frame_y / scale);
    int logical_w = static_cast<int>(frame_w / scale);
    int logical_h = static_cast<int>(frame_h / scale);
    
    Win32Window::Point origin(logical_x, logical_y);
    Win32Window::Size size(logical_w, logical_h);
    if (!window.Create(L"Auok\u6d4f\u89c8\u5668", origin, size)) {
      return EXIT_FAILURE;
    }
  } else {
    // First launch: create window then center it
    Win32Window::Point origin(0, 0);
    Win32Window::Size size(kDefaultWidth, kDefaultHeight);
    if (!window.Create(L"Auok\u6d4f\u89c8\u5668", origin, size)) {
      return EXIT_FAILURE;
    }
    
    // Center the window in work area (excluding taskbar)
    HWND hwnd = window.GetHandle();
    if (hwnd) {
      RECT windowRect;
      GetWindowRect(hwnd, &windowRect);
      int w = windowRect.right - windowRect.left;
      int h = windowRect.bottom - windowRect.top;
      
      // Get work area (screen area minus taskbar)
      RECT workArea;
      SystemParametersInfo(SPI_GETWORKAREA, 0, &workArea, 0);
      
      int workWidth = workArea.right - workArea.left;
      int workHeight = workArea.bottom - workArea.top;
      
      int newX = workArea.left + (workWidth - w) / 2;
      int newY = workArea.top + (workHeight - h) / 2;
      
      SetWindowPos(hwnd, nullptr, newX, newY, 0, 0, 
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }
  
  window.SetQuitOnClose(true);
  
  // Store handle for saving position
  g_main_window = window.GetHandle();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Save window position before exit
  if (g_main_window) {
    SaveWindowPosition(g_main_window);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
