program ap;

uses
  Forms,
  Main in 'Main.pas' {Form1},
  APSockEng in 'APSockEng.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
