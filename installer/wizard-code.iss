const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;
  STILL_ACTIVE = 259;
  PI_IDLE = 0;
  PI_RUNNING = 1;
  PI_SUCCESS = 2;
  PI_FAILED = 3;
  PI_CANCELLED = 4;
  PI_CLEANUP_FAILED = 5;
  MAX_UI_LOG_BYTES = 196608;
  KILL_WAIT_TICKS = 30;

var
  PostInstallPage: TWizardPage;
  StatusLabel: TNewStaticText;
  DetailLabel: TNewStaticText;
  ProgressBar: TNewProgressBar;
  LogMemo: TNewMemo;
  UninstallLogMemo: TNewMemo;
  PostInstallState: Integer;
  LastLogCount: Integer;
  ExitWaitTicks: Integer;
  PostInstallTimer: UINT_PTR;
  PostInstallTimerCallback: NativeInt;
  PostInstallBusy: Boolean;
  DeferredExitTimer: UINT_PTR;
  DeferredExitCallback: NativeInt;
  DeferredExitCode: Integer;
  LogUiTruncated: Boolean;
  InstallLogPath: String;
  PidFilePath: String;
  CancelFilePath: String;
  ProgressFilePath: String;
  ExitCodeFilePath: String;
  ReplacementPage: TWizardPage;
  ReplacementBodyLabel: TNewStaticText;
  IsReplacementInstall: Boolean;
  PreviousInstallDir: String;
  PreviousDisplayVersion: String;

function OpenProcess(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwProcessId: DWORD): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function GetExitCodeProcess(hProcess: THandle; var lpExitCode: DWORD): BOOL;
  external 'GetExitCodeProcess@kernel32.dll stdcall';
function CloseHandle(hObject: THandle): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';
procedure ExitProcess(uExitCode: Cardinal);
  external 'ExitProcess@kernel32.dll stdcall';
function SetTimer(hWnd: HWND; nIDEvent: UINT_PTR; uElapse: UINT; lpTimerFunc: NativeInt): UINT_PTR;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd: HWND; nIDEvent: UINT_PTR): BOOL;
  external 'KillTimer@user32.dll stdcall';

procedure FinishPostInstall(Code: Integer); forward;
function RemoveInstallOnlyFolders: Boolean; forward;
procedure ApplyReplacementDirectory; forward;
procedure RefreshReplacementPage; forward;
procedure FlushLogTail; forward;
procedure RefreshProgressFromFile; forward;
procedure ApplyPostInstallButtons; forward;
procedure StopPostInstallTimer; forward;
procedure StopDeferredExitTimer; forward;
procedure KillPostInstall; forward;
procedure RequestDeferredExit(const Code: Integer); forward;
function IsPostInstallProcessRunning: Boolean; forward;
function TryReadExitCode(var Code: Integer): Boolean; forward;
function ExtractInstallerPayload: Boolean; forward;
procedure RemoveInstallerPayload; forward;
function GetPostInstallCommandLine(const IncludeCoordinationFiles: Boolean): String; forward;

function QuoteParam(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

function GetRuntimeSessionCommand: String;
var
  AppDir, PythonPath: String;
begin
  AppDir := ExpandConstant('{app}');
  PythonPath :=
    AppDir + '\python\python.exe';
  Result :=
    'set "{#MyHomeVar}=' + AppDir + '" && ' +
    'set "JAVA_HOME=' + AppDir + '\java" && ' +
    'set "SPARK_HOME=' + AppDir + '\spark" && ' +
    'set "HADOOP_HOME=' + AppDir + '\hadoop" && ' +
    'set "PYSPARK_PYTHON=' + PythonPath + '" && ' +
    'set "PYSPARK_DRIVER_PYTHON=' + PythonPath + '" && ' +
    'set "PATH=%PATH%;' +
      AppDir + '\java\bin;' +
      AppDir + '\spark\bin;' +
      AppDir + '\hadoop\bin;' +
      AppDir + '\python" && ';
end;

function GetPySparkShellParameters(Param: String): String;
begin
  Result :=
    '/K ' + GetRuntimeSessionCommand +
    'call "' + ExpandConstant('{app}\spark\bin\pyspark.cmd') + '"';
end;

function GetPySparkPythonParameters(Param: String): String;
begin
  Result :=
    '/K ' + GetRuntimeSessionCommand +
    '"' + ExpandConstant(
      '{app}\python\python.exe') + '"';
end;

procedure SetPostInstallPaths;
begin
  InstallLogPath := ExpandConstant('{app}\logs\install.log');
  PidFilePath := ExpandConstant('{app}\logs\post-install.pid');
  CancelFilePath := ExpandConstant('{app}\logs\post-install.cancel');
  ProgressFilePath := ExpandConstant('{app}\logs\post-install.progress');
  ExitCodeFilePath := ExpandConstant('{app}\logs\post-install.exitcode');
end;

procedure StopPostInstallTimer;
begin
  if PostInstallTimer <> 0 then
  begin
    KillTimer(0, PostInstallTimer);
    PostInstallTimer := 0;
  end;
end;

procedure StopDeferredExitTimer;
begin
  if DeferredExitTimer <> 0 then
  begin
    KillTimer(0, DeferredExitTimer);
    DeferredExitTimer := 0;
  end;
end;

procedure PumpWizard;
begin
  if WizardForm <> nil then
  begin
    WizardForm.Refresh;
    WizardForm.Update;
  end;
end;

procedure AddPostInstallLogLine(const S: String);
begin
  if Trim(S) = '' then
    Exit;
  Log(S);
  if LogMemo <> nil then
  begin
    LogMemo.Lines.Add(S);
    LogMemo.SelStart := Length(LogMemo.Text);
    LogMemo.SelLength := 0;
  end;
end;

procedure ApplyPostInstallButtons;
begin
  if (PostInstallPage = nil) or (WizardForm.CurPageID <> PostInstallPage.ID) then
    Exit;

  WizardForm.BackButton.Enabled := False;

  case PostInstallState of
    PI_SUCCESS:
      begin
        WizardForm.NextButton.Enabled := True;
        WizardForm.CancelButton.Enabled := False;
      end;
    PI_FAILED:
      begin
        WizardForm.NextButton.Enabled := False;
        WizardForm.CancelButton.Enabled := True;
        WizardForm.CancelButton.Caption := CustomMessage('CloseButton');
      end;
    PI_CANCELLED:
      begin
        WizardForm.NextButton.Enabled := False;
        WizardForm.CancelButton.Enabled := False;
      end;
    PI_CLEANUP_FAILED:
      begin
        WizardForm.NextButton.Enabled := False;
        WizardForm.CancelButton.Enabled := True;
        WizardForm.CancelButton.Caption := CustomMessage('CloseButton');
      end;
  else
    begin
      WizardForm.NextButton.Enabled := False;
      WizardForm.CancelButton.Enabled := True;
    end;
  end;
end;

procedure FlushLogTail;
var
  Lines: TArrayOfString;
  Count, I, Excess, Added, Size: Integer;
begin
  if LogMemo = nil then
    Exit;
  if (InstallLogPath = '') or (not FileExists(InstallLogPath)) then
    Exit;

  Size := 0;
  if FileSize(InstallLogPath, Size) and (Size > MAX_UI_LOG_BYTES) then
  begin
    if not LogUiTruncated then
    begin
      LogMemo.Lines.Add(CustomMessage('PostInstallLogTruncated'));
      LogUiTruncated := True;
    end;
    Exit;
  end;

  if not LoadStringsFromFile(InstallLogPath, Lines) then
    Exit;

  Count := GetArrayLength(Lines);
  if Count <= LastLogCount then
    Exit;

  Added := 0;
  for I := LastLogCount to Count - 1 do
  begin
    if Trim(Lines[I]) <> '' then
    begin
      if Added >= 80 then
      begin
        if not LogUiTruncated then
        begin
          LogMemo.Lines.Add(CustomMessage('PostInstallLogTruncated'));
          LogUiTruncated := True;
        end;
        Break;
      end;
      LogMemo.Lines.Add(Lines[I]);
      Inc(Added);
    end;
  end;
  LastLogCount := Count;

  Excess := LogMemo.Lines.Count - 400;
  if Excess > 0 then
  begin
    for I := 1 to Excess do
      LogMemo.Lines.Delete(0);
  end;

  LogMemo.SelStart := Length(LogMemo.Text);
  LogMemo.SelLength := 0;
end;

procedure RefreshProgressFromFile;
var
  Lines: TArrayOfString;
  Pct: Integer;
begin
  if (ProgressFilePath = '') or (not FileExists(ProgressFilePath)) then
    Exit;
  if not LoadStringsFromFile(ProgressFilePath, Lines) then
    Exit;
  if GetArrayLength(Lines) = 0 then
    Exit;

  Pct := StrToIntDef(Trim(Lines[0]), -1);
  if (Pct >= 0) and (Pct <= 100) then
    ProgressBar.Position := Pct;
  if (GetArrayLength(Lines) >= 2) and (Trim(Lines[1]) <> '') then
    StatusLabel.Caption := Trim(Lines[1]);
end;

function TryReadPid(var Pid: DWORD): Boolean;
var
  Lines: TArrayOfString;
begin
  Result := False;
  Pid := 0;
  if (PidFilePath = '') or (not FileExists(PidFilePath)) then
    Exit;
  if not LoadStringsFromFile(PidFilePath, Lines) then
    Exit;
  if GetArrayLength(Lines) = 0 then
    Exit;
  Pid := StrToIntDef(Trim(Lines[0]), 0);
  Result := Pid <> 0;
end;

function TryReadExitCode(var Code: Integer): Boolean;
var
  Lines: TArrayOfString;
begin
  Result := False;
  Code := -1;
  if (ExitCodeFilePath = '') or (not FileExists(ExitCodeFilePath)) then
    Exit;
  if not LoadStringsFromFile(ExitCodeFilePath, Lines) then
    Exit;
  if GetArrayLength(Lines) = 0 then
    Exit;
  Code := StrToIntDef(Trim(Lines[0]), -1);
  Result := Code >= 0;
end;

function IsPostInstallProcessRunning: Boolean;
var
  Pid: DWORD;
  Handle: THandle;
  ExitCode: DWORD;
begin
  Result := False;
  if not TryReadPid(Pid) then
    Exit;
  Handle := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if Handle = 0 then
    Exit;
  if GetExitCodeProcess(Handle, ExitCode) then
    Result := ExitCode = STILL_ACTIVE;
  CloseHandle(Handle);
end;

procedure KillInstallRuntimeProcesses;
var
  AppDir, RootLiteral, Command, Params: String;
  ResultCode: Integer;
begin
  AppDir := ExpandConstant('{app}');
  if Trim(AppDir) = '' then
    Exit;

  RootLiteral := AppDir;
  StringChangeEx(RootLiteral, '''', '''''', True);

  Command :=
    'Get-Process | ForEach-Object { ' +
      'try { ' +
        '$p = $_.Path; ' +
        'if ($p -and $p.StartsWith(''' + RootLiteral +
          ''', [StringComparison]::OrdinalIgnoreCase)) { ' +
          'Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue ' +
        '} ' +
      '} catch {} ' +
    '}';

  Params :=
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ' +
    QuoteParam(Command);
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, '', SW_HIDE, ewNoWait, ResultCode);
end;

procedure KillPostInstall;
var
  Pid: DWORD;
  ResultCode: Integer;
  WaitTicks: Integer;
begin
  if CancelFilePath <> '' then
    SaveStringToFile(CancelFilePath, '1', False);

  if TryReadPid(Pid) then
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/PID ' + IntToStr(Pid) + ' /T /F',
      '', SW_HIDE, ewNoWait, ResultCode);

  KillInstallRuntimeProcesses;

  WaitTicks := 0;
  while (WaitTicks < KILL_WAIT_TICKS) and IsPostInstallProcessRunning do
  begin
    Sleep(100);
    PumpWizard;
    Inc(WaitTicks);
  end;

  WaitTicks := 0;
  while WaitTicks < 10 do
  begin
    Sleep(100);
    PumpWizard;
    Inc(WaitTicks);
  end;
end;

procedure DeferredExitProc(Arg1: HWND; Arg2: UINT; Arg3: UINT_PTR; Arg4: DWORD);
begin
  StopDeferredExitTimer;
  StopPostInstallTimer;
  KillPostInstall;
  RemoveInstallerPayload;
  if WizardForm <> nil then
    WizardForm.Hide;
  ExitProcess(DeferredExitCode);
end;

procedure RequestDeferredExit(const Code: Integer);
begin
  DeferredExitCode := Code;
  StopPostInstallTimer;
  if WizardForm <> nil then
  begin
    WizardForm.CancelButton.Enabled := False;
    WizardForm.NextButton.Enabled := False;
  end;
  if DeferredExitCallback = 0 then
    DeferredExitCallback := CreateCallback(@DeferredExitProc);
  if DeferredExitTimer = 0 then
    DeferredExitTimer := SetTimer(0, 0, 100, DeferredExitCallback);
  if DeferredExitTimer = 0 then
    DeferredExitProc(0, 0, 0, 0)
  else if WizardForm <> nil then
    WizardForm.Enabled := False;
end;

procedure FinishPostInstall(Code: Integer);
begin
  StopPostInstallTimer;
  RemoveInstallerPayload;
  FlushLogTail;

  if Code = 0 then
  begin
    PostInstallState := PI_SUCCESS;
    ProgressBar.Position := 100;
    if ProgressBar.State <> npbsNormal then
      ProgressBar.State := npbsNormal;
    StatusLabel.Caption := CustomMessage('PostInstallSuccess');
    StatusLabel.Font.Color := $002E7D32;
    DetailLabel.Caption := CustomMessage('PostInstallSuccessDetail');
    AddPostInstallLogLine(CustomMessage('PostInstallSuccessDetail'));
    ApplyPostInstallButtons;
  end
  else
  begin
    PostInstallState := PI_FAILED;
    ProgressBar.State := npbsError;
    StatusLabel.Caption := CustomMessage('PostInstallFailed');
    StatusLabel.Font.Color := $000000C8;
    DetailLabel.Caption := CustomMessage('PostInstallFailedDetail');
    ApplyPostInstallButtons;
  end;

  WizardForm.Update;
end;

procedure PollPostInstall;
var
  Code: Integer;
  Running, HaveCode: Boolean;
begin
  if (PostInstallState <> PI_RUNNING) or PostInstallBusy then
    Exit;

  PostInstallBusy := True;
  try
    FlushLogTail;
    RefreshProgressFromFile;
    ApplyPostInstallButtons;

    Running := IsPostInstallProcessRunning;
    HaveCode := TryReadExitCode(Code);

    if HaveCode and (not Running) then
      FinishPostInstall(Code)
    else if HaveCode and Running then
    begin
      Inc(ExitWaitTicks);
      if ((Code = 0) and (ExitWaitTicks >= 25)) or
         ((Code <> 0) and (ExitWaitTicks >= 10)) then
      begin
        KillPostInstall;
        FinishPostInstall(Code);
      end;
    end
    else if Running then
      ExitWaitTicks := 0
    else
    begin
      Inc(ExitWaitTicks);
      if FileExists(PidFilePath) then
      begin
        if ExitWaitTicks >= 25 then
          FinishPostInstall(1);
      end
      else if ExitWaitTicks >= 40 then
        FinishPostInstall(1);
    end;
  finally
    PostInstallBusy := False;
  end;
end;

procedure PostInstallTimerProc(Arg1: HWND; Arg2: UINT; Arg3: UINT_PTR; Arg4: DWORD);
begin
  PollPostInstall;
end;

procedure StartPostInstallTimer;
begin
  StopPostInstallTimer;
  if PostInstallTimerCallback = 0 then
    PostInstallTimerCallback := CreateCallback(@PostInstallTimerProc);
  PostInstallTimer := SetTimer(0, 0, 200, PostInstallTimerCallback);
end;

function GetPostInstallCommandLine(const IncludeCoordinationFiles: Boolean): String;
begin
  Result :=
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' +
    QuoteParam(ExpandConstant('{tmp}\post-install.ps1')) +
    ' -InstallRoot ' + QuoteParam(ExpandConstant('{app}')) +
    ' -ConfigPath ' + QuoteParam(ExpandConstant('{tmp}\versions.json')) +
    ' -UiLanguage ' + QuoteParam(ActiveLanguage);
  if IncludeCoordinationFiles then
    Result := Result +
      ' -PidFile ' + QuoteParam(PidFilePath) +
      ' -CancelFile ' + QuoteParam(CancelFilePath) +
      ' -ProgressFile ' + QuoteParam(ProgressFilePath) +
      ' -ExitCodeFile ' + QuoteParam(ExitCodeFilePath);
end;

function ExtractInstallerPayload: Boolean;
begin
  Result := False;
  try
    ExtractTemporaryFile('post-install.ps1');
    ExtractTemporaryFile('common.ps1');
    ExtractTemporaryFile('setup-env.ps1');
    ExtractTemporaryFile('verify-install.ps1');
    ExtractTemporaryFile('versions.json');
    Result :=
      FileExists(ExpandConstant('{tmp}\post-install.ps1')) and
      FileExists(ExpandConstant('{tmp}\common.ps1')) and
      FileExists(ExpandConstant('{tmp}\setup-env.ps1')) and
      FileExists(ExpandConstant('{tmp}\verify-install.ps1')) and
      FileExists(ExpandConstant('{tmp}\versions.json'));
  except
    Log('ERROR: no se pudo extraer el payload de post-instalacion a {tmp}');
    Result := False;
  end;
end;

procedure RemoveInstallerPayload;
begin
  DeleteFile(ExpandConstant('{tmp}\post-install.ps1'));
  DeleteFile(ExpandConstant('{tmp}\common.ps1'));
  DeleteFile(ExpandConstant('{tmp}\setup-env.ps1'));
  DeleteFile(ExpandConstant('{tmp}\verify-install.ps1'));
  DeleteFile(ExpandConstant('{tmp}\versions.json'));
end;

procedure StartPostInstallAsync;
var
  PowershellPath, Params: String;
  ResultCode: Integer;
begin
  if PostInstallState <> PI_IDLE then
    Exit;

  SetPostInstallPaths;
  ForceDirectories(ExtractFileDir(InstallLogPath));
  DeleteFile(PidFilePath);
  DeleteFile(CancelFilePath);
  DeleteFile(ProgressFilePath);
  DeleteFile(ExitCodeFilePath);

  LastLogCount := 0;
  ExitWaitTicks := 0;
  LogUiTruncated := False;
  ProgressBar.Position := 2;
  ProgressBar.State := npbsNormal;
  StatusLabel.Font.Color := clWindowText;
  StatusLabel.Caption := CustomMessage('PostInstallWaiting');
  DetailLabel.Caption := CustomMessage('PostInstallDetail');
  if LogMemo <> nil then
    LogMemo.Lines.Clear;
  AddPostInstallLogLine(CustomMessage('PostInstallWaiting'));

  if not ExtractInstallerPayload then
  begin
    AddPostInstallLogLine(CustomMessage('PostInstallStartFailed'));
    FinishPostInstall(1);
    Exit;
  end;

  Params := GetPostInstallCommandLine(True);

  PowershellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  PostInstallState := PI_RUNNING;
  ApplyPostInstallButtons;

  if not Exec(PowershellPath, Params, ExpandConstant('{app}'), SW_HIDE, ewNoWait, ResultCode) then
  begin
    AddPostInstallLogLine(CustomMessage('PostInstallStartFailed'));
    FinishPostInstall(1);
    Exit;
  end;

  StartPostInstallTimer;
  if PostInstallTimer = 0 then
  begin
    AddPostInstallLogLine(CustomMessage('PostInstallStartFailed'));
    FinishPostInstall(1);
  end;
end;

procedure SilentPostInstallLog(const S: String; const Error, FirstLine: Boolean);
begin
  if Trim(S) = '' then
    Exit;
  if Error then
    Log('ERROR: ' + S)
  else
    Log(S);
end;

procedure RunPostInstallBlocking;
var
  PowershellPath, Params: String;
  ResultCode: Integer;
begin
  if not ExtractInstallerPayload then
    RaiseException(CustomMessage('PostInstallStartFailed'));

  ResultCode := 1;
  try
    Params := GetPostInstallCommandLine(False);
    PowershellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    if not ExecAndLogOutput(PowershellPath, Params, ExpandConstant('{app}'), SW_HIDE,
        ewWaitUntilTerminated, ResultCode, @SilentPostInstallLog) then
      RaiseException(CustomMessage('PostInstallStartFailed'));
  finally
    RemoveInstallerPayload;
  end;
  if ResultCode = 1602 then
    RaiseException(CustomMessage('CancelCleanup'));
  if ResultCode <> 0 then
    RaiseException(
      CustomMessage('PostInstallFailed') + ' (code ' + IntToStr(ResultCode) + ').');
  if not RemoveInstallOnlyFolders then
    RaiseException(CustomMessage('PostInstallCleanupFailed'));
end;

function RemoveInstallOnlyFolder(const Folder: String): Boolean;
begin
  Result := True;
  if not DirExists(Folder) then
    Exit;

  if not DelTree(Folder, True, True, True) then
  begin
    Log('ERROR: no se pudo eliminar el directorio temporal: ' + Folder);
    Result := False;
  end
  else if DirExists(Folder) then
  begin
    Log('ERROR: el directorio temporal sigue existiendo: ' + Folder);
    Result := False;
  end;
end;

function RemoveInstallOnlyFile(const FileName: String): Boolean;
begin
  Result := True;
  if not FileExists(FileName) then
    Exit;

  if not DeleteFile(FileName) then
  begin
    Log('ERROR: no se pudo eliminar el archivo temporal: ' + FileName);
    Result := False;
  end
  else if FileExists(FileName) then
  begin
    Log('ERROR: el archivo temporal sigue existiendo: ' + FileName);
    Result := False;
  end;
end;

function RemoveInstallOnlyFolders: Boolean;
begin
  // scripts/ y config/ bajo el directorio de instalacion: residuos anteriores a D-016.
  Result := True;
  if not RemoveInstallOnlyFolder(ExpandConstant('{app}\installer')) then
    Result := False;
  if not RemoveInstallOnlyFolder(ExpandConstant('{app}\scripts')) then
    Result := False;
  if not RemoveInstallOnlyFolder(ExpandConstant('{app}\config')) then
    Result := False;
  if not RemoveInstallOnlyFolder(ExpandConstant('{app}\bin')) then
    Result := False;
  if not RemoveInstallOnlyFile(ExpandConstant('{app}\setup.ico')) then
    Result := False;

  if Result and not RemoveInstallOnlyFolder(ExpandConstant('{app}\logs')) then
    Result := False;
end;

function NormalizePathEntry(const Value: String): String;
var
  S: String;
begin
  S := Trim(Value);
  StringChangeEx(S, '/', '\', True);
  while (Length(S) > 1) and (S[Length(S)] = '\') do
    Delete(S, Length(S), 1);
  Result := LowerCase(S);
end;

function IsPathUnderApp(const Entry, AppDir: String): Boolean;
var
  N, A: String;
begin
  N := NormalizePathEntry(Entry);
  A := NormalizePathEntry(AppDir);
  Result := (N = A) or (Copy(N, 1, Length(A) + 1) = A + '\');
end;

function IsKnownExpandablePath(const Entry: String): Boolean;
var
  N: String;
begin
  N := NormalizePathEntry(Entry);
  Result :=
    (N = NormalizePathEntry('%JAVA_HOME%\bin')) or
    (N = NormalizePathEntry('%SPARK_HOME%\bin')) or
    (N = NormalizePathEntry('%HADOOP_HOME%\bin')) or
    (N = NormalizePathEntry('%{#MyHomeVar}%\python'));
end;

function ShouldKeepPathEntry(const Entry, AppDir: String): Boolean;
begin
  if Trim(Entry) = '' then
  begin
    Result := False;
    Exit;
  end;
  Result := not (IsKnownExpandablePath(Entry) or IsPathUnderApp(Entry, AppDir));
end;

procedure AddUninstallLogLine(const S: String);
begin
  if Trim(S) = '' then
    Exit;

  Log(S);
  if UninstallLogMemo <> nil then
  begin
    UninstallLogMemo.Lines.Add(S);
    UninstallLogMemo.SelStart := Length(UninstallLogMemo.Text);
    UninstallLogMemo.SelLength := 0;
    UninstallLogMemo.Update;
  end;
end;

procedure DeleteUserEnv(const Name: String);
begin
  AddUninstallLogLine('Eliminando variable de entorno: ' + Name);
  RegDeleteValue(HKCU, 'Environment', Name);
end;

procedure CleanupPythonDiscoveryKey(const Company: String);
var
  KernelDir: String;
begin
  if RegKeyExists(HKCU, 'Software\Python\' + Company) then
  begin
    AddUninstallLogLine('Eliminando registro PEP 514: Software\Python\' + Company);
    if not RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Python\' + Company) then
      AddUninstallLogLine('Aviso: no se pudo eliminar Software\Python\' + Company);
  end;

  KernelDir :=
    ExpandConstant('{userappdata}') + '\jupyter\kernels\' + LowerCase(Company);
  if DirExists(KernelDir) then
  begin
    AddUninstallLogLine('Eliminando kernelspec de usuario: ' + KernelDir);
    if not DelTree(KernelDir, True, True, True) then
      AddUninstallLogLine('Aviso: no se pudo eliminar el kernelspec de usuario.');
  end;
end;

procedure CleanupPythonDiscovery;
begin
  CleanupPythonDiscoveryKey('{#MyAppName}');
  if CompareText('{#MyAppName}', '{#MyLegacyAppName}') <> 0 then
    CleanupPythonDiscoveryKey('{#MyLegacyAppName}');
end;

procedure CleanupUserPath(const AppDir: String);
var
  Current, Entry, NewPath: String;
  P: Integer;
  Changed: Boolean;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Current) then
    Exit;

  NewPath := '';
  Changed := False;
  while Current <> '' do
  begin
    P := Pos(';', Current);
    if P = 0 then
    begin
      Entry := Current;
      Current := '';
    end
    else
    begin
      Entry := Copy(Current, 1, P - 1);
      Delete(Current, 1, P);
    end;

    if ShouldKeepPathEntry(Entry, AppDir) then
    begin
      if NewPath <> '' then
        NewPath := NewPath + ';';
      NewPath := NewPath + Trim(Entry);
    end
    else
    begin
      Changed := True;
      AddUninstallLogLine('Eliminando entrada de PATH: ' + Trim(Entry));
    end;
  end;

  if Changed then
  begin
    if NewPath = '' then
      RegDeleteValue(HKCU, 'Environment', 'Path')
    else
      RegWriteExpandStringValue(HKCU, 'Environment', 'Path', NewPath);
  end;
end;

procedure RunUninstallCleanup;
var
  AppDir, PythonDir: String;
begin
  AppDir := ExpandConstant('{app}');
  AddUninstallLogLine('Iniciando la limpieza de {#MyAppName}...');
  AddUninstallLogLine('Directorio de instalacion: ' + AppDir);

  DeleteUserEnv('{#MyHomeVar}');
  DeleteUserEnv('JAVA_HOME');
  DeleteUserEnv('SPARK_HOME');
  DeleteUserEnv('HADOOP_HOME');
  DeleteUserEnv('PYSPARK_PYTHON');
  DeleteUserEnv('PYSPARK_DRIVER_PYTHON');
  CleanupUserPath(AppDir);
  CleanupPythonDiscovery;

  PythonDir := AppDir + '\python';
  if DirExists(PythonDir) then
  begin
    AddUninstallLogLine('Eliminando runtime Python privado: ' + PythonDir);
    if not DelTree(PythonDir, True, True, True) then
      AddUninstallLogLine(
        'Aviso: no se pudo eliminar por completo python; se reintentara al final.');
  end
  else
    AddUninstallLogLine('El runtime Python privado ya no existe.');

  AddUninstallLogLine(
    'Variables y runtime limpiados. Eliminando ahora el resto del contenido...');
end;

function GetUninstallRegSubkey: String;
begin
  Result :=
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{' +
    '{#MyAppGuid}' + '}_is1';
end;

function SameInstallPath(const A, B: String): Boolean;
begin
  Result := NormalizePathEntry(A) = NormalizePathEntry(B);
end;

function TryReadUninstallRecord(const RootKey: Integer; var InstallDir, DisplayVersion: String): Boolean;
var
  Subkey, AppPath, Location: String;
begin
  Result := False;
  InstallDir := '';
  DisplayVersion := '';
  Subkey := GetUninstallRegSubkey;
  if not RegKeyExists(RootKey, Subkey) then
    Exit;

  if not RegQueryStringValue(RootKey, Subkey, 'Inno Setup: App Path', AppPath) then
    AppPath := '';
  if not RegQueryStringValue(RootKey, Subkey, 'InstallLocation', Location) then
    Location := '';
  if not RegQueryStringValue(RootKey, Subkey, 'DisplayVersion', DisplayVersion) then
    DisplayVersion := '';

  if Trim(AppPath) <> '' then
    InstallDir := RemoveBackslashUnlessRoot(Trim(AppPath))
  else if Trim(Location) <> '' then
    InstallDir := RemoveBackslashUnlessRoot(Trim(Location));

  Result := True;
end;

function TryReadUserHomeHint(var InstallDir: String): Boolean;
var
  Home: String;
begin
  Result := False;
  InstallDir := '';
  if not RegQueryStringValue(HKCU, 'Environment', '{#MyHomeVar}', Home) then
    Home := '';
  Home := RemoveBackslashUnlessRoot(Trim(Home));
  if (Home <> '') and DirExists(Home) then
  begin
    InstallDir := Home;
    Result := True;
  end;
end;

procedure ApplyReplacementDirectory;
var
  Requested: String;
begin
  if not IsReplacementInstall then
    Exit;
  if PreviousInstallDir = '' then
    Exit;
  Requested := ExpandConstant('{param:DIR}');
  if (Requested <> '') and (not SameInstallPath(Requested, PreviousInstallDir)) then
    Log('Ignoring /DIR=' + Requested + '; replacing at ' + PreviousInstallDir);
  if WizardForm <> nil then
    WizardForm.DirEdit.Text := PreviousInstallDir;
end;

procedure RefreshReplacementPage;
var
  VersionLabel, LocationLabel: String;
begin
  if ReplacementBodyLabel = nil then
    Exit;

  VersionLabel := PreviousDisplayVersion;
  if Trim(VersionLabel) = '' then
    VersionLabel := CustomMessage('ReplaceExistingUnknownVersion');

  LocationLabel := PreviousInstallDir;
  if Trim(LocationLabel) = '' then
    LocationLabel := CustomMessage('ReplaceMissingLocation');

  ReplacementBodyLabel.Caption := FmtMessage(
    CustomMessage('ReplaceExistingBody'), [VersionLabel, LocationLabel, '{#MyAppVersion}']);
end;

function EvaluateExistingInstallation: Boolean;
var
  SameDir, OtherDir, SameVersion, OtherVersion, HintDir: String;
  SameRoot, OtherRoot: Integer;
  SameFound, OtherFound: Boolean;
  PrivilegeLabel: String;
begin
  Result := True;
  IsReplacementInstall := False;
  PreviousInstallDir := '';
  PreviousDisplayVersion := '';

  if IsAdminInstallMode then
  begin
    SameRoot := HKLM;
    OtherRoot := HKCU;
    PrivilegeLabel := CustomMessage('ReplacePrivilegeCurrentUser');
  end
  else
  begin
    SameRoot := HKCU;
    OtherRoot := HKLM;
    PrivilegeLabel := CustomMessage('ReplacePrivilegeAllUsers');
  end;

  OtherFound := TryReadUninstallRecord(OtherRoot, OtherDir, OtherVersion);
  SameFound := TryReadUninstallRecord(SameRoot, SameDir, SameVersion);

  if OtherFound then
  begin
    if Trim(OtherDir) = '' then
      OtherDir := CustomMessage('ReplaceMissingLocation');
    Log('ERROR: existing {#MyAppName} in the other privilege mode at ' + OtherDir);
    MsgBox(
      FmtMessage(CustomMessage('ReplacePrivilegeMismatch'), [PrivilegeLabel, OtherDir]),
      mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if SameFound then
  begin
    PreviousInstallDir := SameDir;
    PreviousDisplayVersion := SameVersion;
    if PreviousInstallDir = '' then
      TryReadUserHomeHint(PreviousInstallDir);
    if PreviousInstallDir = '' then
    begin
      Log('ERROR: existing uninstall record without a usable directory');
      MsgBox(CustomMessage('ReplaceUnknownDir'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    IsReplacementInstall := True;
    Log('Existing {#MyAppName} detected at ' + PreviousInstallDir +
      ' version ' + PreviousDisplayVersion);
    Exit;
  end;

  if TryReadUserHomeHint(HintDir) then
  begin
    IsReplacementInstall := True;
    PreviousInstallDir := HintDir;
    Log('Existing install home used as replacement target: ' + HintDir);
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := False;
  if not FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) then
  begin
    MsgBox(CustomMessage('NeedPowerShell'), mbError, MB_OK);
    Exit;
  end;
  Result := EvaluateExistingInstallation;
end;

procedure InitializeUninstallProgressForm;
begin
  UninstallLogMemo := nil;
  if UninstallSilent then
    Exit;

  UninstallProgressForm.PageNameLabel.Caption := CustomMessage('UninstallCaption');
  UninstallProgressForm.PageDescriptionLabel.Caption := CustomMessage('UninstallDescription');
  UninstallProgressForm.StatusLabel.Visible := False;
  UninstallProgressForm.ProgressBar.Visible := False;
  UninstallProgressForm.BeveledLabel.Visible := False;
  UninstallProgressForm.InnerNotebook.ActivePage :=
    UninstallProgressForm.InstallingPage;

  UninstallLogMemo := TNewMemo.Create(UninstallProgressForm.InstallingPage);
  UninstallLogMemo.Parent := UninstallProgressForm.InstallingPage;
  UninstallLogMemo.Align := alClient;
  UninstallLogMemo.ReadOnly := True;
  UninstallLogMemo.ScrollBars := ssBoth;
  UninstallLogMemo.WordWrap := False;
  UninstallLogMemo.BringToFront;
  UninstallLogMemo.Lines.Add(CustomMessage('UninstallDescription'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RunUninstallCleanup;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardSilent then
    RunPostInstallBlocking;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  ApplyReplacementDirectory;
  if (ReplacementPage <> nil) and (CurPageID = ReplacementPage.ID) then
    RefreshReplacementPage;
  if (PostInstallPage <> nil) and (CurPageID = PostInstallPage.ID) then
  begin
    if PostInstallState = PI_IDLE then
      StartPostInstallAsync
    else
      ApplyPostInstallButtons;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  ApplyReplacementDirectory;
  if IsReplacementInstall and (PageID = wpSelectDir) then
    Result := True
  else if (ReplacementPage <> nil) and (PageID = ReplacementPage.ID) and
    (not IsReplacementInstall) then
    Result := True;
end;

function BackButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (PostInstallPage <> nil) and (CurPageID = PostInstallPage.ID) then
    Result := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  ApplyReplacementDirectory;

  if IsReplacementInstall and (CurPageID = wpSelectDir) then
  begin
    if not SameInstallPath(WizardDirValue, PreviousInstallDir) then
    begin
      MsgBox(
        FmtMessage(CustomMessage('ReplaceDirLocked'), [PreviousInstallDir]),
        mbError, MB_OK);
      WizardForm.DirEdit.Text := PreviousInstallDir;
      Result := False;
      Exit;
    end;
  end;

  if (PostInstallPage <> nil) and (CurPageID = PostInstallPage.ID) then
  begin
    Result := PostInstallState = PI_SUCCESS;
    if Result then
    begin
      FlushLogTail;
      if not RemoveInstallOnlyFolders then
      begin
        PostInstallState := PI_CLEANUP_FAILED;
        ProgressBar.State := npbsError;
        StatusLabel.Caption := CustomMessage('PostInstallCleanupFailed');
        StatusLabel.Font.Color := $000000C8;
        DetailLabel.Caption := CustomMessage('PostInstallCleanupFailedDetail');
        ApplyPostInstallButtons;
        WizardForm.Update;
        Result := False;
      end;
    end;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
var
  KeepFiles: Boolean;
begin
  if (PostInstallPage = nil) or (CurPageID <> PostInstallPage.ID) then
    Exit;

  if PostInstallState = PI_SUCCESS then
  begin
    Cancel := False;
    Confirm := False;
    Exit;
  end;

  if PostInstallState = PI_RUNNING then
  begin
    Confirm := False;
    if MsgBox(CustomMessage('ConfirmCancelSetup'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
    begin
      Cancel := False;
      Exit;
    end;

    StatusLabel.Caption := CustomMessage('CancellingSetup');
    WizardForm.CancelButton.Enabled := False;
    PumpWizard;
    StopPostInstallTimer;
    AddPostInstallLogLine(CustomMessage('CancelCleanup'));
    KillPostInstall;
    RemoveInstallerPayload;
    PostInstallState := PI_CANCELLED;
    Cancel := True;
    Exit;
  end;

  if PostInstallState = PI_FAILED then
  begin
    Confirm := False;
    KeepFiles :=
      MsgBox(CustomMessage('FailedKeepFiles'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES;
    if KeepFiles then
    begin
      Cancel := False;
      RequestDeferredExit(1);
      Exit;
    end;
    KillPostInstall;
    Cancel := True;
    Exit;
  end;

  if PostInstallState = PI_CLEANUP_FAILED then
  begin
    Confirm := False;
    Cancel := False;
    RequestDeferredExit(1);
    Exit;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := CustomMessage('ReadyMemoIntro') + NewLine + NewLine;
  if IsReplacementInstall then
    Result := Result + CustomMessage('ReplaceReadyNote') + NewLine + NewLine;
  Result := Result + MemoDirInfo + NewLine + NewLine;
  Result := Result + CustomMessage('ReadyMemoComponents') + NewLine;
  Result := Result + Space + 'Java {#JavaMajorVersion}' + NewLine;
  Result := Result + Space + 'Apache Spark {#SparkVersion}' + NewLine;
  Result := Result + Space + 'PySpark {#PySparkVersion} / Python {#PythonVersion}' + NewLine;
  Result := Result + Space + 'Hadoop winutils {#HadoopWinutilsVersion}' + NewLine + NewLine;
  if Trim(MemoTasksInfo) <> '' then
    Result := Result + MemoTasksInfo + NewLine + NewLine;
  Result := Result + CustomMessage('ReadyMemoTime');
end;

procedure DeinitializeSetup;
begin
  StopPostInstallTimer;
  StopDeferredExitTimer;
  if PostInstallState = PI_RUNNING then
    KillPostInstall;
  RemoveInstallerPayload;
end;

procedure InitializeWizard;
var
  MemoTop: Integer;
begin
  PostInstallState := PI_IDLE;
  LastLogCount := 0;
  ExitWaitTicks := 0;
  PostInstallTimer := 0;
  PostInstallTimerCallback := 0;
  PostInstallBusy := False;
  DeferredExitTimer := 0;
  DeferredExitCallback := 0;
  DeferredExitCode := 1;
  LogUiTruncated := False;

  if IsReplacementInstall then
  begin
    if PreviousInstallDir = '' then
      PreviousInstallDir := RemoveBackslashUnlessRoot(WizardForm.PrevAppDir);
    if PreviousInstallDir = '' then
      TryReadUserHomeHint(PreviousInstallDir);
  end;

  ReplacementPage := CreateCustomPage(
    wpLicense,
    CustomMessage('ReplaceExistingCaption'),
    CustomMessage('ReplaceExistingDescription'));

  ReplacementBodyLabel := TNewStaticText.Create(ReplacementPage);
  ReplacementBodyLabel.Parent := ReplacementPage.Surface;
  ReplacementBodyLabel.AutoSize := False;
  ReplacementBodyLabel.Width := ReplacementPage.SurfaceWidth;
  ReplacementBodyLabel.Height := ReplacementPage.SurfaceHeight;
  ReplacementBodyLabel.Anchors := [akLeft, akTop, akRight, akBottom];
  ReplacementBodyLabel.WordWrap := True;
  RefreshReplacementPage;
  ApplyReplacementDirectory;

  PostInstallPage := CreateCustomPage(
    wpInstalling,
    CustomMessage('PostInstallCaption'),
    CustomMessage('PostInstallDescription'));

  StatusLabel := TNewStaticText.Create(PostInstallPage);
  StatusLabel.Parent := PostInstallPage.Surface;
  StatusLabel.AutoSize := False;
  StatusLabel.Width := PostInstallPage.SurfaceWidth;
  StatusLabel.Height := ScaleY(20);
  StatusLabel.Anchors := [akLeft, akTop, akRight];
  StatusLabel.Caption := CustomMessage('PostInstallWaiting');
  StatusLabel.Font.Style := [fsBold];

  DetailLabel := TNewStaticText.Create(PostInstallPage);
  DetailLabel.Parent := PostInstallPage.Surface;
  DetailLabel.AutoSize := False;
  DetailLabel.Top := StatusLabel.Top + StatusLabel.Height + ScaleY(2);
  DetailLabel.Width := PostInstallPage.SurfaceWidth;
  DetailLabel.Height := ScaleY(32);
  DetailLabel.Anchors := [akLeft, akTop, akRight];
  DetailLabel.WordWrap := True;
  DetailLabel.Caption := CustomMessage('PostInstallDetail');
  DetailLabel.Font.Color := clGray;

  ProgressBar := TNewProgressBar.Create(PostInstallPage);
  ProgressBar.Parent := PostInstallPage.Surface;
  ProgressBar.Top := DetailLabel.Top + DetailLabel.Height + ScaleY(6);
  ProgressBar.Width := PostInstallPage.SurfaceWidth;
  ProgressBar.Height := ScaleY(16);
  ProgressBar.Anchors := [akLeft, akTop, akRight];
  ProgressBar.Min := 0;
  ProgressBar.Max := 100;
  ProgressBar.Position := 0;

  MemoTop := ProgressBar.Top + ProgressBar.Height + ScaleY(10);
  LogMemo := TNewMemo.Create(PostInstallPage);
  LogMemo.Parent := PostInstallPage.Surface;
  LogMemo.SetBounds(0, MemoTop, PostInstallPage.SurfaceWidth,
    PostInstallPage.SurfaceHeight - MemoTop);
  LogMemo.Anchors := [akLeft, akTop, akRight, akBottom];
  LogMemo.ReadOnly := True;
  LogMemo.ScrollBars := ssBoth;
  LogMemo.WordWrap := False;
  LogMemo.Font.Name := 'Consolas';
  LogMemo.Font.Size := 8;
end;
