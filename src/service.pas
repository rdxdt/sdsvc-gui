unit service;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Process, fpjson, jsonparser;

type
  TServiceStatus = (ssStopped, ssStarted, ssFailed);

type
  TServiceFilterType = (ftUser, ftSystem, ftAll);

type
  // which systemd manager a unit belongs to
  TServiceScope = (scSystem, scUser);

type
  TServiceFilterState = (fsInactive, fsRunning, fsFailed, fsAll);

function ScopeSwitch(AScope : TServiceScope) : String;
function ScopeToStr(AScope : TServiceScope) : String;

type
  TService = class(TObject)
    private
      FUnitName : String;
      FScope : TServiceScope;
      FDescription : String;
      FLoaded : Boolean;
      FUnitFileState : String;
      FActive : Boolean;
      FStatus : TServiceStatus;

      function RunSystemctl(const AAction : String) : Boolean;
    public
      property UnitName : String read FUnitName;
      property Scope : TServiceScope read FScope;
      property Description : String read FDescription;
      property Loaded : Boolean read FLoaded;
      // enablement state from "systemctl list-unit-files" (enabled, disabled,
      // static, masked, indirect, ...). Empty when it could not be determined.
      property UnitFileState : String read FUnitFileState;
      function IsEnabled : Boolean;
      function CanEnable : Boolean;
      property Active : Boolean read FActive;
      property Status : TServiceStatus read FStatus;

      function Start : Boolean;
      function Stop : Boolean;
      function Restart : Boolean;
      function Enable : Boolean;
      function Disable :Boolean;

  end;

type
  TServiceList = class(TObject)
    private
      FItems : TFPList;
      FServiceFilterType : TServiceFilterType;
      FServiceFilterState : TServiceFilterState;


      function GetCount : Integer;
      function GetItem(AIndex : Integer) : TService;
      procedure ReadProcessOutput(AScope : TServiceScope; AOutput : TMemoryStream);
      procedure ReadUnitFileStates(AScope : TServiceScope; AStates : TStringList);
      function ParseScope(AScope : TServiceScope) : Boolean;
      procedure AddUnloadedUnits(AScope : TServiceScope; AStates, ASeen : TStringList);
      function DaemonReloadScope(AScope : TServiceScope) : Boolean;
    public
      constructor Create;
      destructor Destroy; override;

      procedure Clear;
      function Parse : Boolean;
      function DaemonReload : Boolean;

      property Count : Integer read GetCount;
      property Items[AIndex : Integer] : TService read GetItem; default;
      property ServiceFilterType : TServiceFilterType read FServiceFilterType write FServiceFilterType;
      property ServiceFilterState : TServiceFilterState read FServiceFilterState write FServiceFilterState;
  end;


implementation

function ScopeSwitch(AScope : TServiceScope) : String;
begin
  if AScope = scUser then
    Result := '--user'
  else
    Result := '--system';
end;

function ScopeToStr(AScope : TServiceScope) : String;
begin
  if AScope = scUser then
    Result := 'User'
  else
    Result := 'System';
end;

function StatusFromActiveState(const AActive : String) : TServiceStatus;
begin
  if AActive = 'active' then
    Result := ssStarted
  else if AActive = 'failed' then
    Result := ssFailed
  else
    Result := ssStopped;
end;

function CompareServices(A, B : Pointer) : Integer;
begin
  Result := Ord(TService(A).Scope) - Ord(TService(B).Scope);
  if Result = 0 then
    Result := CompareStr(TService(A).UnitName, TService(B).UnitName);
end;

{ TService }

function TService.RunSystemctl(const AAction : String) : Boolean;
var
  LOutput : String;
begin
  Result := RunCommand('systemctl', [ScopeSwitch(FScope), AAction, FUnitName],
    LOutput, [poStderrToOutPut]);
end;

function TService.IsEnabled : Boolean;
begin
  // enabled, enabled-runtime
  Result := Pos('enabled', FUnitFileState) = 1;
end;

function TService.CanEnable : Boolean;
begin
  Result := FUnitFileState = 'disabled';
end;

function TService.Start : Boolean;
begin
  Result := RunSystemctl('start');
end;

function TService.Stop : Boolean;
begin
  Result := RunSystemctl('stop');
end;

function TService.Restart : Boolean;
begin
  Result := RunSystemctl('restart');
end;

function TService.Enable : Boolean;
begin
  Result := RunSystemctl('enable');
end;

function TService.Disable : Boolean;
begin
  Result := RunSystemctl('disable');
end;

{ TServiceList }

constructor TServiceList.Create;
begin
  inherited Create;
  FItems := TFPList.Create;
  FServiceFilterType := ftAll;
  FServiceFilterState := fsAll;
end;

destructor TServiceList.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TServiceList.Clear;
var
  I : Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TService(FItems[I]).Free;
  FItems.Clear;
end;

function TServiceList.GetCount : Integer;
begin
  Result := FItems.Count;
end;

function TServiceList.GetItem(AIndex : Integer) : TService;
begin
  Result := TService(FItems[AIndex]);
end;

procedure TServiceList.ReadProcessOutput(AScope : TServiceScope; AOutput : TMemoryStream);
const
  BUF_SIZE = 4096;
var
  LProcess : TProcess;
  LBuffer : array[0..BUF_SIZE - 1] of Byte;
  LBytesRead : LongInt;
begin
  LProcess := TProcess.Create(nil);
  try
    LProcess.Executable := 'systemctl';
    LProcess.Parameters.Add('list-units');
    LProcess.Parameters.Add('--type');
    LProcess.Parameters.Add('service');
    LProcess.Parameters.Add(ScopeSwitch(AScope));
    case FServiceFilterState of
      fsInactive: LProcess.Parameters.Add('--state=inactive');
      fsRunning: LProcess.Parameters.Add('--state=running');
      fsFailed:  LProcess.Parameters.Add('--state=failed');
      // without --all, list-units hides inactive units
      fsAll:     LProcess.Parameters.Add('--all');
    end;

    LProcess.Parameters.Add('--no-pager');
    LProcess.Parameters.Add('--output');
    LProcess.Parameters.Add('json');
    LProcess.Options := [poUsePipes, poNoConsole];
    LProcess.Execute;

    // read the output of the process and store into the memory stream
    repeat
      LBytesRead := LProcess.Output.Read(LBuffer, BUF_SIZE);
      if LBytesRead > 0 then
        AOutput.Write(LBuffer, LBytesRead);
    until (LBytesRead = 0) and not LProcess.Running;

    // read what maybe is left in the pipe
    repeat
      LBytesRead := LProcess.Output.Read(LBuffer, BUF_SIZE);
      if LBytesRead > 0 then
        AOutput.Write(LBuffer, LBytesRead);
    until LBytesRead <= 0;
  finally
    LProcess.Free;
  end;
  AOutput.Position := 0;
end;

procedure TServiceList.ReadUnitFileStates(AScope : TServiceScope; AStates : TStringList);
var
  LOutput : String;
  LData : TJSONData;
  LArray : TJSONArray;
  LObj : TJSONObject;
  I : Integer;
begin
  AStates.Clear;
  if not RunCommand('systemctl', ['list-unit-files', '--type', 'service',
    ScopeSwitch(AScope), '--no-pager', '--output', 'json'], LOutput, [poNoConsole]) then
    Exit;
  if LOutput = '' then
    Exit;

  LData := GetJSON(LOutput);
  try
    if not (LData is TJSONArray) then
      Exit;
    LArray := TJSONArray(LData);
    for I := 0 to LArray.Count - 1 do
    begin
      if not (LArray.Items[I] is TJSONObject) then
        Continue;
      LObj := LArray.Objects[I];
      AStates.Values[LObj.Get('unit_file', '')] := LObj.Get('state', '');
    end;
  finally
    LData.Free;
  end;
end;

function TServiceList.Parse : Boolean;
var
  LSystemOk, LUserOk : Boolean;
begin
  Clear;
  case FServiceFilterType of
    ftSystem: Result := ParseScope(scSystem);
    ftUser:   Result := ParseScope(scUser);
  else
    // evaluate both so one failing (e.g. no user session bus) doesn't hide the other
    LSystemOk := ParseScope(scSystem);
    LUserOk := ParseScope(scUser);
    Result := LSystemOk or LUserOk;
  end;
  FItems.Sort(@CompareServices);
end;

// list-units only reports units systemd currently has in memory, so a stopped
// and disabled service is usually missing from it. Add the remaining installed
// unit files, using one "systemctl show" call to get their details.
procedure TServiceList.AddUnloadedUnits(AScope : TServiceScope; AStates, ASeen : TStringList);
const
  FIXED_ARGS = 5;
var
  LNew, LLines : TStringList;
  LArgs : array of String;
  LOutput, LName, LState, LKey, LValue : String;
  LId, LDescription, LLoad, LActive : String;
  LService : TService;
  LEq, I : Integer;

  procedure FlushBlock;
  var
    LIdx : Integer;
  begin
    LIdx := LNew.IndexOf(LId);
    if LIdx >= 0 then
    begin
      LService := TService(LNew.Objects[LIdx]);
      LService.FDescription := LDescription;
      LService.FLoaded := LLoad = 'loaded';
      LService.FActive := LActive = 'active';
      LService.FStatus := StatusFromActiveState(LActive);
    end;
    LId := ''; LDescription := ''; LLoad := ''; LActive := '';
  end;

begin
  LNew := TStringList.Create;
  LLines := TStringList.Create;
  try
    LNew.Sorted := True;
    for I := 0 to AStates.Count - 1 do
    begin
      LName := AStates.Names[I];
      LState := AStates.ValueFromIndex[I];
      // aliases are listed under their real name; templates can't run uninstanced
      if (LName = '') or (LState = 'alias') or (Pos('@.', LName) > 0) or
         (ASeen.IndexOf(LName) >= 0) then
        Continue;
      LService := TService.Create;
      LService.FUnitName := LName;
      LService.FScope := AScope;
      LService.FUnitFileState := LState;
      LService.FStatus := ssStopped;
      FItems.Add(LService);
      LNew.AddObject(LName, LService);
    end;
    if LNew.Count = 0 then
      Exit;

    SetLength(LArgs, FIXED_ARGS + LNew.Count);
    LArgs[0] := ScopeSwitch(AScope);
    LArgs[1] := 'show';
    LArgs[2] := '--no-pager';
    LArgs[3] := '-p';
    LArgs[4] := 'Id,Description,LoadState,ActiveState';
    for I := 0 to LNew.Count - 1 do
      LArgs[FIXED_ARGS + I] := LNew[I];
    // details are optional: on failure the units keep their defaults
    RunCommand('systemctl', LArgs, LOutput, [poNoConsole]);

    // output is one "Key=Value" block per unit, separated by blank lines
    LLines.Text := LOutput;
    LId := ''; LDescription := ''; LLoad := ''; LActive := '';
    for I := 0 to LLines.Count - 1 do
    begin
      if LLines[I] = '' then
      begin
        FlushBlock;
        Continue;
      end;
      LEq := Pos('=', LLines[I]);
      if LEq = 0 then
        Continue;
      LKey := Copy(LLines[I], 1, LEq - 1);
      LValue := Copy(LLines[I], LEq + 1, MaxInt);
      if LKey = 'Id' then LId := LValue
      else if LKey = 'Description' then LDescription := LValue
      else if LKey = 'LoadState' then LLoad := LValue
      else if LKey = 'ActiveState' then LActive := LValue;
    end;
    FlushBlock;
  finally
    LLines.Free;
    LNew.Free;
  end;
end;

function TServiceList.ParseScope(AScope : TServiceScope) : Boolean;
var
  LOutput : TMemoryStream;
  LStates : TStringList;
  LTemplate : String;
  LAtPos : Integer;
  LData : TJSONData;
  LArray : TJSONArray;
  LObj : TJSONObject;
  LSeen : TStringList;
  LService : TService;
  LActive : String;
  I : Integer;
begin
  Result := False;
  LStates := TStringList.Create;
  LSeen := TStringList.Create;
  LSeen.Sorted := True;
  LOutput := TMemoryStream.Create;
  try
    ReadUnitFileStates(AScope, LStates);
    ReadProcessOutput(AScope, LOutput);
    if LOutput.Size = 0 then
      Exit;

    LData := GetJSON(LOutput);
    try
      if not (LData is TJSONArray) then
        Exit;
      //Parse the JSON
      LArray := TJSONArray(LData);

      for I := 0 to LArray.Count - 1 do
      begin
        if not (LArray.Items[I] is TJSONObject) then
          Continue;
        LObj := LArray.Objects[I];

        LService := TService.Create;
        LService.FUnitName := LObj.Get('unit', '');
        LService.FScope := AScope;
        LSeen.Add(LService.FUnitName);
        LService.FDescription := LObj.Get('description', '');
        LService.FLoaded := LObj.Get('load', '') = 'loaded';

        LService.FUnitFileState := LStates.Values[LService.FUnitName];
        // template instances (foo@bar.service) are listed as foo@.service
        LAtPos := Pos('@', LService.FUnitName);
        if (LService.FUnitFileState = '') and (LAtPos > 0) then
        begin
          LTemplate := Copy(LService.FUnitName, 1, LAtPos) +
            Copy(LService.FUnitName, LastDelimiter('.', LService.FUnitName), MaxInt);
          LService.FUnitFileState := LStates.Values[LTemplate];
        end;

        LActive := LObj.Get('active', '');
        LService.FActive := LActive = 'active';
        LService.FStatus := StatusFromActiveState(LActive);

        FItems.Add(LService);
      end;

      // units that aren't loaded are always inactive
      if FServiceFilterState in [fsInactive, fsAll] then
        AddUnloadedUnits(AScope, LStates, LSeen);

      Result := True;
    finally
      LData.Free;
    end;
  finally
    LOutput.Free;
    LSeen.Free;
    LStates.Free;
  end;
end;

function TServiceList.DaemonReloadScope(AScope : TServiceScope) : Boolean;
var
  Dummy : String;
begin
  Result := RunCommand('systemctl', [ScopeSwitch(AScope), 'daemon-reload'],
    Dummy, [poStderrToOutPut]);
end;

function TServiceList.DaemonReload : Boolean;
var
  LSystemOk, LUserOk : Boolean;
begin
  case FServiceFilterType of
    ftSystem: Result := DaemonReloadScope(scSystem);
    ftUser:   Result := DaemonReloadScope(scUser);
  else
    LSystemOk := DaemonReloadScope(scSystem);
    LUserOk := DaemonReloadScope(scUser);
    Result := LSystemOk and LUserOk;
  end;
end;

end.
