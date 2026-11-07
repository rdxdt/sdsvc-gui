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
  LService : TService;
  LActive : String;
  I : Integer;
begin
  Result := False;
  LStates := TStringList.Create;
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
        if LActive = 'active' then
          LService.FStatus := ssStarted
        else if LActive = 'failed' then
          LService.FStatus := ssFailed
        else
          LService.FStatus := ssStopped;

        FItems.Add(LService);
      end;

      Result := True;
    finally
      LData.Free;
    end;
  finally
    LOutput.Free;
    LStates.Free;
  end;
end;

function TServiceList.DaemonReload:Boolean;
var
  Dummy : String;
begin
  Result:= RunCommand('systemctl',['daemon-reload'],Dummy,[poStderrToOutPut]);
end;

end.
