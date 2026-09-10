import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Events raised by the native layer (tray interaction, close requests, ...).
enum WinShellEvent {
  trayClick(1),
  trayDoubleClick(2),
  closeRequested(3),
  menuShow(4),
  menuConnect(5),
  menuDisconnect(6),
  menuExit(7),
  wakeup(8),
  menuSettings(9);

  const WinShellEvent(this.nativeValue);
  final int nativeValue;

  static WinShellEvent? fromNative(int value) {
    for (final event in values) {
      if (event.nativeValue == value) {
        return event;
      }
    }
    return null;
  }
}

/// Real Windows version, obtained through `RtlGetVersion` so that it is not
/// affected by the application manifest.
class WinShellOsVersion {
  const WinShellOsVersion({
    required this.major,
    required this.minor,
    required this.build,
    required this.isServer,
  });

  final int major;
  final int minor;
  final int build;
  final bool isServer;

  /// Windows 7 / Server 2008 R2 (6.1) and Windows 8 / 8.1 (6.2 / 6.3).
  bool get isLegacyWindows => major == 6;

  /// Windows 10 (build < 22000) and Windows 11 (build >= 22000).
  bool get isWindows10Or11 => major == 10;

  bool get isWindows11 => major == 10 && build >= 22000;

  /// Cores built with Go >= 1.21 refuse to start on anything older than
  /// Windows 10, so legacy systems must use the Win7 flavoured binaries.
  bool get needsLegacyCore => isLegacyWindows;

  @override
  String toString() => '$major.$minor.$build${isServer ? ' (Server)' : ''}';
}

// ---------------------------------------------------------------------------
// Native signatures
// ---------------------------------------------------------------------------

typedef _GetWindowHandleNative = IntPtr Function();
typedef _GetWindowHandleDart = int Function();
typedef _AttachNative = Int32 Function(IntPtr hwnd);
typedef _AttachDart = int Function(int hwnd);
typedef _SingleInstanceNative = Int32 Function(Pointer<Utf16> name);
typedef _SingleInstanceDart = int Function(Pointer<Utf16> name);
typedef _RegisterEventCallbackNative = Void Function(
    Pointer<NativeFunction<Void Function(Int32)>> callback);
typedef _RegisterEventCallbackDart = void Function(
    Pointer<NativeFunction<Void Function(Int32)>> callback);
typedef _SetCloseToTrayNative = Void Function(Int32 enabled);
typedef _SetCloseToTrayDart = void Function(int enabled);
typedef _TrayCreateNative = Int32 Function(Pointer<Utf16> tooltip);
typedef _TrayCreateDart = int Function(Pointer<Utf16> tooltip);
typedef _TraySetTooltipNative = Int32 Function(Pointer<Utf16> tooltip);
typedef _TraySetTooltipDart = int Function(Pointer<Utf16> tooltip);
typedef _TrayBalloonNative = Int32 Function(
    Pointer<Utf16> title, Pointer<Utf16> text, Int32 isError);
typedef _TrayBalloonDart = int Function(
    Pointer<Utf16> title, Pointer<Utf16> text, int isError);
typedef _TrayDestroyNative = Void Function();
typedef _TrayDestroyDart = void Function();
typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _SetWindowTitleNative = Void Function(Pointer<Utf16> title);
typedef _SetWindowTitleDart = void Function(Pointer<Utf16> title);
typedef _IsWindowVisibleNative = Int32 Function();
typedef _IsWindowVisibleDart = int Function();
typedef _SetSystemProxyNative = Int32 Function(
    Int32 enable, Pointer<Utf16> server, Pointer<Utf16> bypass);
typedef _SetSystemProxyDart = int Function(
    int enable, Pointer<Utf16> server, Pointer<Utf16> bypass);
typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _StartProcessNative = IntPtr Function(Pointer<Utf16> exe,
    Pointer<Utf16> args, Pointer<Utf16> workDir, Pointer<Utf16> out, Pointer<Utf16> err);
typedef _StartProcessDart = int Function(Pointer<Utf16> exe, Pointer<Utf16> args,
    Pointer<Utf16> workDir, Pointer<Utf16> out, Pointer<Utf16> err);
typedef _StopProcessNative = Int32 Function(IntPtr pid, Int32 timeoutMs);
typedef _StopProcessDart = int Function(int pid, int timeoutMs);
typedef _IsProcessRunningNative = Int32 Function(IntPtr pid);
typedef _IsProcessRunningDart = int Function(int pid);
typedef _KillProcessTreeNative = Int32 Function(Pointer<Utf16> processName);
typedef _KillProcessTreeDart = int Function(Pointer<Utf16> processName);
typedef _GetOsVersionNative = Void Function(Pointer<Int32> major,
    Pointer<Int32> minor, Pointer<Int32> build, Pointer<Int32> isServer);
typedef _GetOsVersionDart = void Function(Pointer<Int32> major,
    Pointer<Int32> minor, Pointer<Int32> build, Pointer<Int32> isServer);
typedef _RunElevatedNative = Int32 Function(Pointer<Utf16> exe, Pointer<Utf16> args);
typedef _RunElevatedDart = int Function(Pointer<Utf16> exe, Pointer<Utf16> args);
typedef _StringIntNative = Int32 Function(Pointer<Utf16> value);
typedef _StringIntDart = int Function(Pointer<Utf16> value);
typedef _SetAutoStartNative = Int32 Function(Int32 enable, Pointer<Utf16> appName,
    Pointer<Utf16> exePath, Pointer<Utf16> args);
typedef _SetAutoStartDart = int Function(
    int enable, Pointer<Utf16> appName, Pointer<Utf16> exePath, Pointer<Utf16> args);
typedef _SetClipboardNative = Void Function(Pointer<Utf16> text);
typedef _SetClipboardDart = void Function(Pointer<Utf16> text);
typedef _GetClipboardNative = Pointer<Utf16> Function();
typedef _GetClipboardDart = Pointer<Utf16> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf16> pointer);
typedef _FreeStringDart = void Function(Pointer<Utf16> pointer);
typedef _GetUserLocaleNative = Void Function(Pointer<Utf16> buffer, Int32 length);
typedef _GetUserLocaleDart = void Function(Pointer<Utf16> buffer, int length);

/// Late-bound native entry points. Constructed once, only on Windows.
class _Native {
  _Native(DynamicLibrary lib)
      : getWindowHandle =
            lib.lookupFunction<_GetWindowHandleNative, _GetWindowHandleDart>(
                'WinShellGetWindowHandle'),
        attach = lib.lookupFunction<_AttachNative, _AttachDart>('WinShellAttach'),
        singleInstance = lib
            .lookupFunction<_SingleInstanceNative, _SingleInstanceDart>(
                'WinShellSingleInstance'),
        registerEventCallback = lib.lookupFunction<_RegisterEventCallbackNative,
            _RegisterEventCallbackDart>('WinShellRegisterEventCallback'),
        setCloseToTray = lib.lookupFunction<_SetCloseToTrayNative,
            _SetCloseToTrayDart>('WinShellSetCloseToTray'),
        trayCreate =
            lib.lookupFunction<_TrayCreateNative, _TrayCreateDart>('WinShellTrayCreate'),
        traySetTooltip = lib
            .lookupFunction<_TraySetTooltipNative, _TraySetTooltipDart>(
                'WinShellTraySetTooltip'),
        trayBalloon = lib
            .lookupFunction<_TrayBalloonNative, _TrayBalloonDart>('WinShellTrayBalloon'),
        trayDestroy =
            lib.lookupFunction<_TrayDestroyNative, _TrayDestroyDart>('WinShellTrayDestroy'),
        showWindow = lib.lookupFunction<_VoidNative, _VoidDart>('WinShellShowWindow'),
        hideWindow = lib.lookupFunction<_VoidNative, _VoidDart>('WinShellHideWindow'),
        setWindowTitle = lib
            .lookupFunction<_SetWindowTitleNative, _SetWindowTitleDart>(
                'WinShellSetWindowTitle'),
        isWindowVisible = lib
            .lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>(
                'WinShellIsWindowVisible'),
        setSystemProxy = lib
            .lookupFunction<_SetSystemProxyNative, _SetSystemProxyDart>(
                'WinShellSetSystemProxy'),
        clearSavedProxy =
            lib.lookupFunction<_Int32Native, _Int32Dart>('WinShellClearSavedProxy'),
        startProcess = lib
            .lookupFunction<_StartProcessNative, _StartProcessDart>('WinShellStartProcess'),
        stopProcess =
            lib.lookupFunction<_StopProcessNative, _StopProcessDart>('WinShellStopProcess'),
        isProcessRunning = lib
            .lookupFunction<_IsProcessRunningNative, _IsProcessRunningDart>(
                'WinShellIsProcessRunning'),
        killProcessTree = lib
            .lookupFunction<_KillProcessTreeNative, _KillProcessTreeDart>(
                'WinShellKillProcessTreeByName'),
        getOsVersion = lib
            .lookupFunction<_GetOsVersionNative, _GetOsVersionDart>('WinShellGetOsVersion'),
        isAdmin = lib.lookupFunction<_Int32Native, _Int32Dart>('WinShellIsAdmin'),
        runElevated =
            lib.lookupFunction<_RunElevatedNative, _RunElevatedDart>('WinShellRunElevated'),
        openUrl = lib.lookupFunction<_StringIntNative, _StringIntDart>('WinShellOpenUrl'),
        showInExplorer = lib
            .lookupFunction<_StringIntNative, _StringIntDart>('WinShellShowInExplorer'),
        setAutoStart = lib
            .lookupFunction<_SetAutoStartNative, _SetAutoStartDart>('WinShellSetAutoStart'),
        getAutoStart = lib
            .lookupFunction<_StringIntNative, _StringIntDart>('WinShellGetAutoStart'),
        setClipboardText = lib
            .lookupFunction<_SetClipboardNative, _SetClipboardDart>(
                'WinShellSetClipboardText'),
        getClipboardText = lib
            .lookupFunction<_GetClipboardNative, _GetClipboardDart>(
                'WinShellGetClipboardText'),
        freeString =
            lib.lookupFunction<_FreeStringNative, _FreeStringDart>('WinShellFreeString'),
        getUserLocale = lib
            .lookupFunction<_GetUserLocaleNative, _GetUserLocaleDart>(
                'WinShellGetUserLocale');

  final _GetWindowHandleDart getWindowHandle;
  final _AttachDart attach;
  final _SingleInstanceDart singleInstance;
  final _RegisterEventCallbackDart registerEventCallback;
  final _SetCloseToTrayDart setCloseToTray;
  final _TrayCreateDart trayCreate;
  final _TraySetTooltipDart traySetTooltip;
  final _TrayBalloonDart trayBalloon;
  final _TrayDestroyDart trayDestroy;
  final _VoidDart showWindow;
  final _VoidDart hideWindow;
  final _SetWindowTitleDart setWindowTitle;
  final _IsWindowVisibleDart isWindowVisible;
  final _SetSystemProxyDart setSystemProxy;
  final _Int32Dart clearSavedProxy;
  final _StartProcessDart startProcess;
  final _StopProcessDart stopProcess;
  final _IsProcessRunningDart isProcessRunning;
  final _KillProcessTreeDart killProcessTree;
  final _GetOsVersionDart getOsVersion;
  final _Int32Dart isAdmin;
  final _RunElevatedDart runElevated;
  final _StringIntDart openUrl;
  final _StringIntDart showInExplorer;
  final _SetAutoStartDart setAutoStart;
  final _StringIntDart getAutoStart;
  final _SetClipboardDart setClipboardText;
  final _GetClipboardDart getClipboardText;
  final _FreeStringDart freeString;
  final _GetUserLocaleDart getUserLocale;
}

// ---------------------------------------------------------------------------
// Public facade
// ---------------------------------------------------------------------------

/// Singleton accessor for the native Windows shell helpers.
final WinShell winShell = WinShell._();

class WinShell {
  WinShell._();

  static const String _libraryName = 'win_shell.dll';
  static const String appName = 'Radin';

  _Native? _native;
  bool _loadAttempted = false;
  bool get isAvailable => _load() != null;

  final StreamController<WinShellEvent> _events =
      StreamController<WinShellEvent>.broadcast();
  NativeCallable<Void Function(Int32)>? _eventCallback;

  Stream<WinShellEvent> get events => _events.stream;

  _Native? _load() {
    if (_loadAttempted) {
      return _native;
    }
    _loadAttempted = true;
    if (!Platform.isWindows) {
      return null;
    }
    DynamicLibrary? library;
    try {
      library = DynamicLibrary.open(_libraryName);
    } on Object {
      library = null;
    }
    if (library == null) {
      return null;
    }
    _Native? native;
    try {
      native = _Native(library);
    } on Object {
      native = null;
    }
    if (native != null) {
      _eventCallback = NativeCallable<Void Function(Int32)>.listener((int value) {
        final event = WinShellEvent.fromNative(value);
        if (event != null && !_events.isClosed) {
          _events.add(event);
        }
      });
      native.registerEventCallback(_eventCallback!.nativeFunction);
    }
    _native = native;
    return native;
  }

  // -- window ---------------------------------------------------------------

  bool attach([int? hwnd]) {
    final n = _load();
    return n != null && n.attach(hwnd ?? 0) != 0;
  }

  int getWindowHandle() => _load()?.getWindowHandle() ?? 0;

  void setCloseToTray(bool enabled) =>
      _load()?.setCloseToTray(enabled ? 1 : 0);

  void showWindow() => _load()?.showWindow();

  void hideWindow() => _load()?.hideWindow();

  bool isWindowVisible() => (_load()?.isWindowVisible() ?? 0) != 0;

  void setWindowTitle(String title) => using((arena) {
        _load()?.setWindowTitle(title.toNativeUtf16(allocator: arena));
      });

  /// Returns `true` when this is the only running instance of the app.
  bool claimSingleInstance([String name = 'Radin_SingleInstance']) =>
      using((arena) {
        final n = _load();
        if (n == null) {
          return true;
        }
        return n.singleInstance(name.toNativeUtf16(allocator: arena)) != 0;
      });

  // -- tray -----------------------------------------------------------------

  bool createTray(String tooltip) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.trayCreate(tooltip.toNativeUtf16(allocator: arena)) != 0;
      });

  bool setTrayTooltip(String tooltip) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.traySetTooltip(tooltip.toNativeUtf16(allocator: arena)) != 0;
      });

  bool showBalloon(String title, String text, {bool isError = false}) =>
      using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.trayBalloon(title.toNativeUtf16(allocator: arena),
                text.toNativeUtf16(allocator: arena), isError ? 1 : 0) !=
            0;
      });

  void destroyTray() => _load()?.trayDestroy();

  // -- system proxy ---------------------------------------------------------

  /// Turns the Windows system proxy on. [server] is for example
  /// `127.0.0.1:2080` or `http=127.0.0.1:2080;socks=127.0.0.1:2081`.
  bool setSystemProxy({required String server, required String bypass}) =>
      using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.setSystemProxy(1, server.toNativeUtf16(allocator: arena),
                bypass.toNativeUtf16(allocator: arena)) !=
            0;
      });

  /// Restores the proxy configuration that was active before Radin took over.
  bool clearSystemProxy() => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.setSystemProxy(0, ''.toNativeUtf16(allocator: arena),
                ''.toNativeUtf16(allocator: arena)) !=
            0;
      });

  bool clearSavedProxy() => (_load()?.clearSavedProxy() ?? 0) != 0;

  // -- processes ------------------------------------------------------------

  /// Starts [exe] hidden, with no console window. Output is appended to the
  /// given files when provided. Returns the process id, or `0` on failure.
  int startProcess(
    String exe, {
    String args = '',
    String? workDir,
    String? stdoutFile,
    String? stderrFile,
  }) =>
      using((arena) {
        final n = _load();
        if (n == null) {
          return 0;
        }
        return n.startProcess(
          exe.toNativeUtf16(allocator: arena),
          args.toNativeUtf16(allocator: arena),
          (workDir ?? '').toNativeUtf16(allocator: arena),
          (stdoutFile ?? '').toNativeUtf16(allocator: arena),
          (stderrFile ?? '').toNativeUtf16(allocator: arena),
        );
      });

  bool stopProcess(int pid, {int timeoutMs = 3000}) =>
      (_load()?.stopProcess(pid, timeoutMs) ?? 0) != 0;

  bool isProcessRunning(int pid) =>
      (_load()?.isProcessRunning(pid) ?? 0) != 0;

  /// Kills leftover core processes (for example after a crash).
  bool killProcessTree(String processName) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.killProcessTree(processName.toNativeUtf16(allocator: arena)) != 0;
      });

  // -- OS -------------------------------------------------------------------

  WinShellOsVersion getOsVersion() => using((arena) {
        final n = _load();
        final major = arena<Int32>();
        final minor = arena<Int32>();
        final build = arena<Int32>();
        final isServer = arena<Int32>();
        major.value = 0;
        minor.value = 0;
        build.value = 0;
        isServer.value = 0;
        n?.getOsVersion(major, minor, build, isServer);
        return WinShellOsVersion(
          major: major.value,
          minor: minor.value,
          build: build.value,
          isServer: isServer.value != 0,
        );
      });

  bool isAdmin() => (_load()?.isAdmin() ?? 0) != 0;

  bool runElevated(String exe, [String args = '']) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.runElevated(exe.toNativeUtf16(allocator: arena),
                args.toNativeUtf16(allocator: arena)) !=
            0;
      });

  // -- misc -----------------------------------------------------------------

  bool openUrl(String url) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.openUrl(url.toNativeUtf16(allocator: arena)) != 0;
      });

  bool showInExplorer(String path) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.showInExplorer(path.toNativeUtf16(allocator: arena)) != 0;
      });

  bool setAutoStart({
    required bool enabled,
    required String exePath,
    String args = '',
  }) =>
      using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.setAutoStart(
              enabled ? 1 : 0,
              appName.toNativeUtf16(allocator: arena),
              exePath.toNativeUtf16(allocator: arena),
              args.toNativeUtf16(allocator: arena),
            ) !=
            0;
      });

  bool getAutoStart([String name = appName]) => using((arena) {
        final n = _load();
        if (n == null) {
          return false;
        }
        return n.getAutoStart(name.toNativeUtf16(allocator: arena)) != 0;
      });

  void setClipboardText(String text) => using((arena) {
        _load()?.setClipboardText(text.toNativeUtf16(allocator: arena));
      });

  String? getClipboardText() {
    final n = _load();
    if (n == null) {
      return null;
    }
    final pointer = n.getClipboardText();
    if (pointer == nullptr) {
      return null;
    }
    try {
      return pointer.toDartString();
    } finally {
      n.freeString(pointer);
    }
  }

  /// Locale name of the current user, for example `fa-IR`.
  String getUserLocale() => using((arena) {
        final buffer = arena<Utf16>(16);
        _load()?.getUserLocale(buffer, 16);
        return buffer.toDartString();
      });
}
