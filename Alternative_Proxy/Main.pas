unit Main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, Sockets, APSockEng, StdCtrls, ComCtrls;

type
  TForm1 = class(TForm)
    TcpServer1: TTcpServer;
    Label1: TLabel;
    Edit1: TEdit;
    RichEdit1: TRichEdit;
    Button1: TButton;
    Label2: TLabel;
    CheckBox1: TCheckBox;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure CheckBox1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
  public
    HTTPPRoxy: THTTPPRoxy;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
begin
 HTTPPRoxy:=THTTPPRoxy.Create(self);
 HTTPPRoxy.Port:=StrToInt(Edit1.Text);
 HTTPPRoxy.Open;
 Button1.Enabled:=false;
 Button2.Enabled:=true;
end;

procedure TForm1.CheckBox1Click(Sender: TObject);
begin
 if CheckBox1.Checked
 then Form1.FormStyle:=fsStayOnTop
 else Form1.FormStyle:=fsNormal;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
 HTTPPRoxy.Close;
 Button1.Enabled:=true;
 Button2.Enabled:=false;
end;

end.
