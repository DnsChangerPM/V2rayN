#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

#pragma comment(lib, "dwmapi.lib")

namespace {

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values into physical for lowerdpi
// monitors.
long Scale(int source, double scale_factor) {
  return static_cast<long>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the one and only instance of this class.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Registers the window class. Returns true if the registration was
  // successful, or if the window class was already registered.
  bool GetWindowClass(ATOM* out) {
    if (!class_registered_) {
      WNDCLASS window_class{};
      window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
      window_class.lpszClassName = kWindowClassName;
      window_class.style = CS_HREDRAW | CS_VREDRAW;
      window_class.cbClsExtra = 0;
      window_class.cbWndExtra = 0;
      window_class.hInstance = GetModuleHandle(nullptr);
      window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
      window_class.hbrBackground = 0;
      window_class.lpszMenuName = nullptr;
      window_class.lpfnWndProc = Win32Window::WndProc;
      *out = RegisterClass(&window_class);
      if (*out) {
        class_registered_ = true;
      }
    } else {
      WNDCLASS window_class{};
      GetClassInfo(GetModuleHandle(nullptr), kWindowClassName, &window_class);
      *out = 0;
    }
    return class_registered_;
  }

  // Unregisters the window class. Returns true if the unregistration was
  // successful, will return false if the window class is still registered
  // because other windows are using it.
  bool UnregisterWindowClass() {
    if (!class_registered_) {
      return true;
    }
    UnregisterClass(kWindowClassName, nullptr);
    class_registered_ = false;
    return true;
  }

 private:
  WindowClassRegistrar() = default;
  static WindowClassRegistrar* instance_;
  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  // Register the window class.
  ATOM window_class_id;
  if (!WindowClassRegistrar::GetInstance()->GetWindowClass(&window_class_id)) {
    return false;
  }
  const wchar_t* window_class_name = kWindowClassName;

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class_name, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE: {
      if (child_content_ != nullptr) {
        auto size = GetSize();
        MoveWindow(child_content_, 0, 0, size.width, size.height, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_MENUCHAR:
      // Don't exit full screen mode on accelerator key press since it causes
      // an undesired beep.
      return MAKELRESULT(0, MNC_CLOSE);

    case WM_SYNCPAINT:
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
    case WM_MOUSEWHEEL:
    case WM_MOUSELEAVE:
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
    case WM_CHAR:
    case WM_SYSCHAR:
      // Events that are handled by the Flutter engine should be forwarded
      // to the child window.
      if (child_content_ != nullptr) {
        return SendMessage(child_content_, message, wparam, lparam);
      }
      break;

    default:
      break;
  }
  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    HWND handle = window_handle_;
    window_handle_ = nullptr;
    DestroyWindow(handle);
  }

  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);

  // Get the client area.
  RECT frame_rect;
  GetClientRect(window_handle_, &frame_rect);

  // Move the window to the top left of the frame rect.
  MoveWindow(content, frame_rect.left, frame_rect.top,
             frame_rect.right - frame_rect.left,
             frame_rect.bottom - frame_rect.top, TRUE);

  SetFocus(child_content_);
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetTitle(const std::wstring& title) {
  title_ = title;
  if (window_handle_ != nullptr) {
    SetWindowText(window_handle_, title.c_str());
  }
}

std::wstring Win32Window::GetTitle() {
  return title_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op by default, to be overridden by inheriting classes.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op by default, to be overridden by inheriting classes.
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::UpdateTheme(HWND const window) {
  // Dark title bar supported on Windows 10 1809+ only; harmless elsewhere.
  DWORD light_mode = 0;
  DwmSetWindowAttribute(window, 20 /*DWMWA_USE_IMMERSIVE_DARK_MODE*/,
                        &light_mode, sizeof(light_mode));
}

Win32Window::Point Win32Window::GetPosition() {
  RECT rect;
  GetWindowRect(window_handle_, &rect);
  return Point(rect.left, rect.top);
}

Win32Window::Size Win32Window::GetSize() {
  RECT rect;
  GetClientRect(window_handle_, &rect);
  return Size(rect.right - rect.left, rect.bottom - rect.top);
}
