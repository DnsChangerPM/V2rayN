#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS -- and thus you should ensure that the
  // specified size is larger than the minimum size of the window.
  // Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release the OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window. Size of the content is unrelated to
  // window size.
  void SetChildContent(HWND content);

  // Returns the backing Window handle, after it has been created.
  HWND GetHandle();

  // Set the text of the window title bar.
  void SetTitle(const std::wstring& title);

  // Returns the text of the window title bar.
  std::wstring GetTitle();

  // Quit the message loop when this window closes (main window behavior).
  void SetQuitOnClose(bool quit_on_close);

  // Returns the position of the current window in screen coordinates.
  Point GetPosition();

  // Returns the size of the current window.
  Size GetSize();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  // Called when Create is called, allowing subclass window-related setup.
  // Subclasses should return false if setup fails.
  virtual bool OnCreate();
  virtual void OnDestroy();

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|.
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Returns the client area of the window in window coordinates.
  RECT GetClientArea();

  // Processes all window messages except for WM_NCCREATE.
  LRESULT MessageHandler(HWND hwnd,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept;

 private:
  friend class WindowClassRegistrar;

  // Applies the dark title-bar theme where the OS supports it (no-op
  // elsewhere).
  void UpdateTheme(HWND const window);

  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
  bool quit_on_close_ = false;

  // The least recently set window title, for serialization purposes.
  std::wstring title_ = L"";
};

#endif  // RUNNER_WIN32_WINDOW_H_
