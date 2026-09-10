/// Windows shell integration for the Radin client.
///
/// Thin Dart wrapper around the native `win_shell.dll` that ships with the app.
/// Everything here is a no-op (and reports `false`) if the library cannot be
/// loaded, so the rest of the app never has to null-check the platform.
library;

export 'src/win_shell.dart'
    show WinShell, WinShellEvent, WinShellOsVersion, winShell;
