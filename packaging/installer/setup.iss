; ---------------------------------------------------------------------------
;  Radin installer (Inno Setup 6.3+)
;
;  Targets Windows 7 SP1 through Windows 11 (x64 only, because the cores and
;  the Flutter engine are built for amd64).
;
;  Compile with:
;    ISCC.exe setup.iss /DMyAppVersion=1.2.3 /DSourceDir=..\..\dist\app ^
;       /DCoresDir=..\..\dist\cores /DRedistDir=..\..\dist\redist ^
;       /DOutputDir=..\..\dist
; ---------------------------------------------------------------------------

#define MyAppName "Radin"
#define MyAppPublisher "Radin"
#define MyAppURL "https://github.com/DnsChangerPM/V2rayN"
#define MyAppExeName "radin.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\app"
#endif
#ifndef CoresDir
  #define CoresDir "..\..\dist\cores"
#endif
#ifndef RedistDir
  #define RedistDir "..\..\dist\redist"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef SetupIcon
  #define SetupIcon "..\..\windows_custom\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{A1F4E2C6-7B3D-4E8A-9C21-5D6F0B8E4A17}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
DefaultDirName={autopf}\Radin
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
LicenseFile=
OutputDir={#OutputDir}
OutputBaseFilename=Radin-Setup-{#MyAppVersion}
SetupIconFile={#SetupIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4
WizardStyle=modern
WizardResizable=no
; Windows 7 (6.1) is the oldest supported system.
MinVersion=6.1
; 64-bit only: the bundled cores and the Flutter engine are amd64 builds.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startafterinstall"; Description: "Run {#MyAppName} after installation"; GroupDescription: "After installation:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#CoresDir}\*"; DestDir: "{app}\core"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RedistDir}\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedInstallVCRedist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
    Check: NeedInstallVCRedist; StatusMsg: "Installing the Visual C++ runtime..."; \
    Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Tasks: startafterinstall; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: files; Name: "{localappdata}\Radin\*"

[Code]
var
  VCRedistNeeded: Boolean;

/// True when the Visual C++ 2015-2022 runtime (x64) is missing.
/// Flutter's engine links against it dynamically.
function NeedInstallVCRedist(): Boolean;
var
  Version: String;
  RuntimePath: String;
begin
  Result := VCRedistNeeded;

  if not Result then
    exit;

  if RegQueryStringValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
       'Version', Version) then
  begin
    Log('Found VC++ runtime: ' + Version);
    Result := False;
    exit;
  end;

  if RegQueryStringValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
       'Version', Version) then
  begin
    Log('Found VC++ runtime: ' + Version);
    Result := False;
    exit;
  end;

  RuntimePath := ExpandConstant('{sys}\vcruntime140.dll');
  if FileExists(RuntimePath) then
  begin
    Log('Found ' + RuntimePath);
    Result := False;
  end;
end;

procedure InitializeWizard;
begin
  // Decided once, so that the [Files] Check and the [Run] Check agree.
  VCRedistNeeded := True;
end;

/// Remove the autostart entry and stop a running core before uninstalling.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run', '{#MyAppName}');
    Exec('taskkill.exe', '/F /T /IM {#MyAppExeName}', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /T /IM xray.exe', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /T /IM xray-win7.exe', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /T /IM v2ray.exe', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /T /IM v2ray-win7.exe', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /T /IM tun2socks.exe', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
    Exec('netsh.exe', 'interface ipv4 reset', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
  end;
end;
