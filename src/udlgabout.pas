unit udlgabout;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls;

type

  { TdlgAbout }

  TdlgAbout = class(TForm)
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
  private

  public

  end;

var
  dlgAbout: TdlgAbout;

implementation

{$R *.lfm}

end.

