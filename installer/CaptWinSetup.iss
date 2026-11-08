; Build: ISCC.exe installer\CaptWinSetup.iss
; Output: dist\Canon-LBP1120-CAPT-Setup.exe

#define MyAppName "Canon LBP1120 CAPT"
#define MyAppVersion "1.1.22"
#define MyAppPublisher "sabir · Community CAPT port"
#define Payload "..\release\Canon-LBP1120-captwin-Win10-x64"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\CanonLBP1120Capt
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=Canon-LBP1120-CAPT-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\captwin.exe

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Обязательно в Setup (в release\tools часто нет — только pack-release кладёт zadig)
Source: "..\tools\zadig\zadig.exe"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "..\tools\wdi-simple.exe"; DestDir: "{app}\tools"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\third_party\ghostscript\*"; DestDir: "{app}\gs"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\libcapt\examples\data\example-1.pbm"; DestDir: "{app}\data"; Flags: ignoreversion
Source: "..\libcapt\examples\data\example-1.pbm"; DestDir: "{app}\installer"; DestName: "example-1.pbm"; Flags: ignoreversion
Source: "captwin_winusb.inf"; DestDir: "{app}\installer"
Source: "Install-CaptWin.ps1"; DestDir: "{app}\installer"
Source: "Install-Ghostscript.ps1"; DestDir: "{app}\installer"
Source: "Install-PrinterQueue.ps1"; DestDir: "{app}\installer"
Source: "Fix-PrintQueue.ps1"; DestDir: "{app}\installer"
Source: "Uninstall-CaptWin.ps1"; DestDir: "{app}\installer"
Source: "Install-WinUsb-Capt.ps1"; DestDir: "{app}\installer"
Source: "Setup-WinUsb.bat"; DestDir: "{app}\installer"
Source: "PostInstall-Wizard.ps1"; DestDir: "{app}\installer"
Source: "Setup-Guide.ru.txt"; DestDir: "{app}\installer"
Source: "CaptWin-Logging.ps1"; DestDir: "{app}\installer"
Source: "CaptWin-Server-Gui.ps1"; DestDir: "{app}"
Source: "Launch-CaptWinServer.vbs"; DestDir: "{app}"
Source: "CaptWin-Server.bat"; DestDir: "{app}"
Source: "CaptWin-Launcher.ps1"; DestDir: "{app}"
Source: "captwin.ico"; DestDir: "{app}"

[Tasks]
Name: "launchapp"; Description: "Открыть мастер настройки и сервер печати"; Flags: checkedonce

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\Install-CaptWin.ps1"" -InstallDir ""{app}"""; StatusMsg: "Ghostscript, очередь принтера, ярлыки..."; Flags: waituntilterminated

Filename: "{app}\CaptWin-Server.bat"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Tasks: launchapp; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\Uninstall-CaptWin.ps1"""; Flags: waituntilterminated

[Icons]
Name: "{autodesktop}\LBP-1120 — быстрый запуск"; Filename: "{app}\CaptWin-Server.bat"; WorkingDir: "{app}"; IconFilename: "{app}\captwin.ico"
Name: "{group}\Быстрый запуск сервера"; Filename: "{app}\CaptWin-Server.bat"; WorkingDir: "{app}"; IconFilename: "{app}\captwin.ico"
Name: "{group}\Тестовая страница"; Filename: "{app}\print-testpage.bat"; WorkingDir: "{app}"
Name: "{group}\Мастер настройки"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -File ""{app}\CaptWin-Launcher.ps1"" -InstallDir ""{app}"" -ForceWizard"; WorkingDir: "{app}"
Name: "{group}\Справка"; Filename: "{app}\README.ru.txt"
Name: "{group}\Краткая инструкция"; Filename: "{app}\installer\Setup-Guide.ru.txt"
Name: "{group}\Zadig (WinUSB)"; Filename: "{app}\tools\zadig.exe"; WorkingDir: "{app}\tools"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

[Messages]
russian.WelcomeLabel2=Установит программу, Ghostscript и очередь Windows для печати из браузера (Ctrl+P).%n%nНастройка WinUSB и проверка — при первом запуске ярлыка «LBP-1120 — быстрый запуск» на рабочем столе (мастер с шагами «Далее», Zadig уже в папке tools).%n%nПодключите Canon LBP-1120 по USB.
