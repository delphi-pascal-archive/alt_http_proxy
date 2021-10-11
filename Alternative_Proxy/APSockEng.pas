unit APSockEng;

interface
uses Windows, ScktComp, Classes, Registry, SysUtils, Messages, Dialogs, ComCtrls,
      WinSock, SConnect;

Type
  THTTPProxy = class(TServerSocket)
  private
    FTimeout: Integer;
    procedure GetThread(Sender: TObject; ClientSocket: TServerClientWinSocket;
      var SocketThread: TServerClientThread);
  public
    constructor Create(AOwner: TComponent); override;
    property Timeout: Integer read FTimeout write FTimeout;
  end;

  THTTPProxyTransport = class;
  THTTPProxyThread = class(TServerClientThread)
  private
    FTimeout: TDateTime;
    FTransport: THTTPProxyTransport;
    FLogFile: String;
    function CreateServerTransport: THTTPProxyTransport;
    function Authenticate(MS: TMemoryStream): Integer;
    procedure LoadFromRemoteServer(MS: TMemoryStream; Host, Port: String);
    procedure Answer(MS: TMemoryStream);
    procedure WriteLog(Text: String);
  protected
  public
    constructor Create(CreateSuspended: Boolean; ASocket: TServerClientWinSocket; Timeout: Integer);
    procedure ClientExecute; override;
    property LogFile: String read FLogFile write FLogFile;
  end;

  THTTPProxyTransport = class(TInterfacedObject)
  private
    FEvent: THandle;
    FClientSocket: TClientSocket;
    FSocket: TCustomWinSocket;
    FPort: Integer;
    FHost: string;
    FAddress: string;
  protected
    function GetWaitEvent: THandle; stdcall;
    function GetConnected: Boolean; stdcall;
    procedure SetConnected(Value: Boolean); stdcall;
    function Receive(WaitForInput: Boolean; Context: Integer): TMemoryStream; stdcall;
    function Send(Data: TMemoryStream): Integer; stdcall;
  public
    property Host: string read FHost write FHost;
    property Address: string read FAddress write FAddress;
    property Port: Integer read FPort write FPort;
    property Socket: TCustomWinSocket read FSocket write FSocket;
  end;

  function EncodeBase64(const inStr: string): string;
  function DecodeBase64(const CinLine: string): string;

implementation

uses
 main, RTLConsts, Sockets;

 // Base64 encoding
function EncodeBase64(const inStr: string): string;
  function Encode_Byte(b: Byte): char;
  const Base64Code: string[64] =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  begin
    Result := Base64Code[(b and $3F)+1];
  end;
var i: Integer;
begin
  i := 1;
  Result := '';
  while i <= Length(InStr) do begin
    Result := Result + Encode_Byte(Byte(inStr[i]) shr 2);
    Result := Result + Encode_Byte((Byte(inStr[i]) shl 4) or (Byte(inStr[i+1]) shr 4));
    if i+1 <= Length(inStr)
      then Result := Result + Encode_Byte((Byte(inStr[i+1]) shl 2) or (Byte(inStr[i+2]) shr 6))
      else Result := Result + '=';
    if i+2 <= Length(inStr)
      then Result := Result + Encode_Byte(Byte(inStr[i+2]))
      else Result := Result + '=';
    Inc(i, 3);
  end;
end;

// Base64 decoding
function DecodeBase64(const CinLine: string): string;
const
  RESULT_ERROR = -2;
var
  inLineIndex: Integer;
  c: Char;
  x: SmallInt;
  c4: Word;
  StoredC4: array[0..3] of SmallInt;
  InLineLength: Integer;
begin
  Result := '';
  inLineIndex := 1;
  c4 := 0;
  InLineLength := Length(CinLine);

  while inLineIndex <= InLineLength do begin
    while (inLineIndex <= InLineLength) and (c4 < 4) do begin
      c := CinLine[inLineIndex];
      case c of
        '+'     : x := 62;
        '/'     : x := 63;
        '0'..'9': x := Ord(c) - (Ord('0')-52);
        '='     : x := -1;
        'A'..'Z': x := Ord(c) - Ord('A');
        'a'..'z': x := Ord(c) - (Ord('a')-26);
      else
        x := RESULT_ERROR;
      end;
      if x <> RESULT_ERROR then begin
        StoredC4[c4] := x;
        Inc(c4);
      end;
      Inc(inLineIndex);
    end;
    if c4 = 4 then begin
      c4 := 0;
      Result := Result + Char((StoredC4[0] shl 2) or (StoredC4[1] shr 4));
      if StoredC4[2] = -1 then Exit;
      Result := Result + Char((StoredC4[1] shl 4) or (StoredC4[2] shr 2));
      if StoredC4[3] = -1 then Exit;
      Result := Result + Char((StoredC4[2] shl 6) or (StoredC4[3]));
    end;
  end;
end;

function StrReplace(S, WhatFind, Repl: String): String;
var i: Integer;
begin
  i := pos(WhatFind, S);
  while i > 0 do begin
    Delete(S, i, Length(WhatFind));
    Insert(Repl, S, i);
    i := pos(WhatFind, S);
  end;
  Result := S;
end;

constructor THTTPProxy.Create(AOwner: TComponent);
begin
 if not LoadWinSock2
 then raise Exception.Create('WinSock не установлен, его присутствие необходимо для соеденения.');
 inherited Create(AOwner);
 ServerType := stThreadBlocking;
 OnGetThread := GetThread;
end;

procedure THTTPProxy.GetThread(Sender: TObject;
  ClientSocket: TServerClientWinSocket; var SocketThread: TServerClientThread);
begin
 SocketThread:=THTTPProxyThread.Create(False, ClientSocket, Timeout);
end;

{ THTTPProxyThread }

procedure THTTPProxyThread.Answer(MS: TMemoryStream);
var
 SS: TStringStream;
 S, S2, TargetHost, TargetPort: string;
 SL: TStringList;
 p: Integer;
begin
  SS:=TStringStream.Create(S);
  SL:=TStringList.Create;
  try
    SS.CopyFrom(MS, MS.Size);
    SL.Text := SS.DataString;
    if SL.Count>0
    then
     begin
      if Length(SL[0])>5
      then
       begin
        if copy(SL[0], 1, 3) = 'GET'
        then S2:=Copy(SL[0], 5, Length(SL[0]) - 4);
        if copy(SL[0], 1, 4) = 'POST'
        then S2 := Copy(SL[0], 6, Length(SL[0]) - 5);
        if copy(SL[0], 1, 7) = 'CONNECT'
        then S2 := Copy(SL[0], 9, Length(SL[0]) - 8);
        //
        p := pos(' ' , S2);
        if p > 0
        then
         begin
          TargetHost := Copy(S2, 1, p - 1);
          TargetHost := StrReplace(TargetHost, 'http://', '');
          p := pos('/', TargetHost);
          if p > 0
          then TargetHost := copy(TargetHost, 1, p - 1);
          p := pos(' ', TargetHost);
          if p > 0
          then TargetHost := copy(TargetHost, 1, p - 1);
          p := pos(':', TargetHost);
          if p > 0
          then
           begin
            TargetPort := copy(TargetHost, p + 1, Length(TargetHost) - p);
            TargetHost := copy(TargetHost, 1, p - 1);
           end
          else TargetPort := '80';

          MS.Position := 0;
          WriteLog(SL[0] + ' (Host:' + TargetHost + ')');
          LoadFromRemoteServer(MS, TargetHost, TargetPort);
       end
      else
       begin

       end;
     end;
   end;
  finally
   SS.Free;
   SL.Free;
  end;
end;

function THTTPProxyThread.Authenticate(MS: TMemoryStream): Integer;
const
  CookieStr = 'Cookie: ALTERNATIVE_PROXY=';
  AuthStr   = 'Proxy-Authorization: Basic ';
 function GetUserPwl(SL: TStringList): String;
 var
  i, j: Integer;
 begin
  Result := '';
  for i := 0 to SL.Count - 1 do
   begin
    j := pos(AnsiLowerCase(AuthStr), AnsiLowerCase(SL[i]));
    if j > 0
    then
     begin
      Result := copy(SL[i], j + Length(AuthStr), Length(SL[i]) - j - Length(AuthStr) + 1);
      Result := DecodeBase64(Result);
      exit;
     end;
   end;
 end;

var
 SS: TStringStream;
 S: String;
 SL: TStringList;
begin
  SL := TStringList.Create;
  MS.Position := 0;
  SS := TStringStream.Create(S);
  SS.CopyFrom(MS, MS.Size);
  SL.Text := SS.DataString;
  SS.Free;
  S := GetUserPwl(SL);
  if S <> 'your_login:your_pwl'
  then
   begin
    S :=  'HTTP/1.0 407 Proxy Authentication Required'#13#10 +
          'Content-type: text/html'#13#10+
          'Proxy-Authenticate: Basic realm="ALTERNATIVE PROXY"'#13#10+
          'Для доступа к этой странице требуется пароль!'#13#10;


    SS := TStringStream.Create(S);
    MS.Clear;
    MS.LoadFromStream(SS);
    SS.Free;
    Result := -1;
   end
  else Result := 10;
end;

procedure THTTPProxyThread.ClientExecute;
var
  msg: TMsg;
  Event: THandle;
  WaitTime: DWord;
  CurData: TMemoryStream;
begin
  FTransport := CreateServerTransport;
  try
    Event := FTransport.GetWaitEvent;
    PeekMessage(msg, 0, WM_USER, WM_USER, PM_NOREMOVE);
    if FTimeout = 0
    then WaitTime := INFINITE
    else WaitTime := 60000;
    //
    while not Terminated and FTransport.GetConnected do
    try
      case MsgWaitForMultipleObjects(1, Event, False, WaitTime, QS_ALLEVENTS) of
        WAIT_OBJECT_0: begin
          WSAResetEvent(Event);
          CurData := FTransport.Receive(False, 0);
          Answer(CurData);
          CurData.Position := 0;
          FTransport.Send(CurData);
          FTransport.SetConnected(false);
        end;
        WAIT_OBJECT_0 + 1:
          while PeekMessage(msg, 0, 0, 0, PM_REMOVE) do DispatchMessage(msg);
        {WAIT_TIMEOUT:
          if (FTimeout > 0) and ((Now - FLastActivity) > FTimeout)
          then FTransport.Connected := False;}
      end;
    except
      FTransport.SetConnected(False);
    end;
  finally
    FTransport.Free;
    FTransport := nil;
  end;
end;

constructor THTTPProxyThread.Create(CreateSuspended: Boolean;
  ASocket: TServerClientWinSocket; Timeout: Integer);
begin
 FTimeout:= EncodeTime(Timeout div 60, Timeout mod 60, 0, 0);
 inherited Create(CreateSuspended, ASocket);
 LogFile:='http_log.txt';
end;

function THTTPProxyThread.CreateServerTransport: THTTPProxyTransport;
var
 HTTPProxyTransport: THTTPProxyTransport;
begin
 HTTPProxyTransport:=THTTPProxyTransport.Create;
 HTTPProxyTransport.Socket:=ClientSocket;
 Result:=HTTPProxyTransport;
end;

procedure THTTPProxyThread.LoadFromRemoteServer(MS: TMemoryStream; Host, Port: String);
var
 C: TTcpClient;
 P: PChar;
 RecLen: Integer;
begin
  C:=TTcpClient.Create(nil);
  C.RemoteHost:=Host;
  C.RemotePort:=Port;
  try
    //if Authenticate(MS) <> -1
    //then
     if C.Connect
     then
      begin
       MS.Position := 0;
       C.SendStream(MS);
       MS.Clear;
       P := GetMemory(256);
       RecLen := C.ReceiveBuf(P^, 256);
       while RecLen > 0 do
        begin
         MS.Write(P^, RecLen);
         RecLen := C.ReceiveBuf(P^, 256);
        end;
      FreeMemory(P);
     end;
  finally
    C.Free;
  end;
end;

procedure THTTPProxyThread.WriteLog(Text: string);
var
 F: TextFile;
begin
 AssignFile(F, FLogFile);
 if FileExists(FLogFile)
 then Append(F)
 else ReWrite(F);
 WriteLn(F, DateTimeToStr(Now)+' - '+Text);
 CloseFile(F);
 //
 try
  Form1.RichEdit1.Lines.Add(DateTimeToStr(Now)+' - '+Text);
 except

 end;
end;

{ THTTPProxyTransport }

function THTTPProxyTransport.GetConnected: Boolean;
begin
 Result:=(FSocket <> nil) and (FSocket.Connected);
end;

function THTTPProxyTransport.GetWaitEvent: THandle;
begin
 FEvent := WSACreateEvent;
 WSAEventSelect(FSocket.SocketHandle, FEvent, FD_READ or FD_CLOSE);
 Result := FEvent;
end;

function THTTPProxyTransport.Receive(WaitForInput: Boolean;
  Context: Integer): TMemoryStream;
var
 RetLen: Integer;
 P: PChar;
 FDSet: TFDSet;
 TimeVal: PTimeVal;
 RetVal: Integer;
begin
  Result := nil;
  TimeVal := nil;
  FD_ZERO(FDSet);
  FD_SET(FSocket.SocketHandle, FDSet);
  if not WaitForInput then
  begin
    New(TimeVal);
    TimeVal.tv_sec := 0;
    TimeVal.tv_usec := 1;
  end;
  RetVal := select(0, @FDSet, nil, nil, TimeVal);
  if Assigned(TimeVal) then
    FreeMem(TimeVal);
  if RetVal = SOCKET_ERROR then
    raise Exception.Create(SysErrorMessage(WSAGetLastError));
  if (RetVal = 0) then Exit;

  Result := TMemoryStream.Create;
  P := GetMemory(256);
  RetLen := FSocket.ReceiveBuf(P^, 256);
  while RetLen > 0 do
   begin
    Result.Write(P^, RetLen);
    RetLen := FSocket.ReceiveBuf(P^, 256);
   end;
  FreeMemory(P);
  Result.Position := 0;
end;

function THTTPProxyTransport.Send(Data: TMemoryStream): Integer;
var
  P: Pointer;
begin
  Result := 0;
  Data.Position := 0;
  P := Data.Memory;
  Result := FSocket.SendBuf(P^, Data.Size);
end;

procedure THTTPProxyTransport.SetConnected(Value: Boolean);
begin
  if GetConnected = Value then Exit;
  if Value then begin
    if (FAddress = '') and (FHost = '') then
      raise ESocketConnectionError.CreateRes(@SNoAddress);
    FClientSocket := TClientSocket.Create(nil);
    FClientSocket.ClientType := ctBlocking;
    FSocket := FClientSocket.Socket;
    FClientSocket.Port := FPort;
    if FAddress <> '' then
      FClientSocket.Address := FAddress else
      FClientSocket.Host := FHost;
    FClientSocket.Open;
  end else begin
    if FSocket <> nil then FSocket.Close;
    FSocket := nil;
    FreeAndNil(FClientSocket);
    if FEvent <> 0 then WSACloseEvent(FEvent);
    FEvent := 0;
  end;
end;

end.
