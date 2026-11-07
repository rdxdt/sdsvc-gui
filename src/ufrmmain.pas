unit ufrmmain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Buttons, Process, Service;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    btnDaemonReload: TBitBtn;
    BitBtn2: TBitBtn;
    btnRefresh: TBitBtn;
    btnServiceEnable: TButton;
    btnServiceDisable: TButton;
    btnServiceStart: TButton;
    btnServiceStop: TButton;
    btnServiceRestart: TButton;
    cbxFilterType: TComboBox;
    cbxFilterState: TComboBox;
    lblServiceName: TLabel;
    lblServiceDescription: TLabel;
    lblAction: TLabel;
    lvwServiceList: TListView;
    Panel1: TPanel;
    pnlServiceActions: TPanel;
    StatusBar1: TStatusBar;
    procedure BitBtn2Click(Sender: TObject);
    procedure btnDaemonReloadClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnServiceDisableClick(Sender: TObject);
    procedure btnServiceEnableClick(Sender: TObject);
    procedure btnServiceRestartClick(Sender: TObject);
    procedure btnServiceStartClick(Sender: TObject);
    procedure btnServiceStopClick(Sender: TObject);
    procedure cbxFilterStateChange(Sender: TObject);
    procedure cbxFilterTypeChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure lvwServiceListChange(Sender: TObject; Item: TListItem;
      Change: TItemChange);
    procedure lvwServiceListSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure RefreshServiceList;
    procedure RefreshAfterAction(AService : TService);
    procedure UpdateServiceDetails;
  private

  public
    ServiceList : TServiceList;
  end;

var
  frmMain: TfrmMain;

implementation

uses UDlgAbout;

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  RefreshServiceList;
  lvwServiceList.ItemIndex := 0;
  UpdateServiceDetails;
end;

procedure TfrmMain.btnDaemonReloadClick(Sender: TObject);
begin
  if not ServiceList.DaemonReload then
    MessageDlg('Daemon reload failed',mtError,[mbOk],0);
end;

procedure TfrmMain.BitBtn2Click(Sender: TObject);
begin
  dlgAbout.ShowModal;
end;

procedure TfrmMain.lvwServiceListChange(Sender: TObject; Item: TListItem;
  Change: TItemChange);
begin
  UpdateServiceDetails;
end;

procedure TfrmMain.lvwServiceListSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  UpdateServiceDetails;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  ServiceList := TServiceList.Create;
  RefreshServiceList;
  lvwServiceList.ItemIndex := 0;
end;

procedure TfrmMain.btnServiceStopClick(Sender: TObject);
begin
  if lvwServiceList.ItemIndex = -1 then
    Exit;
  if MessageDlg('Are you sure you want to stop the service '+
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName,mtConfirmation,[
    mbYes,mbNo],0) = mrNo then
    Exit;
  ServiceList.Items[lvwServiceList.ItemIndex].Stop;
  RefreshAfterAction(ServiceList.Items[lvwServiceList.ItemIndex]);
end;

procedure TfrmMain.cbxFilterStateChange(Sender: TObject);
begin
  ServiceList.ServiceFilterState:= TServiceFilterState(cbxFilterState.ItemIndex);
  RefreshServiceList;
end;

procedure TfrmMain.cbxFilterTypeChange(Sender: TObject);
begin
  ServiceList.ServiceFilterType:= TServiceFilterType(cbxFilterType.ItemIndex);
  RefreshServiceList;
end;

procedure TfrmMain.btnServiceRestartClick(Sender: TObject);
begin
  if lvwServiceList.ItemIndex = -1 then
    Exit;
  if MessageDlg('Are you sure you want to restart the service '+
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName,mtConfirmation,[
    mbYes,mbNo],0) = mrNo then
    Exit;
  ServiceList.Items[lvwServiceList.ItemIndex].Restart;
  RefreshAfterAction(ServiceList.Items[lvwServiceList.ItemIndex]);
end;

procedure TfrmMain.btnServiceDisableClick(Sender: TObject);
begin
  if lvwServiceList.ItemIndex = -1 then
    Exit;
  if MessageDlg('Are you sure you want to disable the service '+
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName,mtConfirmation,[
    mbYes,mbNo],0) = mrNo then
    Exit;
  ServiceList.Items[lvwServiceList.ItemIndex].Disable;
  RefreshAfterAction(ServiceList.Items[lvwServiceList.ItemIndex]);
end;

procedure TfrmMain.btnServiceEnableClick(Sender: TObject);
begin
  if lvwServiceList.ItemIndex = -1 then
    Exit;
  if MessageDlg('Are you sure you want to enable the service '+
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName,mtConfirmation,[
    mbYes,mbNo],0) = mrNo then
    Exit;
  ServiceList.Items[lvwServiceList.ItemIndex].Enable;
  RefreshAfterAction(ServiceList.Items[lvwServiceList.ItemIndex]);
end;

procedure TfrmMain.btnServiceStartClick(Sender: TObject);
begin
  if lvwServiceList.ItemIndex = -1 then
    Exit;
  if MessageDlg('Are you sure you want to start the service '+
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName,mtConfirmation,[
    mbYes,mbNo],0) = mrNo then
    Exit;
  ServiceList.Items[lvwServiceList.ItemIndex].Start;
  RefreshAfterAction(ServiceList.Items[lvwServiceList.ItemIndex]);
end;

procedure TfrmMain.RefreshServiceList;
var
  L : TListItem;
  I : Integer;
begin
  ServiceList.Clear;
  lvwServiceList.Items.Clear;
  if not ServiceList.Parse then
  begin
    MessageDlg('Retrieving service list failed',mtError,[mbOk],0);
    Exit;
  end;
  for I := 0 to ServiceList.Count -1 do
  begin
    L := lvwServiceList.Items.Add;
    L.Caption := ServiceList.Items[I].UnitName;
    L.SubItems.Add(ScopeToStr(ServiceList.Items[I].Scope));
    L.SubItems.Add(BoolToStr(ServiceList.Items[I].Loaded,True));
    L.SubItems.Add(ServiceList.Items[I].UnitFileState);
    L.SubItems.Add(BoolToStr(ServiceList.Items[I].Active,True));
    case ServiceList.Items[I].Status of
      ssStopped:
        begin
          L.SubItems.Add('Stopped');
          L.ImageIndex:= 5;
        end;
      ssStarted:
        begin
        L.SubItems.Add('Running');
          L.ImageIndex:= 3;
        end;
      ssFailed:
        begin
          L.SubItems.Add('Failed');
          L.ImageIndex:= 4;
        end;
    end;
    L.SubItems.Add(ServiceList.Items[I].Description);
  end;
end;

procedure TfrmMain.RefreshAfterAction(AService : TService);
var
  I : Integer;
  LUnitName : String;
  LScope : TServiceScope;
begin
  // copy before the refresh frees AService
  LUnitName := AService.UnitName;
  LScope := AService.Scope;
  RefreshServiceList;
  lvwServiceList.ItemIndex := -1;
  for I := 0 to ServiceList.Count - 1 do
    if (ServiceList.Items[I].UnitName = LUnitName) and
       (ServiceList.Items[I].Scope = LScope) then
    begin
      lvwServiceList.ItemIndex := I;
      Break;
    end;
  UpdateServiceDetails;
end;

procedure TfrmMain.UpdateServiceDetails;
begin
  if lvwServiceList.ItemIndex = -1 then
  begin
    lblServiceName.Caption := '';
    lblServiceDescription.Caption := '';
    btnServiceEnable.Enabled := False;
    btnServiceDisable.Enabled := False;
    btnServiceStart.Enabled:= False;
    btnServiceStop.Enabled:= False;
    btnServiceRestart.Enabled := False;
    Exit;
  end;
  lblServiceName.Caption :=
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName;
  lblServiceDescription.Caption :=
    ServiceList.Items[lvwServiceList.ItemIndex].Description;
  btnServiceEnable.Enabled := ServiceList.Items[lvwServiceList.ItemIndex].CanEnable;
  btnServiceDisable.Enabled := ServiceList.Items[lvwServiceList.ItemIndex].IsEnabled;
  case ServiceList.Items[lvwServiceList.ItemIndex].Status of
    ssStopped:
      begin
        btnServiceStart.Enabled := True;
        btnServiceStop.Enabled := False;
        btnServiceRestart.Enabled := False;
      end;
    ssStarted:
      begin
        btnServiceStart.Enabled := False;
        btnServiceStop.Enabled := True;
        btnServiceRestart.Enabled := True;
      end;
    ssFailed:
      begin
        btnServiceStart.Enabled := True;
        btnServiceStop.Enabled := False;
        btnServiceRestart.Enabled := False;
      end;
  end;
end;


end.

