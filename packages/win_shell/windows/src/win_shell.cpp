// win_shell - native Windows shell integration for Radin.
//
// Implements everything the app needs that the Flutter framework does not
// provide: system tray, close-to-tray, system proxy (registry + WinINet),
// child process control (job objects), UAC detection, autostart and OS
// version detection.
//
// Everything is plain Win32 on purpose: the resulting binary must run on
// Windows 7 SP1 all the way up to Windows 11.
//
// NOTE ON WINDOWS 7 COMPATIBILITY
//   * No API newer than Windows 7 is used without a runtime fallback.
//   * OS detection uses RtlGetVersion (ntdll) so that it reports the real
//     version even when the process is not manifested for Windows 10.
//   * Tray icons use NOTIFYICON_VERSION_4 which is available since Vista.

#include <windows.h>
#include <commctrl.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <wininet.h>

#include <cstring>
#include <map>
#include <mutex>
#include <stdio.h>
#include <string>
#include <vector>
#include <wchar.h>

#define WINSHELL_API extern "C" __declspec(dllexport)

// Forward declaration: the window subclass procedure needs to open the tray
// context menu.
extern "C" void win_shell_show_tray_menu();

namespace {

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const UINT kTrayMessage = WM_APP + 11;
const UINT kIconId = 1;

// Event ids delivered to Dart through WinShellRegisterEventCallback().
const int kEventTrayClick = 1;
const int kEventTrayDoubleClick = 2;
const int kEventCloseRequested = 3;
const int kEventMenuShow = 4;
const int kEventMenuConnect = 5;
const int kEventMenuDisconnect = 6;
const int kEventMenuExit = 7;
const int kEventWakeup = 8;
const int kEventMenuSettings = 9;

const int kMenuIdShow = 1001;
const int kMenuIdConnect = 1002;
const int kMenuIdDisconnect = 1003;
const int kMenuIdSettings = 1004;
const int kMenuIdExit = 1005;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

typedef void (*EventCallback)(int);

std::mutex g_mutex;
HWND g_window = nullptr;
HMODULE g_module = nullptr;
UINT g_wakeupMessage = 0;
EventCallback g_eventCallback = nullptr;
bool g_closeToTray = false;
bool g_trayCreated = false;
NOTIFYICONDATAW g_trayData = {};
HICON g_trayIcon = nullptr;
HANDLE g_singleInstanceMutex = nullptr;

struct ProcessEntry {
  HANDLE process = nullptr;
  HANDLE job = nullptr;
};

std::map<DWORD, ProcessEntry> g_processes;

// Registry paths used by the system proxy / autostart helpers.
const wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
const wchar_t kSavedProxyKey[] = L"Software\\Radin\\SavedProxy";
const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

void Emit(int event) {
  EventCallback callback = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    callback = g_eventCallback;
  }
  if (callback != nullptr) {
    callback(event);
  }
}

// ---------------------------------------------------------------------------
// Window helpers
// ---------------------------------------------------------------------------

struct FindWindowData {
  DWORD processId = 0;
  HWND found = nullptr;
};

BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lparam) {
  FindWindowData *data = reinterpret_cast<FindWindowData *>(lparam);
  DWORD processId = 0;
  GetWindowThreadProcessId(hwnd, &processId);
  if (processId != data->processId) {
    return TRUE;
  }
  if (!IsWindowVisible(hwnd)) {
    return TRUE;
  }
  // Keep only top level (unowned) windows.
  if (GetWindow(hwnd, GW_OWNER) != nullptr) {
    return TRUE;
  }
  data->found = hwnd;
  return FALSE;
}

// Finds the main Flutter window of the current process without relying on the
// (undocumented but stable) window class name.
HWND FindFlutterWindow() {
  FindWindowData data;
  data.processId = GetCurrentProcessId();
  EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&data));
  return data.found;
}

LRESULT CALLBACK SubclassProc(HWND hwnd, UINT msg, WPARAM wparam,
                              LPARAM lparam, UINT_PTR /*subclassId*/,
                              DWORD_PTR /*refData*/) {
  switch (msg) {
    case WM_CLOSE: {
      bool closeToTray = false;
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        closeToTray = g_closeToTray;
      }
      if (closeToTray) {
        ShowWindow(hwnd, SW_HIDE);
        Emit(kEventCloseRequested);
        return 0;
      }
      break;
    }
    case WM_DESTROY:
      if (g_trayCreated) {
        Shell_NotifyIconW(NIM_DELETE, &g_trayData);
        g_trayCreated = false;
      }
      if (g_trayIcon != nullptr) {
        DestroyIcon(g_trayIcon);
        g_trayIcon = nullptr;
      }
      break;
    default:
      if (msg == kTrayMessage) {
        switch (LOWORD(lparam)) {
          case WM_LBUTTONUP:
            Emit(kEventTrayClick);
            return 0;
          case WM_LBUTTONDBLCLK:
            Emit(kEventTrayDoubleClick);
            return 0;
          case WM_RBUTTONUP:
          case WM_CONTEXTMENU:
            win_shell_show_tray_menu();
            return 0;
          default:
            return 0;
        }
      }
      if (g_wakeupMessage != 0 && msg == g_wakeupMessage) {
        ShowWindow(hwnd, SW_SHOWNORMAL);
        SetForegroundWindow(hwnd);
        Emit(kEventWakeup);
        return 0;
      }
      break;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

void EnsureWakeupMessage() {
  if (g_wakeupMessage == 0) {
    g_wakeupMessage = RegisterWindowMessageW(L"Radin_Wakeup_b7f3c1d0");
  }
}

HICON LoadAppIcon() {
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) {
    return nullptr;
  }
  HICON icon = ExtractIconW(GetModuleHandleW(nullptr), path, 0);
  if (icon != nullptr) {
    return icon;
  }
  return LoadIconW(nullptr, IDI_APPLICATION);
}

bool AttachToWindow(HWND hwnd) {
  if (hwnd == nullptr) {
    hwnd = FindFlutterWindow();
  }
  if (hwnd == nullptr) {
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_window == hwnd) {
      return true;
    }
    g_window = hwnd;
  }
  EnsureWakeupMessage();
  SetWindowSubclass(hwnd, SubclassProc, 1, 0);
  return true;
}

// ---------------------------------------------------------------------------
// Process helpers
// ---------------------------------------------------------------------------

HANDLE CreateKillableJob() {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    return nullptr;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  // Not fatal when this fails: the process is also terminated explicitly.
  SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                          sizeof(info));
  return job;
}

HANDLE OpenLogFile(const wchar_t *path) {
  if (path == nullptr || path[0] == L'\0') {
    return nullptr;
  }
  SECURITY_ATTRIBUTES attributes = {};
  attributes.nLength = sizeof(SECURITY_ATTRIBUTES);
  attributes.bInheritHandle = TRUE;
  return CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ, &attributes,
                     OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
}

// ---------------------------------------------------------------------------
// Registry helpers
// ---------------------------------------------------------------------------

bool SetStringValue(HKEY root, const wchar_t *key, const wchar_t *name,
                    const std::wstring &value) {
  HKEY handle = nullptr;
  if (RegCreateKeyExW(root, key, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &handle,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LONG result = RegSetValueExW(
      handle, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(handle);
  return result == ERROR_SUCCESS;
}

bool SetDwordValue(HKEY root, const wchar_t *key, const wchar_t *name,
                   DWORD value) {
  HKEY handle = nullptr;
  if (RegCreateKeyExW(root, key, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &handle,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LONG result =
      RegSetValueExW(handle, name, 0, REG_DWORD,
                     reinterpret_cast<const BYTE *>(&value), sizeof(value));
  RegCloseKey(handle);
  return result == ERROR_SUCCESS;
}

bool ReadStringValue(HKEY root, const wchar_t *key, const wchar_t *name,
                     std::wstring *out) {
  HKEY handle = nullptr;
  if (RegOpenKeyExW(root, key, 0, KEY_QUERY_VALUE, &handle) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buffer[4096] = {};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  LONG result = RegQueryValueExW(handle, name, nullptr, &type,
                                 reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(handle);
  if (result != ERROR_SUCCESS || type != REG_SZ) {
    return false;
  }
  out->assign(buffer);
  return true;
}

bool ReadDwordValue(HKEY root, const wchar_t *key, const wchar_t *name,
                    DWORD *out) {
  HKEY handle = nullptr;
  if (RegOpenKeyExW(root, key, 0, KEY_QUERY_VALUE, &handle) != ERROR_SUCCESS) {
    return false;
  }
  DWORD value = 0;
  DWORD size = sizeof(value);
  DWORD type = 0;
  LONG result = RegQueryValueExW(
      handle, name, nullptr, &type, reinterpret_cast<LPBYTE>(&value), &size);
  RegCloseKey(handle);
  if (result != ERROR_SUCCESS || type != REG_DWORD) {
    return false;
  }
  *out = value;
  return true;
}

bool DeleteValue(HKEY root, const wchar_t *key, const wchar_t *name) {
  HKEY handle = nullptr;
  if (RegOpenKeyExW(root, key, 0, KEY_SET_VALUE, &handle) != ERROR_SUCCESS) {
    return false;
  }
  RegDeleteValueW(handle, name);
  RegCloseKey(handle);
  return true;
}

void RefreshInternetSettings() {
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

}  // namespace

// ---------------------------------------------------------------------------
// Tray context menu
// ---------------------------------------------------------------------------

extern "C" void win_shell_show_tray_menu() {
  HWND hwnd = g_window;
  if (hwnd == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  // Menu labels (Persian) are written as escape sequences so that the source
  // file stays ASCII.
  AppendMenuW(menu, MF_STRING, kMenuIdShow,
              L"\u0646\u0645\u0627\u06cc\u0634 / \u0645\u062e\u0641\u06cc");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuIdConnect, L"\u0627\u062a\u0635\u0627\u0644");
  AppendMenuW(menu, MF_STRING, kMenuIdDisconnect,
              L"\u0642\u0637\u0639 \u0627\u062a\u0635\u0627\u0644");
  AppendMenuW(menu, MF_STRING, kMenuIdSettings,
              L"\u062a\u0646\u0638\u06cc\u0645\u0627\u062a");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuIdExit, L"\u062e\u0631\u0648\u062c");

  POINT point = {};
  GetCursorPos(&point);
  SetForegroundWindow(hwnd);
  const UINT flags = TPM_RIGHTALIGN | TPM_BOTTOMALIGN | TPM_RETURNCMD |
                     TPM_NONOTIFY | TPM_LEFTBUTTON;
  const UINT command =
      TrackPopupMenu(menu, flags, point.x, point.y, 0, hwnd, nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  switch (command) {
    case kMenuIdShow:
      Emit(kEventMenuShow);
      break;
    case kMenuIdConnect:
      Emit(kEventMenuConnect);
      break;
    case kMenuIdDisconnect:
      Emit(kEventMenuDisconnect);
      break;
    case kMenuIdSettings:
      Emit(kEventMenuSettings);
      break;
    case kMenuIdExit:
      Emit(kEventMenuExit);
      break;
    default:
      break;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

WINSHELL_API intptr_t WinShellGetWindowHandle() {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_window != nullptr && IsWindow(g_window)) {
      return reinterpret_cast<intptr_t>(g_window);
    }
  }
  HWND hwnd = FindFlutterWindow();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_window = hwnd;
  }
  return reinterpret_cast<intptr_t>(hwnd);
}

WINSHELL_API int WinShellAttach(intptr_t hwnd) {
  return AttachToWindow(reinterpret_cast<HWND>(hwnd)) ? 1 : 0;
}

WINSHELL_API int WinShellSingleInstance(const wchar_t *name) {
  const wchar_t *mutexName =
      (name == nullptr || name[0] == L'\0') ? L"Radin_SingleInstance" : name;
  g_singleInstanceMutex = CreateMutexW(nullptr, TRUE, mutexName);
  if (g_singleInstanceMutex == nullptr) {
    return 0;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance owns the mutex: ask it to come to the foreground.
    EnsureWakeupMessage();
    if (g_wakeupMessage != 0) {
      SendMessageTimeoutW(HWND_BROADCAST, g_wakeupMessage, 0, 0,
                          SMTO_ABORTIFHUNG, 2000, nullptr);
    }
    CloseHandle(g_singleInstanceMutex);
    g_singleInstanceMutex = nullptr;
    return 0;  // not the first instance
  }
  return 1;  // first instance
}

WINSHELL_API void WinShellRegisterEventCallback(EventCallback callback) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_eventCallback = callback;
}

WINSHELL_API void WinShellSetCloseToTray(int enabled) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_closeToTray = (enabled != 0);
}

WINSHELL_API int WinShellTrayCreate(const wchar_t *tooltip) {
  HWND hwnd = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    hwnd = g_window;
  }
  if (hwnd == nullptr) {
    if (!AttachToWindow(nullptr)) {
      return 0;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    hwnd = g_window;
  }

  if (g_trayCreated) {
    Shell_NotifyIconW(NIM_DELETE, &g_trayData);
    g_trayCreated = false;
  }
  if (g_trayIcon == nullptr) {
    g_trayIcon = LoadAppIcon();
  }

  ZeroMemory(&g_trayData, sizeof(g_trayData));
  g_trayData.cbSize = sizeof(NOTIFYICONDATAW);
  g_trayData.hWnd = hwnd;
  g_trayData.uID = kIconId;
  g_trayData.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  g_trayData.uCallbackMessage = kTrayMessage;
  g_trayData.hIcon = g_trayIcon;
  if (tooltip != nullptr) {
    wcsncpy_s(g_trayData.szTip, 128, tooltip, _TRUNCATE);
  }
  if (!Shell_NotifyIconW(NIM_ADD, &g_trayData)) {
    return 0;
  }
  g_trayData.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &g_trayData);
  g_trayCreated = true;
  return 1;
}

WINSHELL_API int WinShellTraySetTooltip(const wchar_t *tooltip) {
  if (!g_trayCreated || tooltip == nullptr) {
    return 0;
  }
  g_trayData.uFlags = NIF_TIP | NIF_SHOWTIP;
  wcsncpy_s(g_trayData.szTip, 128, tooltip, _TRUNCATE);
  return Shell_NotifyIconW(NIM_MODIFY, &g_trayData) ? 1 : 0;
}

WINSHELL_API int WinShellTrayBalloon(const wchar_t *title, const wchar_t *text,
                                     int isError) {
  if (!g_trayCreated) {
    return 0;
  }
  g_trayData.uFlags = NIF_INFO | NIF_SHOWTIP;
  g_trayData.dwInfoFlags = isError != 0 ? NIIF_ERROR : NIIF_INFO;
  wcsncpy_s(g_trayData.szInfoTitle, 64, title == nullptr ? L"Radin" : title,
            _TRUNCATE);
  wcsncpy_s(g_trayData.szInfo, 256, text == nullptr ? L"" : text, _TRUNCATE);
  g_trayData.uTimeout = 5000;
  return Shell_NotifyIconW(NIM_MODIFY, &g_trayData) ? 1 : 0;
}

WINSHELL_API void WinShellTrayDestroy() {
  if (g_trayCreated) {
    Shell_NotifyIconW(NIM_DELETE, &g_trayData);
    g_trayCreated = false;
  }
}

// ---------------------------------------------------------------------------
// Window control
// ---------------------------------------------------------------------------

WINSHELL_API void WinShellShowWindow() {
  HWND hwnd = reinterpret_cast<HWND>(WinShellGetWindowHandle());
  if (hwnd == nullptr) {
    return;
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOWNORMAL);
  }
  SetForegroundWindow(hwnd);
}

WINSHELL_API void WinShellHideWindow() {
  HWND hwnd = reinterpret_cast<HWND>(WinShellGetWindowHandle());
  if (hwnd != nullptr) {
    ShowWindow(hwnd, SW_HIDE);
  }
}

WINSHELL_API int WinShellIsWindowVisible() {
  HWND hwnd = reinterpret_cast<HWND>(WinShellGetWindowHandle());
  if (hwnd == nullptr) {
    return 0;
  }
  return (IsWindowVisible(hwnd) && !IsIconic(hwnd)) ? 1 : 0;
}

WINSHELL_API void WinShellSetWindowTitle(const wchar_t *title) {
  HWND hwnd = reinterpret_cast<HWND>(WinShellGetWindowHandle());
  if (hwnd != nullptr && title != nullptr) {
    SetWindowTextW(hwnd, title);
  }
}

// ---------------------------------------------------------------------------
// System proxy
// ---------------------------------------------------------------------------

WINSHELL_API int WinShellSetSystemProxy(int enable, const wchar_t *server,
                                        const wchar_t *bypass) {
  const std::wstring proxyServer = (server == nullptr) ? L"" : server;
  const std::wstring proxyBypass = (bypass == nullptr) ? L"" : bypass;

  if (enable == 0) {
    // Restore whatever the user had before Radin touched it.
    std::wstring savedServer;
    std::wstring savedBypass;
    DWORD savedEnable = 0;
    const bool haveSaved =
        ReadStringValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyServer",
                        &savedServer) ||
        ReadDwordValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyEnable",
                       &savedEnable);
    ReadStringValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyOverride",
                    &savedBypass);

    SetDwordValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyEnable",
                  haveSaved ? savedEnable : 0);
    if (haveSaved && !savedServer.empty()) {
      SetStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyServer",
                     savedServer);
    } else {
      DeleteValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyServer");
    }
    if (haveSaved && !savedBypass.empty()) {
      SetStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyOverride",
                     savedBypass);
    } else {
      DeleteValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyOverride");
    }
    RegDeleteKeyW(HKEY_CURRENT_USER, kSavedProxyKey);
    RefreshInternetSettings();
    return 1;
  }

  // Save the current settings once, so that they can be restored on exit even
  // if the app is killed.
  DWORD alreadySaved = 0;
  if (!ReadDwordValue(HKEY_CURRENT_USER, kSavedProxyKey, L"RadinActive",
                      &alreadySaved)) {
    std::wstring currentServer;
    std::wstring currentBypass;
    DWORD currentEnable = 0;
    ReadStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyServer",
                    &currentServer);
    ReadStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyOverride",
                    &currentBypass);
    ReadDwordValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyEnable",
                   &currentEnable);
    SetDwordValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyEnable",
                  currentEnable);
    SetStringValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyServer",
                   currentServer);
    SetStringValue(HKEY_CURRENT_USER, kSavedProxyKey, L"ProxyOverride",
                   currentBypass);
    SetDwordValue(HKEY_CURRENT_USER, kSavedProxyKey, L"RadinActive", 1);
  }

  SetDwordValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyEnable", 1);
  SetStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyServer",
                 proxyServer);
  SetStringValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"ProxyOverride",
                 proxyBypass);
  SetDwordValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"AutoDetect", 0);
  DeleteValue(HKEY_CURRENT_USER, kInternetSettingsKey, L"AutoConfigURL");
  RefreshInternetSettings();
  return 1;
}

WINSHELL_API int WinShellClearSavedProxy() {
  RegDeleteKeyW(HKEY_CURRENT_USER, kSavedProxyKey);
  return 1;
}

// ---------------------------------------------------------------------------
// Process control
// ---------------------------------------------------------------------------

WINSHELL_API intptr_t WinShellStartProcess(const wchar_t *exe,
                                           const wchar_t *args,
                                           const wchar_t *workDir,
                                           const wchar_t *stdoutFile,
                                           const wchar_t *stderrFile) {
  if (exe == nullptr || exe[0] == L'\0') {
    return 0;
  }

  std::wstring command = L"\"";
  command += exe;
  command += L"\"";
  if (args != nullptr && args[0] != L'\0') {
    command += L" ";
    command += args;
  }
  // CreateProcessW may alter the buffer, so keep a writable copy.
  std::vector<wchar_t> commandBuffer(command.begin(), command.end());
  commandBuffer.push_back(L'\0');

  HANDLE stdoutHandle = OpenLogFile(stdoutFile);
  HANDLE stderrHandle = OpenLogFile(stderrFile);

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  if (stdoutHandle != nullptr || stderrHandle != nullptr) {
    startup.dwFlags |= STARTF_USESTDHANDLES;
    startup.hStdInput = nullptr;
    startup.hStdOutput = stdoutHandle != nullptr ? stdoutHandle : stderrHandle;
    startup.hStdError = stderrHandle != nullptr ? stderrHandle : stdoutHandle;
  }

  PROCESS_INFORMATION processInfo = {};
  // CREATE_NO_WINDOW keeps conhost.exe out of sight; CREATE_SUSPENDED lets us
  // attach the job object before the process can spawn children.
  const DWORD flags =
      CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT;
  BOOL ok = CreateProcessW(
      nullptr, commandBuffer.data(), nullptr, nullptr,
      (stdoutHandle != nullptr || stderrHandle != nullptr) ? TRUE : FALSE,
      flags, nullptr,
      (workDir != nullptr && workDir[0] != L'\0') ? workDir : nullptr, &startup,
      &processInfo);

  if (stdoutHandle != nullptr) {
    CloseHandle(stdoutHandle);
  }
  if (stderrHandle != nullptr) {
    CloseHandle(stderrHandle);
  }

  if (!ok) {
    return 0;
  }

  HANDLE job = CreateKillableJob();
  if (job != nullptr) {
    AssignProcessToJobObject(job, processInfo.hProcess);
  }
  ResumeThread(processInfo.hThread);
  CloseHandle(processInfo.hThread);

  ProcessEntry entry;
  entry.process = processInfo.hProcess;
  entry.job = job;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_processes[processInfo.dwProcessId] = entry;
  }
  return static_cast<intptr_t>(processInfo.dwProcessId);
}

WINSHELL_API int WinShellIsProcessRunning(intptr_t pid) {
  ProcessEntry entry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    std::map<DWORD, ProcessEntry>::iterator it =
        g_processes.find(static_cast<DWORD>(pid));
    if (it == g_processes.end()) {
      return 0;
    }
    entry = it->second;
  }
  DWORD exitCode = 0;
  if (GetExitCodeProcess(entry.process, &exitCode) &&
      exitCode == STILL_ACTIVE) {
    return 1;
  }
  return 0;
}

WINSHELL_API int WinShellStopProcess(intptr_t pid, int timeoutMs) {
  ProcessEntry entry;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    std::map<DWORD, ProcessEntry>::iterator it =
        g_processes.find(static_cast<DWORD>(pid));
    if (it == g_processes.end()) {
      return 0;
    }
    entry = it->second;
    g_processes.erase(it);
  }

  // Closing the job object kills the whole process tree.
  if (entry.job != nullptr) {
    CloseHandle(entry.job);
    WaitForSingleObject(entry.process,
                        timeoutMs > 0 ? static_cast<DWORD>(timeoutMs) : 3000);
  }
  DWORD exitCode = 0;
  if (GetExitCodeProcess(entry.process, &exitCode) &&
      exitCode == STILL_ACTIVE) {
    TerminateProcess(entry.process, 1);
    WaitForSingleObject(entry.process, 2000);
  }
  CloseHandle(entry.process);
  return 1;
}

WINSHELL_API int WinShellKillProcessTreeByName(const wchar_t *processName) {
  if (processName == nullptr) {
    return 0;
  }
  // Uses taskkill so that we also reap processes we did not start (for example
  // a core left behind after a crash).
  std::wstring command = L"/c taskkill /F /T /IM \"";
  command += processName;
  command += L"\" >nul 2>&1";
  ShellExecuteW(nullptr, L"open", L"cmd.exe", command.c_str(), nullptr,
                SW_HIDE);
  return 1;
}

// ---------------------------------------------------------------------------
// OS / privileges
// ---------------------------------------------------------------------------

WINSHELL_API void WinShellGetOsVersion(int *outMajor, int *outMinor,
                                       int *outBuild, int *outIsServer) {
  int major = 0;
  int minor = 0;
  int build = 0;
  int server = 0;

  // RtlGetVersion is not affected by the application manifest and is present on
  // every Windows since 2000.
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    ntdll = LoadLibraryW(L"ntdll.dll");
  }
  if (ntdll != nullptr) {
    typedef LONG(WINAPI * RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
    RtlGetVersionPtr rtlGetVersion = reinterpret_cast<RtlGetVersionPtr>(
        GetProcAddress(ntdll, "RtlGetVersion"));
    if (rtlGetVersion != nullptr) {
      // RTL_OSVERSIONINFOEXW (not RTL_OSVERSIONINFOW) carries wProductType.
      RTL_OSVERSIONINFOEXW info = {};
      info.dwOSVersionInfoSize = sizeof(info);
      if (rtlGetVersion(reinterpret_cast<PRTL_OSVERSIONINFOW>(&info)) == 0) {
        major = static_cast<int>(info.dwMajorVersion);
        minor = static_cast<int>(info.dwMinorVersion);
        build = static_cast<int>(info.dwBuildNumber);
        server = (info.wProductType != VER_NT_WORKSTATION) ? 1 : 0;
      }
    }
  }

  if (major == 0) {
    // Fallback (deprecated but always available).
#pragma warning(push)
#pragma warning(disable : 4996)
    DWORD version = GetVersion();
#pragma warning(pop)
    major = static_cast<int>(LOBYTE(LOWORD(version)));
    minor = static_cast<int>(HIBYTE(LOWORD(version)));
    build = static_cast<int>(HIWORD(version));
  }

  if (outMajor != nullptr) {
    *outMajor = major;
  }
  if (outMinor != nullptr) {
    *outMinor = minor;
  }
  if (outBuild != nullptr) {
    *outBuild = build;
  }
  if (outIsServer != nullptr) {
    *outIsServer = server;
  }
}

WINSHELL_API int WinShellIsAdmin() {
  SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
  PSID administratorsGroup = nullptr;
  if (!AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                &administratorsGroup)) {
    return 0;
  }
  BOOL isMember = FALSE;
  if (!CheckTokenMembership(nullptr, administratorsGroup, &isMember)) {
    isMember = FALSE;
  }
  FreeSid(administratorsGroup);
  return isMember ? 1 : 0;
}

WINSHELL_API int WinShellRunElevated(const wchar_t *exe, const wchar_t *args) {
  if (exe == nullptr) {
    return 0;
  }
  intptr_t result = reinterpret_cast<intptr_t>(
      ShellExecuteW(nullptr, L"runas", exe, args, nullptr, SW_SHOWNORMAL));
  return result > 32 ? 1 : 0;
}

WINSHELL_API int WinShellOpenUrl(const wchar_t *url) {
  if (url == nullptr) {
    return 0;
  }
  intptr_t result = reinterpret_cast<intptr_t>(
      ShellExecuteW(nullptr, L"open", url, nullptr, nullptr, SW_SHOWNORMAL));
  return result > 32 ? 1 : 0;
}

WINSHELL_API int WinShellShowInExplorer(const wchar_t *path) {
  if (path == nullptr) {
    return 0;
  }
  std::wstring args = L"/select,\"";
  args += path;
  args += L"\"";
  intptr_t result = reinterpret_cast<intptr_t>(ShellExecuteW(
      nullptr, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOWNORMAL));
  return result > 32 ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Autostart
// ---------------------------------------------------------------------------

WINSHELL_API int WinShellSetAutoStart(int enable, const wchar_t *appName,
                                      const wchar_t *exePath,
                                      const wchar_t *args) {
  if (appName == nullptr || exePath == nullptr) {
    return 0;
  }
  HKEY handle = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &handle, nullptr) != ERROR_SUCCESS) {
    return 0;
  }
  LONG result = 0;
  if (enable != 0) {
    std::wstring value = L"\"";
    value += exePath;
    value += L"\"";
    if (args != nullptr && args[0] != L'\0') {
      value += L" ";
      value += args;
    }
    result = RegSetValueExW(
        handle, appName, 0, REG_SZ,
        reinterpret_cast<const BYTE *>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(handle, appName);
  }
  RegCloseKey(handle);
  return result == ERROR_SUCCESS ? 1 : 0;
}

WINSHELL_API int WinShellGetAutoStart(const wchar_t *appName) {
  if (appName == nullptr) {
    return 0;
  }
  HKEY handle = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &handle) !=
      ERROR_SUCCESS) {
    return 0;
  }
  LONG result =
      RegQueryValueExW(handle, appName, nullptr, nullptr, nullptr, nullptr);
  RegCloseKey(handle);
  return result == ERROR_SUCCESS ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Clipboard
// ---------------------------------------------------------------------------

WINSHELL_API void WinShellSetClipboardText(const wchar_t *text) {
  if (text == nullptr || !OpenClipboard(nullptr)) {
    return;
  }
  size_t bytes = (wcslen(text) + 1) * sizeof(wchar_t);
  HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (global != nullptr) {
    wchar_t *target = static_cast<wchar_t *>(GlobalLock(global));
    if (target != nullptr) {
      memcpy(target, text, bytes);
      GlobalUnlock(global);
    }
    EmptyClipboard();
    SetClipboardData(CF_UNICODETEXT, global);
  }
  CloseClipboard();
}

WINSHELL_API wchar_t *WinShellGetClipboardText() {
  if (!OpenClipboard(nullptr)) {
    return nullptr;
  }
  HANDLE data = GetClipboardData(CF_UNICODETEXT);
  if (data == nullptr) {
    CloseClipboard();
    return nullptr;
  }
  wchar_t *source = static_cast<wchar_t *>(GlobalLock(data));
  wchar_t *result = nullptr;
  if (source != nullptr) {
    size_t bytes = (wcslen(source) + 1) * sizeof(wchar_t);
    result = static_cast<wchar_t *>(CoTaskMemAlloc(bytes));
    if (result != nullptr) {
      memcpy(result, source, bytes);
    }
    GlobalUnlock(data);
  }
  CloseClipboard();
  return result;
}

WINSHELL_API void WinShellFreeString(wchar_t *pointer) {
  if (pointer != nullptr) {
    CoTaskMemFree(pointer);
  }
}

// ---------------------------------------------------------------------------
// Locale
// ---------------------------------------------------------------------------

WINSHELL_API void WinShellGetUserLocale(wchar_t *buffer, int bufferLength) {
  if (buffer == nullptr || bufferLength <= 0) {
    return;
  }
  buffer[0] = L'\0';
  wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH) > 0) {
    wcsncpy_s(buffer, static_cast<size_t>(bufferLength), locale, _TRUNCATE);
  }
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID /*reserved*/) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
  }
  if (reason == DLL_PROCESS_DETACH) {
    if (g_trayCreated) {
      Shell_NotifyIconW(NIM_DELETE, &g_trayData);
      g_trayCreated = false;
    }
    if (g_trayIcon != nullptr) {
      DestroyIcon(g_trayIcon);
      g_trayIcon = nullptr;
    }
    if (g_singleInstanceMutex != nullptr) {
      CloseHandle(g_singleInstanceMutex);
      g_singleInstanceMutex = nullptr;
    }
  }
  return TRUE;
}
