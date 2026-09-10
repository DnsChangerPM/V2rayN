; IranLink — Inno Setup 6 script.
; Windows 7 SP1 is the floor (MinVersion=6.1sp1). Per-user install by default:
; no admin rights required. User data lives in %AppData%\IranLink (outside the
; install dir), so upgrades and uninstalls never touch profiles/settings/logs.
;
; Version stamping: CI passes /DAppVersion=<ver>; the #define below is only the
; local-build default (also updated by scripts/set_version.py).
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\\build\\windows\\x64\\runner\\Release"
#endif

#define MyAppName "IranLink"
#define MyAppPublisher "Parsa"
#define MyAppURL "https://github.com/DnsChangerPM/V2rayN"
#define MyAppExeName "IranLink.exe"

[Setup]
AppId={{[UUID_PLACEHOLDER_1]}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=IranLink-{#MyAppVersion}-Windows-{#MyAppArch}-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=110
MinVersion=6.1sp1
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=assets\installer.ico
DisableProgramGroupPage=yes
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  Version: TWindowsVersion;
  UCRTPath: String;
begin
  Result := True;
  GetWindowsVersionEx(Version);
  { On pre-10 Windows, the Flutter/MSVC build needs the Universal CRT. It ships
    with Windows 10+; on 7/8.1 it comes via Windows Update (KB2999226). }
  if Version.Major < 10 then
  begin
    UCRTPath := ExpandConstant('{sys}\ucrtbase.dll');
    if not FileExists(UCRTPath) then
    begin
      MsgBox(
        'Windows ' + IntToStr(Version.Major) + ' detected, but the Universal C Runtime ' +
        '(ucrtbase.dll) is missing.' + #13#10 + #13#10 +
        'IranLink needs the Universal CRT. Please install all important Windows ' +
        'Updates (KB2999226) and then run IranLink again. Setup will continue, ' +
        'but the application may fail to start until the update is installed.',
        mbInformation, MB_OK);
    end;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  { User data (%AppData%\IranLink) is intentionally preserved on uninstall. }
end;
