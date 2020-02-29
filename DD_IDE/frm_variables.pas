unit frm_variables;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ImgList, ComCtrls, StdCtrls, Buttons, ExtCtrls,
  SynEdit, SynHighlighterDDScript;

type
  TVarExampleSynEdit = class(TSynEdit)
  private
    fvarname: string;
    function GetSaveFileName(const fn: string): string;
    procedure SetFuncName(const fn: string);
  public
    property varname: string read fvarname write SetFuncName;
    procedure DoSave;
  end;

type
  varinfo_t = record
    varname: string[128];
    varvalue: string[255];
  end;
  varinfo_p = ^varinfo_t;
  varinfo_a = array[0..$FFF] of varinfo_t;
  varinfo_pa = ^varinfo_a;

type
  TFrame_Variables = class(TFrame)
    ToolbarPanel: TPanel;
    EditorPanel: TPanel;
    Splitter1: TSplitter;
    DetailPanel: TPanel;
    Panel1: TPanel;
    ListView1: TListView;
    SearchEdit: TEdit;
    ClearFilterSpeedButton: TSpeedButton;
    DeclPanel: TPanel;
    DeclEdit: TEdit;
    procedure ListView1Data(Sender: TObject; Item: TListItem);
    procedure ListView1Compare(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
    procedure ListView1ColumnClick(Sender: TObject; Column: TListColumn);
    procedure SearchEditChange(Sender: TObject);
    procedure ClearFilterSpeedButtonClick(Sender: TObject);
    procedure ListView1Change(Sender: TObject; Item: TListItem;
      Change: TItemChange);
    procedure DeclPanelResize(Sender: TObject);
  private
    { Private declarations }
    vars: varinfo_pa;
    numvars: integer;
    fgame: string;
    sortcolumn: integer;
    procedure ClearVars;
    procedure ResizeVars(const sz: Integer);
    procedure OnExampleChange(Sender: TObject);
  protected
    SynEdit1: TVarExampleSynEdit;
    SynPasSyn1: TSynDDScriptSyn;
    procedure CreateParams(var Params: TCreateParams); override;
    procedure FillListView;
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateGameControls(const game: string);
    procedure FocusAndSelectFirstItem;
  end;

implementation

{$R *.dfm}

uses
  ddc_base, ide_utils;

function TVarExampleSynEdit.GetSaveFileName(const fn: string): string;
var
  base: string;
begin
  base := ExtractFilePath(ParamStr(0));
  base := base + '\vars\';
  if not DirectoryExists(base) then
    MkDir(base);
  Result := base + fn + '.ddscript';
end;

procedure TVarExampleSynEdit.SetFuncName(const fn: string);
var
  lst: TStringList;
begin
  if fvarname <> fn then
  begin
    if not ReadOnly then
    begin
      if fvarname <> '' then
      begin
        lst := TStringList.Create;
        lst.Text := Text;
        lst.SaveToFile(GetSaveFileName(fvarname));
        lst.Free;
      end;
    end;
    lst := TStringList.Create;
    if FileExists(GetSaveFileName(fn)) then
      lst.LoadFromFile(GetSaveFileName(fn));
    Text := lst.Text;
    lst.Free;
    fvarname := fn;
  end;
end;

procedure TVarExampleSynEdit.DoSave;
var
  lst: TStringList;
begin
  if not ReadOnly then
    if fvarname <> '' then
    begin
      lst := TStringList.Create;
      lst.Text := Text;
      lst.SaveToFile(GetSaveFileName(fvarname));
      lst.Free;
    end;
end;

constructor TFrame_Variables.Create(AOwner: TComponent);
begin
  inherited;

  fgame := '';

  SynEdit1 := TVarExampleSynEdit.Create(Self);
  SynEdit1.Parent := DetailPanel;
  SynEdit1.Align := alClient;
  SynEdit1.Highlighter := nil;
  SynEdit1.OnChange := OnExampleChange;
  SynEdit1.Gutter.ShowLineNumbers := True;
  SynEdit1.Gutter.AutoSize := True;
  SynEdit1.MaxScrollWidth := 255;
  SynEdit1.WantTabs := True;
  SynEdit1.varname := '';

  SynPasSyn1 := TSynDDScriptSyn.Create(Self);

  SynEdit1.Highlighter := SynPasSyn1;
  SynEdit1.ReadOnly := CheckParm('-devparm') <= 0;
end;

procedure TFrame_Variables.CreateParams(var Params: TCreateParams);
begin
  sortcolumn := 0;
  Inherited;
end;

destructor TFrame_Variables.Destroy;
begin
  ClearVars;
  inherited;
end;

procedure TFrame_Variables.OnExampleChange(Sender: TObject);
begin
  if SynEdit1.Modified then
    SynEdit1.DoSave;
end;

procedure TFrame_Variables.ClearVars;
begin
  FreeMem(vars);
  numvars := 0;
end;

procedure TFrame_Variables.ResizeVars(const sz: Integer);
begin
  ReallocMem(vars, sz * SizeOf(varinfo_t));
  numvars := sz;
end;

procedure TFrame_Variables.FocusAndSelectFirstItem;
begin
  if ListView1.Items.Count > 0 then
  begin
    ListView1.Selected := ListView1.Items[0];
    ListView1.ItemFocused := ListView1.Selected;
  end;
end;

procedure TFrame_Variables.UpdateGameControls(const game: string);
var
  i: integer;
  fvariables: TStringList;
  s1, s2: string;
begin
  if fgame = LowerCase(game) then
    Exit;

  fgame := LowerCase(game);

  fvariables := dll_getvariables(fgame);

  if fvariables = nil then
    Exit;

  ResizeVars(fvariables.Count);

  for i := 0 to fvariables.Count - 1 do
  begin
    splitstring(fvariables.Strings[i], s1, s2, '=');
    vars[i].varname := s1;
    vars[i].varvalue := s2;
  end;

  fvariables.Free;

  FillListView;
end;

procedure TFrame_Variables.FillListView;

  procedure AddListItem(Info: varinfo_p);
  var
    ListItem: TListItem;
  begin
    ListItem := ListView1.Items.Add;
    ListItem.Caption := Info.varname;
    ListItem.SubItems.Add(Info.varvalue);
    ListItem.Data := Info;
  end;

var
  i: integer;
  srch: string;
begin
  ListView1.Items.BeginUpdate;
  try
    ListView1.Items.Clear;

    srch := LowerCase(Trim(SearchEdit.Text));

    for i := 0 to numvars - 1 do
    begin
      if Length(srch) = 0 then
        AddListItem(@vars[i])
      else if Pos(srch, LowerCase(vars[i].varname)) > 0 then
        AddListItem(@vars[i]);
    end;

  finally
    ListView1.AlphaSort;
    ListView1.Items.EndUpdate;
    FocusAndSelectFirstItem;
  end;
end;

procedure TFrame_Variables.ListView1Data(Sender: TObject;
  Item: TListItem);
begin
  //
end;

procedure TFrame_Variables.ListView1Compare(Sender: TObject; Item1,
  Item2: TListItem; Data: Integer; var Compare: Integer);
var
  value1, value2: string;
begin
  if sortcolumn = 0 then
  begin
    value1 := Item1.Caption;
    value2 := Item2.Caption;
  end
  else
  begin
    value1 := Item1.SubItems[sortcolumn - 1];
    value2 := Item2.SubItems[sortcolumn - 1];
  end;

  Compare := AnsiCompareText(value1, value2);
end;

procedure TFrame_Variables.ListView1ColumnClick(Sender: TObject;
  Column: TListColumn);
begin
  sortcolumn := Column.Index;
  FillListView;
end;

procedure TFrame_Variables.SearchEditChange(Sender: TObject);
begin
  FillListView;
  ClearFilterSpeedButton.Visible := SearchEdit.Text <> '';
end;

procedure TFrame_Variables.ClearFilterSpeedButtonClick(
  Sender: TObject);
begin
  SearchEdit.Clear;
end;

procedure TFrame_Variables.ListView1Change(Sender: TObject;
  Item: TListItem; Change: TItemChange);
var
  inf: varinfo_p;
begin
  if ListView1.Selected <> nil then
  begin
    inf := ListView1.Selected.Data;
    DeclEdit.Text := inf.varname + ': ' + inf.varvalue + ';';
    DeclEdit.Hint := DeclEdit.Text;
    DeclPanel.Hint := DeclEdit.Text;
    SynEdit1.varname := inf.varname;
  end;
end;

procedure TFrame_Variables.DeclPanelResize(Sender: TObject);
begin
  DeclEdit.Width := DeclPanel.Width - 16;
end;

end.
