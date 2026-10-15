unit service;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Process, fpjson, jsonparser;

type
  TServiceStatus = (ssStopped, ssStarted, ssFailed);

type
  TService = class(TObject)
    private
      FUnitName : String;
      FDescription : String;
      FLoaded : Boolean;
      FActive : Boolean;
      FStatus : TServiceStatus;

      function RunSystemctl(const AAction : String) : Boolean;
    public
      property UnitName : String read FUnitName;
      property Description : String read FDescription;
      property Loaded : Boolean read FLoaded;
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

      function GetCount : Integer;
      function GetItem(AIndex : Integer) : TService;
      procedure ReadProcessOutput(AOutput : TMemoryStream);
    public
      constructor Create;
      destructor Destroy; override;

      procedure Clear;
      function Parse : Boolean;

      property Count : Integer read GetCount;
      property Items[AIndex : Integer] : TService read GetItem; default;
  end;


implementation

{ TService }

function TService.RunSystemctl(const AAction : String) : Boolean;
var
  LOutput : String;
begin
  Result := RunCommand('systemctl', [AAction, FUnitName], LOutput, [poStderrToOutPut]);
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

procedure TServiceList.ReadProcessOutput(AOutput : TMemoryStream);
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
    LProcess.Parameters.Add('--all');
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

function TServiceList.Parse : Boolean;
var
  LOutput : TMemoryStream;
  LData : TJSONData;
  LArray : TJSONArray;
  LObj : TJSONObject;
  LService : TService;
  LActive : String;
  I : Integer;
begin
  Result := False;
  Clear;
  LOutput := TMemoryStream.Create;
  try
    ReadProcessOutput(LOutput);
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
        LService.FDescription := LObj.Get('description', '');
        LService.FLoaded := LObj.Get('load', '') = 'loaded';

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
  end;
end;

end.
