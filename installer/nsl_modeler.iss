; NSL Modeler — สคริปต์ตัวติดตั้ง Inno Setup (https://jrsoftware.org/isinfo.php)
; สร้างด้วย tool\build_installer.ps1 (ส่ง /DAppVersion=x.y.z มาให้) หรือเปิดไฟล์นี้ใน Inno Setup Compiler แล้วกด Compile
; ติดตั้งแบบผู้ใช้คนเดียว (ไม่ต้องใช้สิทธิ์ผู้ดูแล) ลงใน %LOCALAPPDATA%\Programs\NSL Modeler

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

#define AppName "NSL Modeler"
#define AppExe "nsl_modeler.exe"
#define ProgId "NSLModeler.Project"

[Setup]
; GUID ตายตัวของแอปนี้ — อย่าเปลี่ยน ไม่เช่นนั้นการอัปเกรดจะติดตั้งซ้อนกับรุ่นเดิม
AppId={{6E1B7C2A-4D5F-4B8E-9A31-5C0D7F2E8A14}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=NSL
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename=NSL-Modeler-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "thai"; MessagesFile: "compiler:Languages\Thai.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "assoc_nslm"; Description: "ผูกไฟล์ .nslm กับ NSL Modeler (ดับเบิลคลิกเพื่อเปิด) / Associate .nslm files with NSL Modeler"; GroupDescription: "{cm:AssocFileExtension,{#AppName},.nslm}"
Name: "assoc_erd"; Description: "ผูกไฟล์ .erd รุ่นเก่า / Associate legacy .erd files"; GroupDescription: "{cm:AssocFileExtension,{#AppName},.erd}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; ลงทะเบียนเฉพาะผู้ใช้ (HKA = HKCU เมื่อติดตั้งแบบผู้ใช้เดียว) ; uninsdeletekey ลบคีย์ของเราออกตอนถอนการติดตั้ง
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "NSL Modeler Project"; Flags: uninsdeletekey; Tasks: assoc_nslm assoc_erd
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"; Tasks: assoc_nslm assoc_erd
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc_nslm assoc_erd
Root: HKA; Subkey: "Software\Classes\.nslm"; ValueType: string; ValueData: "{#ProgId}"; Flags: uninsdeletevalue; Tasks: assoc_nslm
Root: HKA; Subkey: "Software\Classes\.erd"; ValueType: string; ValueData: "{#ProgId}"; Flags: uninsdeletevalue; Tasks: assoc_erd

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
