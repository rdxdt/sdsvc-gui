unit ufrmmain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Process, Service;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    btnServiceEnable: TButton;
    btnServiceDisable: TButton;
    btnServiceStart: TButton;
    btnServiceStop: TButton;
    btnServiceRestart: TButton;
    ImageList1: TImageList;
    lblServiceName: TLabel;
    lblServiceDescription: TLabel;
    lblAction: TLabel;
    lvwServiceList: TListView;
    pnlServiceActions: TPanel;
    StatusBar1: TStatusBar;
    ToolBar1: TToolBar;
    tbRefresh: TToolButton;
    tb: TToolButton;
    ToolButton3: TToolButton;
    tbInfo: TToolButton;
    procedure FormCreate(Sender: TObject);
    procedure lvwServiceListChange(Sender: TObject; Item: TListItem;
      Change: TItemChange);
    procedure lvwServiceListSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure tbRefreshClick(Sender: TObject);
    procedure tbClick(Sender: TObject);
    procedure tbInfoClick(Sender: TObject);
    procedure RefreshServiceList;
    procedure UpdateServiceDetails;
  private

  public
    ServiceList : TServiceList;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.tbInfoClick(Sender: TObject);
begin
  MessageDlg('About this application',
    'SystemD Service Manager by rdxdt'+#13+
    'https://github.com/rdxdt/sdsvc-gui'+#13+
    'Icons from https://freeicon.com',
    mtInformation,
    [mbOk],
    0);
end;

procedure TfrmMain.tbClick(Sender: TObject);
var
  LOutput : String;
begin
  RunCommand('systemctl', ['daemon-reload'], LOutput, [poStderrToOutPut]);
  MessageDlg(LOutput,mtInformation,[mbOk],0);
end;

procedure TfrmMain.tbRefreshClick(Sender: TObject);
begin
  ServiceList := TServiceList.Create;
  RefreshServiceList;
  lvwServiceList.ItemIndex := 0;
  UpdateServiceDetails;
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
  UpdateServiceDetails;
end;

procedure TfrmMain.RefreshServiceList;
var
  L : TListItem;
  I : Integer;
begin
  ServiceList.Clear;
  lvwServiceList.Clear;
  if not ServiceList.Parse then
  begin
    MessageDlg('Retrieving service list failed',mtError,[mbOk],0);
    Exit;
  end;
  for I := 0 to ServiceList.Count -1 do
  begin
    L := lvwServiceList.Items.Add;
    L.Caption := ServiceList.Items[I].UnitName;
    L.SubItems.Add(BoolToStr(ServiceList.Items[I].Loaded,True));
    L.SubItems.Add(BoolToStr(ServiceList.Items[I].Active,True));
    case ServiceList.Items[I].Status of
      ssStopped: L.SubItems.Add('Stopped');
      ssStarted: L.SubItems.Add('Running');
      ssFailed:  L.SubItems.Add('Failed');
    end;
    L.SubItems.Add(ServiceList.Items[I].Description);
  end;
end;

procedure TfrmMain.UpdateServiceDetails;
begin
  lblServiceName.Caption :=
    ServiceList.Items[lvwServiceList.ItemIndex].UnitName;
  lblServiceDescription.Caption :=
    ServiceList.Items[lvwServiceList.ItemIndex].Description;
  btnServiceEnable.Enabled := not ServiceList.Items[lvwServiceList.ItemIndex].Active;
  btnServiceDisable.Enabled := ServiceList.Items[lvwServiceList.ItemIndex].Active;
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

