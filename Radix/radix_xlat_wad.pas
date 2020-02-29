//
//  RAD: Recreation of the game "Radix - beyond the void"
//       powered by the DelphiDoom engine
//
//  Copyright (C) 1995 by Epic MegaGames, Inc.
//  Copyright (C) 1993-1996 by id Software, Inc.
//  Copyright (C) 2004-2020 by Jim Valavanis
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, inc., 59 Temple Place - Suite 330, Boston, MA
//  02111-1307, USA.
//
//  DESCRIPTION:
//   Convert RADIX.DAT to id-tech1 WAD
//
//------------------------------------------------------------------------------
//  Site: https://sourceforge.net/projects/rad-x/
//------------------------------------------------------------------------------

unit radix_xlat_wad;

interface

uses
  d_delphi;

procedure Radix2WAD(const fin, fout: string);

procedure Radix2Stream(const fin: string; const strm: TDStream);

procedure Radix2CSV(const fin: string; const pathout: string);

implementation

uses
  radix_defs,
  radix_palette,
  radix_patch,
  radix_level,
  radix_things,
  radix_bitmap,
  radix_font,
  r_defs,
  v_video,
  w_wadwriter,
  w_wad;

type
  TRadixToWADConverter = class(TObject)
  private
    wadwriter: TWadWriter;
    header: radixheader_t;
    f: TFile;
    lumps: Pradixlump_tArray;
    numlumps: integer;
    def_pal: packed array[0..767] of byte;
    def_palL: array[0..255] of LongWord;
    redfromblue_tr: array[0..255] of byte;
    greenfromblue_tr: array[0..255] of byte;
    yellowfromblue_tr: array[0..255] of byte;
    aliases: TDStringList;
    textures: TDStringList;
    markflats: PBooleanArray;
    numflats: integer;
  protected
    function ReadLump(const l: Pradixlump_tArray; const numl: integer;
      const lmp: string; var buf: pointer; var size: integer): boolean;
    function FindLump(const l: Pradixlump_tArray; const numl: integer;
       const lmp: string): integer;
    procedure Clear;
    function ReadHeader: boolean;
    function ReadDirectory: boolean;
    function GeneratePalette: boolean;
    function GenerateTranslationTables: boolean;
    function GenerateTextures(const pnames, texture1: string): boolean;
    function GenerateLevels: boolean;
    function GenerateCSVs(const path: string): boolean;
    function GenerateFlats: boolean;
    function GenerateGraphicWithOutPalette(const rname, wname: string; const solid: boolean; const opaqueindex: integer = -1): boolean;
    function GenerateGraphicWithPalette(const rname, wname: string; const solid: boolean): boolean;
    function GenerateOpaqueGraphicWithPalette(const rname, wname: string; const bgcolor: byte): boolean;
    function GenerateMainGraphics: boolean;
    function GenerateAdditionalGraphics: boolean;
    function GenerateSmallFont: boolean;
    function GenerateBigFonts: boolean;
    function GenerateDosFonts: boolean;
    function GenerateMenuTranslation: boolean;
    function GenerateSprites: boolean;
    function GenerateMusic: boolean;
    function GenerateCockpitOverlay: boolean;
    procedure WritePK3Entry;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Convert(const fname: string);
    procedure SaveToFile(const fname: string);
    procedure SaveToSream(const strm: TDStream);
  end;

constructor TRadixToWADConverter.Create;
begin
  f := nil;
  wadwriter := nil;
  lumps := nil;
  numlumps := 0;
  aliases := nil;
  textures := nil;
  markflats := nil;
  numflats := 0;
  Inherited;
end;

destructor TRadixToWADConverter.Destroy;
begin
  Clear;
  Inherited;
end;

procedure TRadixToWADConverter.Clear;
begin
  if wadwriter <> nil then
    wadwriter.Free;

  if f <> nil then
    f.Free;

  if aliases <> nil then
    aliases.Free;

  if textures <> nil then
    textures.Free;

  if markflats <> nil then
    memfree(pointer(markflats), numflats);

  if numlumps <> 0 then
  begin
    memfree(pointer(lumps), numlumps * SizeOf(radixlump_t));
    numlumps := 0;
  end;
end;

function TRadixToWADConverter.ReadLump(const l: Pradixlump_tArray; const numl: integer;
  const lmp: string; var buf: pointer; var size: integer): boolean;
var
  i: integer;
begin
  for i := 0 to numl - 1 do
    if radixlumpname(l[i]) = lmp then
    begin
      f.Seek(l[i].position, sFrombeginning);
      size := l[i].length;
      buf := malloc(size);
      f.Read(buf^, size);
      result := true;
      exit;
    end;
  result := false;
end;

function TRadixToWADConverter.FindLump(const l: Pradixlump_tArray; const numl: integer;
  const lmp: string): integer;
var
  i: integer;
begin
  for i := 0 to numl - 1 do
    if radixlumpname(l[i]) = lmp then
    begin
      result := i;
      exit;
    end;
  result := -1;
end;

function TRadixToWADConverter.ReadHeader: boolean;
var
  i: integer;
  s: string;
begin
  f.Seek(0, sFromBeginning);
  f.Read(header, SizeOf(radixheader_t));
  s := '';
  for i := 0 to 10 do
    s := s + header.id[i];
  result := s = 'NSRes:Radix';
end;

function TRadixToWADConverter.ReadDirectory: boolean;
begin
  numlumps := header.numlumps;
  lumps := mallocz(numlumps * SizeOf(radixlump_t));
  f.Seek(header.start, sFromBeginning);
  result := f.Read(lumps^, numlumps * SizeOf(radixlump_t)) = numlumps * SizeOf(radixlump_t);
end;

function TRadixToWADConverter.GeneratePalette: boolean;
var
  p: pointer;
  pal: PByteArray;
  size: integer;
  playpal: packed array[0..768 * 14 - 1] of byte;
  colormap: packed array[0..34 * 256 - 1] of byte;
  i: integer;
  r, g, b: LongWord;
begin
  result := ReadLump(lumps, numlumps, 'Palette[1]', p, size);
  if not result then
    exit;
  pal := p;
  RX_CreateDoomPalette(pal, @playpal, @colormap);

  // Keep def_pal AFTER RX_CreateDoomPalette call
  for i := 0 to 767 do
    def_pal[i] := pal[i];
  for i := 0 to 255 do
  begin
    r := def_pal[3 * i];
    if r > 255 then r := 255;
    g := def_pal[3 * i + 1];
    if g > 255 then g := 255;
    b := def_pal[3 * i + 2];
    if b > 255 then b := 255;
    def_palL[i] := (r shl 16) + (g shl 8) + (b);
  end;

  wadwriter.AddData('PLAYPAL', @playpal, SizeOf(playpal));
  wadwriter.AddData('COLORMAP', @colormap, SizeOf(colormap));
  memfree(p, size);
end;

function TRadixToWADConverter.GenerateTranslationTables: boolean;
var
  p1, p2, p3: pointer;
  pal1, pal2, pal3: PByteArray;
  size1, size2, size3: integer;
  ret1, ret2, ret3: boolean;
begin
  ret1 := ReadLump(lumps, numlumps, 'RedFromBluePal', p1, size1);
  pal1 := p1;

  ret2 := ReadLump(lumps, numlumps, 'GreenFromBluePal', p2, size2);
  pal2 := p2;

  ret3 := ReadLump(lumps, numlumps, 'YellowFromBluePal', p3, size3);
  pal3 := p3;

  result := ret1 and ret2 and ret3;

  if result then
  begin
    RX_CreateTranslation(@def_pal, pal1, @redfromblue_tr);
    wadwriter.AddData('TRN_RED', @redfromblue_tr, 256);
    RX_CreateTranslation(@def_pal, pal2, @greenfromblue_tr);
    wadwriter.AddData('TRN_GREE', @greenfromblue_tr, 256);
    RX_CreateTranslation(@def_pal, pal3, @yellowfromblue_tr);
    wadwriter.AddData('TRN_YELL', @yellowfromblue_tr, 256);
  end;

  memfree(p1, size1);
  memfree(p2, size2);
  memfree(p3, size3);
end;

function TRadixToWADConverter.GenerateTextures(const pnames, texture1: string): boolean;
var
  position: integer;
  bstart: integer;
  bnumlumps: word;
  blumps: Pradixbitmaplump_tArray;
  i: integer;
  buf: PByteArray;
  bufsize: integer;
  p: pointer;
  size: integer;
  stmp: string;
  mp, mt: TDMemoryStream;
  psize: integer;
  c8: char8_t;
  tex: maptexture_t;
  extraskypatch: mappatch_t;
  texname: string;
  foundsky: boolean;
begin
  i := FindLump(lumps, numlumps, 'WallBitmaps');
  if i < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  position := lumps[i].position;
  f.Seek(position, sFromBeginning);
  f.Read(bnumlumps, SizeOf(word));

  blumps := mallocz(bnumlumps * SizeOf(radixbitmaplump_t));

  // Keep flats after loading levels
  numflats := bnumlumps + 1;
  markflats := mallocz(numflats);

  f.Read(bstart, SizeOf(integer));
  f.Seek(bstart, sFromBeginning);
  f.Read(blumps^, bnumlumps * SizeOf(radixbitmaplump_t));

  wadwriter.AddSeparator('P_START');

  mp := TDMemoryStream.Create;  // PNAMES
  mt := TDMemoryStream.Create;  // TEXTURE1

  psize := bnumlumps + 7; // 1 stub + 3x2 skies

  // PNAMES header
  mp.Write(psize, SizeOf(integer));

  // TEXTURE1 header
  psize := psize - 3; // 3 less - count for double skies
  mt.Write(psize, SizeOf(integer));
  psize := 0;
  for i := 0 to bnumlumps do
  begin
    psize := (bnumlumps + 4) * 4 + 4 + i * SizeOf(maptexture_t);
    mt.Write(psize, SizeOf(integer));
  end;
  // Skies have two patches
  for i := 1 to 3 do
  begin
    psize := psize + SizeOf(maptexture_t);
    if i > 1 then
      psize := psize + SizeOf(mappatch_t);
    mt.Write(psize, SizeOf(integer));
  end;

  // Stub texture
  buf := mallocz(32 * 32);
  RX_CreateDoomPatch(buf, 32, 32, true, p, size);
  stmp := RX_WALL_PREFIX + '0000';
  wadwriter.AddData(stmp, p, size);
  memfree(p, size);

  // Save PNAMES entry
  c8 := stringtochar8(stmp);
  mp.Write(c8, 8);

  // Save TEXTURE1 entry
  ZeroMemory(@tex, SizeOf(maptexture_t));
  tex.name := c8;
  tex.width := 32;
  tex.height := 32;
  tex.patchcount := 1;
  tex.patches[0].patch := 0;
  mt.Write(tex, SizeOf(maptexture_t));

  memfree(pointer(buf), 32 * 32);

  for i := 0 to bnumlumps - 1 do
  begin
    buf := malloc(blumps[i].width * blumps[i].height);

    f.Seek(blumps[i].position, sFromBeginning);
    f.Read(buf^, blumps[i].width * blumps[i].height);

    RX_CreateDoomPatch(buf, blumps[i].width, blumps[i].height, true, p, size);
    if blumps[i].width = blumps[i].height then
      markflats[i + 1] := true;

    stmp := RX_WALL_PREFIX + IntToStrZFill(4, i + 1);
    wadwriter.AddData(stmp, p, size);
    memfree(p, size);

    // Save PNAMES entry
    c8 := stringtochar8(stmp);
    mp.Write(c8, 8);

    // Save TEXTURE1 entry
    ZeroMemory(@tex, SizeOf(maptexture_t));
    tex.name := c8;
    tex.width := blumps[i].width;
    tex.height := blumps[i].height;
    tex.patchcount := 1;
    tex.patches[0].patch := i + 1;
    mt.Write(tex, SizeOf(maptexture_t));

    texname := radixlumpname(blumps[i]);
    // Save PK3ENTRY entry
    aliases.Add(stmp + '=' + texname);

    // Save Texture name
    textures.Add(texname);

    memfree(pointer(buf), blumps[i].width * blumps[i].height);
  end;

  extraskypatch.originx := 256;
  extraskypatch.originy := 0;
  for i := 1 to 3 do
  begin
    foundsky := FindLump(lumps, numlumps, 'MainEpisodeImage[' + itoa(i) + ']') >= 0;
    if foundsky then
      texname := 'MainEpisodeImage[' + itoa(i) + ']'
    else
      texname := 'MainEpisodeImage[1]';
    if ReadLump(lumps, numlumps, texname, pointer(buf), bufsize) then
    begin
      RX_CreateDoomSkyPatch(buf, p, size);

      stmp := 'RSKY' + itoa(i);
      wadwriter.AddData(stmp, p, size);

      // Save PNAMES entry
      c8 := stringtochar8(stmp);
      mp.Write(c8, 8);

      // Save TEXTURE1 entry
      ZeroMemory(@tex, SizeOf(maptexture_t));
      tex.name := stringtochar8('SKY' + itoa(i));
      tex.width := PSmallIntArray(p)[0] * 2;
      tex.height := PSmallIntArray(p)[1];
      memfree(p, size);
      tex.patchcount := 2;
      tex.patches[0].patch := bnumlumps + 2 * i - 1;
      mt.Write(tex, SizeOf(maptexture_t));

      // Save PK3ENTRY entry
      if foundsky then
        aliases.Add(stmp + '=' + texname);

      // Save Texture name
      textures.Add('SKY' + itoa(i));

      memfree(pointer(buf), bufsize);
    end;

    if foundsky then
      texname := 'FillEpisodeImage[' + itoa(i) + ']'
    else
      texname := 'FillEpisodeImage[1]';
    if ReadLump(lumps, numlumps, texname, pointer(buf), bufsize) then
    begin
      RX_CreateDoomSkyPatch(buf, p, size);

      stmp := 'RSKY' + itoa(i) + 'B';
      wadwriter.AddData(stmp, p, size);

      // Save PNAMES entry
      c8 := stringtochar8(stmp);
      mp.Write(c8, 8);

      // Save TEXTURE1 entry - extra patch
      memfree(p, size);
      extraskypatch.patch := bnumlumps + 2 * i;
      mt.Write(extraskypatch, SizeOf(mappatch_t));

      // Save PK3ENTRY entry
      if foundsky then
        aliases.Add(stmp + '=' + texname);

      memfree(pointer(buf), bufsize);
    end;
  end;

  wadwriter.AddSeparator('P_END');

  wadwriter.AddData(texture1, mt.Memory, mt.Size);
  wadwriter.AddData(pnames, mp.Memory, mp.Size);

  psize := 0;
  wadwriter.AddData('TEXTURE2', @psize, 4);

  mp.Free;
  mt.Free;

  memfree(pointer(blumps), bnumlumps * SizeOf(radixbitmaplump_t));

end;

function TRadixToWADConverter.GenerateLevels: boolean;
var
  i, j: integer;
  rlevel: pointer;
  rsize: integer;
  ret: boolean;
begin
  result := false;

  for i := 1 to 3 do
    for j := 1 to 9 do
    begin
      if ReadLump(lumps, numlumps, 'WorldData[' + itoa(i) +'][' + itoa(j) + ']', rlevel, rsize) then
      begin
        ret := RX_CreateDoomLevel('E' + itoa(i) + 'M' + itoa(j), rlevel, rsize, markflats, wadwriter);
        result := result or ret;
        memfree(rlevel, rsize);
      end;
    end;
end;

function TRadixToWADConverter.GenerateCSVs(const path: string): boolean;
var
  i, j: integer;
  rlevel: pointer;
  rsize: integer;
  ret: boolean;

  procedure CreateAll(const prefix: string);
  var
    ii, jj, kk: integer;
    lsts: array[1..3,1..9] of TDStringList;
    l: TDStringList;
    finp: string;
    apath: string;
    header: string;
  begin
    apath := path;
    if apath <> '' then
      if apath[length(apath)] <> '\' then
        apath := apath + '\';
    header := '';
    for ii := 1 to 3 do
      for jj := 1 to 9 do
      begin
        lsts[ii, jj] := TDStringList.Create;
        finp := apath + '\' + 'E' + itoa(ii) + 'M' + itoa(jj) + '_' + prefix + '.txt';
        if fexists(finp) then
        begin
          lsts[ii, jj].LoadFromFile(finp);
          if lsts[ii, jj].Count > 0 then
          begin
            header := 'level' + ',' + lsts[ii, jj].Strings[0];
            lsts[ii, jj].Delete(0);
          end;
        end;
      end;
    l := TDStringList.Create;
    l.Add(header);
    for ii := 1 to 3 do
      for jj := 1 to 9 do
      begin
        for kk := 0 to lsts[ii, jj].Count - 1 do
          l.Add('E' + itoa(ii) + 'M' + itoa(jj) + ',' + lsts[ii, jj].Strings[kk]);
        lsts[ii, jj].Free;
      end;
    l.SaveToFile(apath + '\' + 'ALL' + '_' + prefix + '.txt');
    l.Free;
  end;

begin
  result := true;

  for i := 1 to 3 do
    for j := 1 to 9 do
    begin
      if ReadLump(lumps, numlumps, 'WorldData[' + itoa(i) +'][' + itoa(j) + ']', rlevel, rsize) then
      begin
        ret := RX_CreateRadixMapCSV('E' + itoa(i) + 'M' + itoa(j), path, rlevel, rsize);
        result := result or ret;
        memfree(rlevel, rsize);
      end;
    end;

  CreateAll('sectors');
  CreateAll('sprites');
  CreateAll('things');
  CreateAll('walls');
  CreateAll('triggers');
  CreateAll('gridtable1');
  CreateAll('gridtable2');
end;


function TRadixToWADConverter.GenerateFlats: boolean;
var
  position: integer;
  bstart: integer;
  bnumlumps: word;
  blumps: Pradixbitmaplump_tArray;
  i: integer;
  buf: PByteArray;
  stmp: string;
  c: byte;
  t: integer;
begin
  i := FindLump(lumps, numlumps, 'WallBitmaps');
  if i < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  position := lumps[i].position;
  f.Seek(position, sFromBeginning);
  f.Read(bnumlumps, SizeOf(word));

  blumps := mallocz(bnumlumps * SizeOf(radixbitmaplump_t));

  f.Read(bstart, SizeOf(integer));
  f.Seek(bstart, sFromBeginning);
  f.Read(blumps^, bnumlumps * SizeOf(radixbitmaplump_t));

  wadwriter.AddSeparator('F_START');

  t := FindLump(lumps, numlumps, 'TileBitmap');
  if t >= 0 then
    if lumps[t].length = 4100 then
    begin
      buf := malloc(4096);

      f.Seek(lumps[t].position + 4, sFromBeginning);
      f.Read(buf^, 4096);

      for i := 0 to 4095 do
        if buf[i] = 0 then
          buf[i] := 63;
          
      stmp := RX_FLAT_PREFIX + '0000';
      wadwriter.AddData(stmp, buf, 4096);

      memfree(pointer(buf), 4096);
    end;

  for i := 0 to bnumlumps - 1 do
    if markflats[i + 1] then
    begin
      buf := malloc(blumps[i].width * blumps[i].height);

      f.Seek(blumps[i].position, sFromBeginning);
      f.Read(buf^, blumps[i].width * blumps[i].height);

      stmp := RX_FLAT_PREFIX + IntToStrZFill(4, i + 1);
      wadwriter.AddData(stmp, buf, blumps[i].width * blumps[i].height);

      memfree(pointer(buf), blumps[i].width * blumps[i].height);
    end;

  // Create F_SKY1
  buf := malloc(64 * 64);
  c := V_FindAproxColorIndex(@def_palL, 77 shl 16 + 179 shl 8 + 255);
  memset(buf, c, 64 * 64);
  wadwriter.AddData('F_SKY1', buf, 64 * 64);
  memfree(pointer(buf), 64 * 64);

  wadwriter.AddSeparator('F_END');

  memfree(pointer(blumps), bnumlumps * SizeOf(radixbitmaplump_t));
end;

function TRadixToWADConverter.GenerateGraphicWithOutPalette(const rname, wname: string;
  const solid: boolean; const opaqueindex: integer = -1): boolean;
var
  lump: integer;
  buf: pointer;
  bufsize: integer;
  p: pointer;
  i, size: integer;
  pb: PByteArray;
begin
  lump := FindLump(lumps, numlumps, rname);
  if lump < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  bufsize := lumps[lump].length;
  buf := malloc(bufsize);
  f.Seek(lumps[lump].position, sFromBeginning);
  f.Read(buf^, bufsize);

  if not solid and (opaqueindex >= 0) then
  begin
    pb := buf;
    for i := 4 to bufsize - 1 do
    begin
      if pb[i] = opaqueindex then
        pb[i] := 254
      else if pb[i] = 254 then
        pb[i] := 252;
    end;
  end;

  RX_CreateDoomPatchFromLumpData(buf, solid, p, size);

  wadwriter.AddData(wname, p, size);
  memfree(p, size);
  memfree(buf, bufsize);
end;

function TRadixToWADConverter.GenerateGraphicWithPalette(const rname, wname: string; const solid: boolean): boolean;
var
  lump: integer;
  buf: pointer;
  bufsize: integer;
  p: pointer;
  size: integer;
begin
  lump := FindLump(lumps, numlumps, rname);
  if lump < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  bufsize := lumps[lump].length;
  buf := malloc(size);
  f.Seek(lumps[lump].position, sFromBeginning);
  f.Read(buf^, bufsize);

  RX_CreateDoomPatchFromLumpDataPal(buf, solid, @def_palL, p, size);

  wadwriter.AddData(wname, p, size);
  memfree(p, size);
  memfree(buf, bufsize);
end;

function TRadixToWADConverter.GenerateOpaqueGraphicWithPalette(const rname, wname: string; const bgcolor: byte): boolean;
var
  lump: integer;
  buf: pointer;
  bufsize: integer;
  p: pointer;
  size: integer;
begin
  lump := FindLump(lumps, numlumps, rname);
  if lump < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  bufsize := lumps[lump].length;
  buf := malloc(size);
  f.Seek(lumps[lump].position, sFromBeginning);
  f.Read(buf^, bufsize);

  RX_CreateOpaqueDoomPatchFromLumpDataPal(buf, bgcolor, @def_palL, p, size);

  wadwriter.AddData(wname, p, size);
  memfree(p, size);
  memfree(buf, bufsize);
end;

function TRadixToWADConverter.GenerateMainGraphics: boolean;
var
  rname, wname: string;
  i: integer;
begin
  for i := 1 to 99 do
  begin
    rname := 'OrderInfo[' + itoa(i) + ']';
    wname := 'HELP' + IntToStrzFill(2, i);
    if not GenerateGraphicWithOutPalette(rname, wname, true) then
      break;
    aliases.Add(wname + '=' + rname);
  end;

  rname := 'MainTitle';
  wname := 'TITLEPIC';
  GenerateGraphicWithPalette(rname, wname, true);
  aliases.Add(wname + '=' + rname);

  rname := 'DemoDecal';
  wname := 'M_RADIX';
  GenerateOpaqueGraphicWithPalette(rname, wname, 0);
  aliases.Add(wname + '=' + rname);

  result := true;
end;

function TRadixToWADConverter.GenerateAdditionalGraphics: boolean;
var
  i, j, patchid: integer;

  procedure AddGraphicWithPalette(const rname: string);
  var
    wname: string;
  begin
    wname := 'RADIX' + IntToStrzFill(3, patchid);
    if GenerateGraphicWithPalette(rname, wname, true) then
    begin
      aliases.Add(wname + '=' + rname);
      inc(patchid);
    end;
  end;

  procedure AddGraphicWithOutPalette(const rname: string; const opaqueindex: integer = -1);
  var
    wname: string;
  begin
    wname := 'RADIX' + IntToStrzFill(3, patchid);
    if GenerateGraphicWithOutPalette(rname, wname, false, opaqueindex) then
    begin
      aliases.Add(wname + '=' + rname);
      inc(patchid);
    end;
  end;

begin
  result := true;

  patchid := 1;

  AddGraphicWithPalette('SelectSkill');
  AddGraphicWithPalette('SkillButton1');
  AddGraphicWithPalette('SkillButton2');
  AddGraphicWithPalette('SkillButton3');
  AddGraphicWithPalette('SkillButton4');
  AddGraphicWithPalette('PlayerNameBox');
  AddGraphicWithPalette('SelectEpisode');
  AddGraphicWithPalette('EpisodeButton1');
  AddGraphicWithPalette('EpisodeButton2');
  AddGraphicWithPalette('EpisodeButton3');
  AddGraphicWithPalette('SkillPicture1');
  AddGraphicWithPalette('SkillPicture2');
  AddGraphicWithPalette('SkillPicture3');
  AddGraphicWithPalette('SkillPicture4');
  AddGraphicWithPalette('TopTenScreen');
  AddGraphicWithPalette('NetworkMenu');
  AddGraphicWithPalette('NetworkMenuOverlay');
  AddGraphicWithPalette('StatsScreen');
  AddGraphicWithPalette('BriefScreen');
  AddGraphicWithPalette('DebriefScreen1');
  AddGraphicWithPalette('DebriefScreen2');
  AddGraphicWithPalette('DebriefScreen3');
  AddGraphicWithPalette('NetDebriefScreen');
  AddGraphicWithPalette('NetFlag');
  AddGraphicWithPalette('StartLogo');
  AddGraphicWithPalette('MainMenu');
  AddGraphicWithPalette('MainMenuButton1');
  AddGraphicWithPalette('MainMenuButton2');
  AddGraphicWithPalette('MainMenuButton3');
  AddGraphicWithPalette('MainMenuButton4');
  AddGraphicWithPalette('MainMenuButton5');
  AddGraphicWithPalette('MainMenuButton6');
  AddGraphicWithPalette('MainMenuButton7');
  AddGraphicWithPalette('MainMenuButton8');
  AddGraphicWithPalette('OptionMenu');
  AddGraphicWithPalette('Option1');
  AddGraphicWithPalette('Option2');
  AddGraphicWithPalette('Option3');
  AddGraphicWithPalette('NeuralLogo');

  AddGraphicWithOutPalette('ArmourBar');
  AddGraphicWithOutPalette('BackViewOn', 0);
  AddGraphicWithOutPalette('CockpitNumOn', 0);
  AddGraphicWithOutPalette('CockpitNumUse', 0);
  AddGraphicWithOutPalette('CockPitRadar');
  AddGraphicWithOutPalette('CrossHair', 0);
  AddGraphicWithOutPalette('CrossLock1', 0);
  AddGraphicWithOutPalette('CrossLock2', 0);
  AddGraphicWithOutPalette('CrossLock3', 0);
  AddGraphicWithOutPalette('CrossLock4', 0);
  AddGraphicWithOutPalette('CrossLock5', 0);
  AddGraphicWithOutPalette('CrossLock6', 0);
  AddGraphicWithOutPalette('EnergyBar');
  AddGraphicWithOutPalette('EnhancedEPCWeaponPicture');
  AddGraphicWithOutPalette('HelpScreen');
  AddGraphicWithOutPalette('HelpScreen2');
  AddGraphicWithOutPalette('LeftArrow', 0);
  AddGraphicWithOutPalette('MissionBack');
  AddGraphicWithOutPalette('MissionBegin');
  AddGraphicWithOutPalette('MissionForward');
  AddGraphicWithOutPalette('MissionLoad');
  AddGraphicWithOutPalette('MissionPause');
  AddGraphicWithOutPalette('MissionQuit');
  AddGraphicWithOutPalette('MissionReverse');
  AddGraphicWithOutPalette('MissionSave');
  AddGraphicWithOutPalette('MissionScreen');
  AddGraphicWithOutPalette('MissionStats');
  AddGraphicWithOutPalette('NetworkChatScreen');
  AddGraphicWithOutPalette('PlasmaIcon', 0);
  AddGraphicWithOutPalette('PowerUpIcon[1]', 0);
  AddGraphicWithOutPalette('PowerUpIcon[2]', 0);
  AddGraphicWithOutPalette('PowerUpIcon[3]', 0);
  AddGraphicWithOutPalette('PowerUpIcon[4]', 0);
  AddGraphicWithOutPalette('PowerUpIcon[5]', 0);
  AddGraphicWithOutPalette('RadarOverlay');
  AddGraphicWithOutPalette('RightArrow', 0);
  AddGraphicWithOutPalette('SaveLoadScreen');
  AddGraphicWithOutPalette('ShieldBar');
  AddGraphicWithOutPalette('SmallCrossHair', 0);
  AddGraphicWithOutPalette('SmallCrossLock', 0);
  AddGraphicWithOutPalette('StatAmmo1');
  AddGraphicWithOutPalette('StatAmmo2');
  AddGraphicWithOutPalette('StatAmmo3');
  AddGraphicWithOutPalette('StatAmmo4');
  AddGraphicWithOutPalette('StatAmmo5');
  AddGraphicWithOutPalette('StatAmmo6');
  AddGraphicWithOutPalette('StatAmmo7');
  AddGraphicWithOutPalette('StatAmmo8');
  AddGraphicWithOutPalette('StatusBarFlag');
  AddGraphicWithOutPalette('StatusBarImage');
  AddGraphicWithOutPalette('StatusBarKill');
  AddGraphicWithOutPalette('SuperEPCWeaponPicture');
  AddGraphicWithOutPalette('ThreatOffMap');
  AddGraphicWithOutPalette('ThreatOnMap');
  AddGraphicWithOutPalette('TileBitmap');
  AddGraphicWithOutPalette('Weapon1Image');
  AddGraphicWithOutPalette('Weapon2Image');
  AddGraphicWithOutPalette('Weapon3Image');
  AddGraphicWithOutPalette('Weapon4Image');
  AddGraphicWithOutPalette('Weapon5Image');
  AddGraphicWithOutPalette('Weapon6Image');
  AddGraphicWithOutPalette('Weapon7Image');
  AddGraphicWithOutPalette('WeaponNumOff');
  AddGraphicWithOutPalette('WeaponNumOn');
  AddGraphicWithOutPalette('WeaponNumUse');

  for i := 1 to 3 do
    for j := 1 to 9 do
    begin
      AddGraphicWithOutPalette('MissionPrimary[' + itoa(i) + '][' + itoa(j) + ']');
      AddGraphicWithOutPalette('MissionSecondary[' + itoa(i) + '][' + itoa(j) + ']');
    end;
end;

function TRadixToWADConverter.GenerateSmallFont: boolean;
var
  lump: integer;
  buf: pointer;
  bufsize: integer;
  imginp: PByteArray;
  imgout: PByteArray;
  p: pointer;
  size: integer;
  fnt: string;
  idx: integer;
  ch: char;
  found: boolean;
begin
  lump := FindLump(lumps, numlumps, 'SmallFont');
  if lump < 0 then
  begin
    result := false;
    exit;
  end;
  if lumps[lump].length <> 2222 then
  begin
    result := false;
    exit;
  end;
  result := true;

  bufsize := lumps[lump].length;
  buf := malloc(lumps[lump].length);
  f.Seek(lumps[lump].position, sFromBeginning);
  f.Read(buf^, bufsize);

  imginp := @PByteArray(buf)[8];
  RX_ColorReplace(imginp, 368, 6, 0, 254);
  RX_ColorReplace(imginp, 368, 6, 1, 254);
  RX_ColorReplace(imginp, 368, 6, 6, 254);
  RX_ColorReplace(imginp, 368, 6, 28, 254);

  RX_CreateDoomPatch(imginp, 368, 6, false, p, size, 0, 0);

  wadwriter.AddData('SMALLFNT', p, size);
  memfree(p, size);

  imgout := malloc(5 * 6);
  memset(imgout, 254, 5 * 6);
  fnt := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.?[]!:;"`,-0123456789_';


  for ch := Chr(33) to Chr(128) do
  begin
    found := false;
    for idx := 1 to length(fnt) do
      if fnt[idx] <> ' ' then
        if fnt[idx] = ch then
        begin
          RX_BltImageBuffer(imginp, 368, 6, imgout, (idx - 1) * 5, idx * 5 - 2, 0, 5);
          RX_ColorReplace(imgout, 5, 6, 0, 254);
          RX_CreateDoomPatch(imgout, 5, 6, false, p, size, 0, 0);

          wadwriter.AddData('FNTA' + IntToStrzFill(3, Ord(ch)), p, size);
          memfree(p, size);
          fnt[idx] := ' ';
          found := true;
          break;
        end;
    if not found then
      if not (ch in ['%', '(', ')', '*', '+', '#', '/', '<', '=', '>']) then
      begin
        memset(imgout, 254, 5 * 6);
        RX_CreateDoomPatch(imgout, 5, 6, false, p, size, 0, 0);
        wadwriter.AddData('FNTA' + IntToStrzFill(3, Ord(ch)), p, size);
        memfree(p, size);
      end;
  end;

  memfree(pointer(imgout), 4 * 6);
  memfree(buf, bufsize);
end;

function TRadixToWADConverter.GenerateBigFonts: boolean;
const
  NUM_BIG_FONT_COLORS = 3;
var
  imgsize: integer;
  imginp: PByteArray;
  imgout: PByteArray;
  imgoutw: PByteArray;
  p: pointer;
  size: integer;
  i: integer;
  ch: char;
  COLORS: array[0..NUM_BIG_FONT_COLORS - 1] of LongWord;
  cidx: integer;
  c: LongWord;
  r1, g1, b1: LongWord;
  r, g, b: LongWord;
  x, y: integer;
  fnt: string;
  fidx: integer;
  widx: integer;
  w: integer;
begin
  result := true;

  imgsize := SizeOf(BIG_FONT_BUFFER);
  imginp := malloc(imgsize);

  COLORS[0] := $800000;
  COLORS[1] := $808080;
  COLORS[2] := $C47C0C;

  fnt := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890`~!@#$%^&*()-_=+*/<>.,\[]|;:''"{}';
  imgout := malloc(18 * 21);
  for cidx := 0 to NUM_BIG_FONT_COLORS - 1 do
  begin
    r1 := (COLORS[cidx] shr 16) and $FF;
    g1 := (COLORS[cidx] shr 8) and $FF;
    b1 := COLORS[cidx] and $FF;
    for i := 0 to imgsize - 1 do
    begin
      if BIG_FONT_BUFFER[i] = 0 then
        imginp[i] := 254
      else
      begin
        r := round(r1 * BIG_FONT_BUFFER[i] / 256);
        if r > 255 then
          r := 255;
        g := round(g1 * BIG_FONT_BUFFER[i] / 256);
        if g > 255 then
          g := 255;
        b := round(b1 * BIG_FONT_BUFFER[i] / 256);
        if b > 255 then
          b := 255;
        c := r shl 16 + g shl 8 + b;
        imginp[i] := V_FindAproxColorIndex(@def_palL, c, 0, 253);
        if def_palL[imginp[i]] = 0 then
          imginp[i] := 254;
      end;
    end;

    for ch := Chr(33) to Chr(128) do
    begin
      fidx := Pos(ch, fnt);
      if fidx > 0 then
      begin
        x := 0;
        y := 4 + (fidx - 1) * 21;
        RX_BltImageBuffer(imginp, 18, 1984, imgout, x, x + 17, y, y + 20);
        // Right trim image
        widx := 18 * 21 - 1;
        while widx > 0 do
        begin
          if imgout[widx] <> 254 then
            break;
          dec(widx);
        end;
        if widx < 16 * 21 then
        begin
          w := (widx div 21) + 1;
          imgoutw := malloc(21 * w);
          memcpy(imgoutw, imgout, w * 21);
          RX_CreateDoomPatch(imgoutw, w, 21, false, p, size, 4, 1);
          memfree(pointer(imgoutw), 21 * w);
        end
        else
          RX_CreateDoomPatch(imgout, 18, 21, false, p, size, 4, 1);
      end
      else
      begin
        memset(imgout, 254, 18 * 21);
        RX_CreateDoomPatch(imgout, 5, 21, false, p, size, 4, 1);
      end;
      wadwriter.AddData('BIGF' + Chr(Ord('A') + cidx) + IntToStrzFill(3, Ord(ch)), p, size);
      memfree(p, size);
    end;
  end;

  memfree(pointer(imginp), imgsize);
  memfree(pointer(imgout), 18 * 21);
end;

// Generate DOS font in various colors
function TRadixToWADConverter.GenerateDosFonts: boolean;
const
  NUM_DOS_FONT_COLORS = 2;
var
  imgsize: integer;
  imginp: PByteArray;
  imgout: PByteArray;
  p: pointer;
  size: integer;
  i, j: integer;
  ch: char;
  COLORS: array[0..NUM_DOS_FONT_COLORS - 1] of LongWord;
  cidx: integer;
  c: LongWord;
  r1, g1, b1: LongWord;
  r, g, b: LongWord;
  x, y, fpos: integer;
begin
  result := true;

  COLORS[0] := 192 shl 16 + 14 shl 8 + 14 shl 8;
  COLORS[1] := $FFFFFF;

  // Big dos font
  imgsize := $10000;
  imginp := malloc(imgsize);

  imgout := malloc(14 * 14);
  for cidx := 0 to NUM_DOS_FONT_COLORS - 1 do
  begin
    r1 := (COLORS[cidx] shr 16) and $FF;
    g1 := (COLORS[cidx] shr 8) and $FF;
    b1 := COLORS[cidx] and $FF;
    for i := 0 to imgsize - 1 do
    begin
      if DOS_FONT_BUFFER[i] = 0 then
        imginp[i] := 254
      else
      begin
        r := round(r1 * DOS_FONT_BUFFER[i] / 256);
        if r > 255 then
          r := 255;
        g := round(g1 * DOS_FONT_BUFFER[i] / 256);
        if g > 255 then
          g := 255;
        b := round(b1 * DOS_FONT_BUFFER[i] / 256);
        if b > 255 then
          b := 255;
        c := r shl 16 + g shl 8 + b;
        imginp[i] := V_FindAproxColorIndex(@def_palL, c, 0, 253);
        if def_palL[imginp[i]] = 0 then
          imginp[i] := 254;
      end;
    end;

    for ch := Chr(33) to Chr(128) do
    begin
      x := Ord(ch) mod 16;
      y := Ord(ch) div 16;
      RX_BltImageBuffer(imginp, 256, 256, imgout, x * 16 + 1, x * 16 + 14, y * 16 + 2, y * 16 + 15);
      RX_CreateDoomPatch(imgout, 14, 14, false, p, size, 3, 1);
      wadwriter.AddData('DOSF' + Chr(Ord('A') + cidx) + IntToStrzFill(3, Ord(ch)), p, size);
      memfree(p, size);
    end;
  end;

  memfree(pointer(imginp), imgsize);
  memfree(pointer(imgout), 14 * 14);

  // Small dos font
  imgsize := 128 * 128;
  imginp := malloc(imgsize);

  imgout := malloc(8 * 8);
  for cidx := 0 to NUM_DOS_FONT_COLORS - 1 do
  begin
    r1 := (COLORS[cidx] shr 16) and $FF;
    g1 := (COLORS[cidx] shr 8) and $FF;
    b1 := COLORS[cidx] and $FF;
    for i := 0 to imgsize - 1 do
    begin
      if SMALL_DOS_FONT_BUFFER[i] = 0 then
        imginp[i] := 254
      else
      begin
        r := round(r1 * SMALL_DOS_FONT_BUFFER[i] / 256);
        if r > 255 then
          r := 255;
        g := round(g1 * SMALL_DOS_FONT_BUFFER[i] / 256);
        if g > 255 then
          g := 255;
        b := round(b1 * SMALL_DOS_FONT_BUFFER[i] / 256);
        if b > 255 then
          b := 255;
        c := r shl 16 + g shl 8 + b;
        imginp[i] := V_FindAproxColorIndex(@def_palL, c, 0, 253);
        if def_palL[imginp[i]] = 0 then
          imginp[i] := 254;
      end;
    end;

    for ch := Chr(33) to Chr(128) do
    begin
      x := (Ord(ch) - 1) mod 16;
      y := (Ord(ch) - 1) div 16;
      for j := 0 to 7 do
      begin
        fpos := x * 8 + (y * 8 + j) * 128;
        for i := 0 to 7 do
        begin
          imgout[i * 8 + j] := imginp[fpos];
          inc(fpos);
        end;
      end;
      RX_CreateDoomPatch(imgout, 8, 8, false, p, size, 0, 0);
      wadwriter.AddData('DOSS' + Chr(Ord('A') + cidx) + IntToStrzFill(3, Ord(ch)), p, size);
      memfree(p, size);
    end;
  end;

  memfree(pointer(imginp), imgsize);
  memfree(pointer(imgout), 8 * 8);
end;

function TRadixToWADConverter.GenerateMenuTranslation: boolean;
var
  trn: packed array[0..255] of byte;
  i: integer;
begin
  result := true;
  for i := 0 to 255 do
    trn[i] := i;
  for i := 0 to 15 do
    trn[208 + i] := 128 + i;
  wadwriter.AddData('TRN_MENU', @trn, 256);
end;

type
  spriteinfo_t = record
    rname: string[32];
    dname: string[8];
    translation: PByteArray;
    xoffs, yoffs: integer;
    centeroffs: boolean;
    defaultoffs: boolean;
  end;
  Pspriteinfo_t = ^spriteinfo_t;

function TRadixToWADConverter.GenerateSprites: boolean;
var
  position: integer;
  bstart: integer;
  bnumlumps: word;
  blumps: Pradixbitmaplump_tArray;
  bl: Pradixbitmaplump_t;
  i, j: integer;
  buf: PByteArray;
  stmp: string;
  SPRITEINFO: array[0..1000] of spriteinfo_t;
  spr: Pspriteinfo_t;
  numsprinfo: integer;
  bmp: TRadixBitmap;
  rcol: radixcolumn_t;
  pc: Pradixcolumn_tArray;
  x, y, z: integer;
  p: pointer;
  size: integer;

  function remove_underline(const s: string): string;
  var
    ii: integer;
  begin
    result := '';
    for ii := 1 to length(s) do
      if s[ii] <> '_' then
        result := result + s[ii];
  end;

  procedure MakeNonRotatingSprite(const rprefix: string; const r_id: integer;
    const numframes: integer; const trans: PByteArray = nil;
    const xofs: integer = -255; const yofs: integer = -255;
    const cofs: boolean = true; const defofs: boolean = true);
  var
    ii: integer;
  begin
    for ii := 1 to numframes do
    begin
      spr.rname := rprefix + '_' + itoa(ii);
      spr.dname := 'XR' + IntToStrzFill(2, r_id) + Chr(Ord('A') + ii - 1) + '0';
      spr.translation := trans;
      spr.xoffs := xofs;
      spr.yoffs := yofs;
      spr.centeroffs := cofs;
      spr.defaultoffs := defofs;
      inc(spr);
      inc(numsprinfo);
    end;
  end;

  procedure MakeRotatingSprite(const rprefix: string; const r_id: integer;
    const numframes: integer; const trans: PByteArray = nil;
    const xofs: integer = -255; const yofs: integer = -255;
    const cofs: boolean = true; const defofs: boolean = true);
  var
    ii: integer;
    jj: integer;
  begin
    for ii := 1 to numframes do
      for jj := 1 to 8 do
      begin
        spr.rname := rprefix + '_' + itoa(jj + (ii - 1) * 8);
        spr.dname := 'XR' + IntToStrzFill(2, r_id) + Chr(Ord('A') + ii - 1) + itoa(jj);
        spr.translation := trans;
        spr.xoffs := xofs;
        spr.yoffs := yofs;
        spr.centeroffs := cofs;
        spr.defaultoffs := defofs;
        inc(spr);
        inc(numsprinfo);
      end;
  end;

  procedure MakeOneSprite(const rname: string; const r_id: integer;
    const trans: PByteArray = nil;
    const xofs: integer = -255; const yofs: integer = -255;
    const cofs: boolean = true; const defofs: boolean = true);
  begin
    spr.rname := rname;
    spr.dname := 'XR' + IntToStrzFill(2, r_id) + 'A0';
    spr.translation := trans;
    spr.xoffs := xofs;
    spr.yoffs := yofs;
    spr.centeroffs := cofs;
    spr.defaultoffs := defofs;
    inc(spr);
    inc(numsprinfo);
  end;

begin
  i := FindLump(lumps, numlumps, 'ObjectBitmaps');
  if i < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;

  position := lumps[i].position;
  f.Seek(position, sFromBeginning);
  f.Read(bnumlumps, SizeOf(word));

  blumps := mallocz(bnumlumps * SizeOf(radixbitmaplump_t));

  f.Read(bstart, SizeOf(integer));
  f.Seek(bstart, sFromBeginning);
  f.Read(blumps^, bnumlumps * SizeOf(radixbitmaplump_t));

  wadwriter.AddSeparator('S_START');


  numsprinfo := 0;

  spr := @SPRITEINFO[0];

  // MT_FULLSHIED
  MakeNonRotatingSprite('FullShield', _MTRX_FULLSHIED, 3);

  // MT_FULLENERGY
  MakeNonRotatingSprite('FullEnergy', _MTRX_FULLENERGY, 3);

  // MT_SUPERCHARGE
  MakeNonRotatingSprite('SuperCharge', _MTRX_SUPERCHARGE, 3);

  // MT_RAPIDSHIELD
  MakeNonRotatingSprite('RapidShld.Recharger', _MTRX_RAPIDSHIELD, 3);

  // MT_RAPIDENERGY
  MakeNonRotatingSprite('RapidEngy.Energizer', _MTRX_RAPIDENERGY, 3);

  // MT_MANEUVERJETS
  MakeNonRotatingSprite('ManeuveringJets', _MTRX_MANEUVERJETS, 3);

  // MT_NIGHTVISION
  MakeNonRotatingSprite('NightVisionSys', _MTRX_NIGHTVISION, 3);

  // MT_PLASMABOMB
  MakeNonRotatingSprite('PlasmaBomb', _MTRX_PLASMABOMB, 3);

  // MT_ALDS
  MakeNonRotatingSprite('A.L.D.S', _MTRX_ALDS, 3);

  // MT_ULTRASHIELDS
  MakeNonRotatingSprite('GodMode', _MTRX_ULTRASHIELDS, 3);

  // MT_LEVEL2NEUTRONCANNONS
  MakeNonRotatingSprite('LaserCannons', _MTRX_LEVEL2NEUTRONCANNONS, 3);

  // MT_STANDARDEPC
  MakeNonRotatingSprite('ExplosiveCannon', _MTRX_STANDARDEPC, 3);

  // MT_LEVEL1PLASMASPREADER
  MakeNonRotatingSprite('PlasmaCannon', _MTRX_LEVEL1PLASMASPREADER, 3);

  // MT_NUCLEARCAPABILITY
  MakeNonRotatingSprite('NuclearWeaponSystem', _MTRX_NUCLEARCAPABILITY, 3);

  // MT_MISSILECAPABILITY
  MakeNonRotatingSprite('SeekingMissileSystem', _MTRX_MISSILECAPABILITY, 3);

  // MT_TORPEDOCAPABILITY
  MakeNonRotatingSprite('PhaseTorpedoSystem', _MTRX_TORPEDOCAPABILITY, 3);

  // MT_GRAVITYDEVICE
  MakeNonRotatingSprite('GravityWaveDevice', _MTRX_GRAVITYDEVICE, 3);

  // MT_250SHELLS
  MakeNonRotatingSprite('250ShellPack', _MTRX_250SHELLS, 3);

  // MT_500SHELLS
  MakeNonRotatingSprite('500ShellPack', _MTRX_500SHELLS, 3);

  // MT_1000SHELLS
  MakeNonRotatingSprite('1000ShellPack', _MTRX_1000SHELLS, 3);

  // MT_4NUKES
  MakeNonRotatingSprite('5Nukes', _MTRX_4NUKES, 3);

  // MT_10NUKES
  MakeNonRotatingSprite('25Nukes', _MTRX_10NUKES, 3);

  // MT_15TORPEDOES
  MakeNonRotatingSprite('10Torps', _MTRX_15TORPEDOES, 3);

  // MT_75TORPEDOES
  MakeNonRotatingSprite('50Torps', _MTRX_75TORPEDOES, 3);

  // MT_20MISSILES
  MakeNonRotatingSprite('20Missiles', _MTRX_20MISSILES, 3);

  // MT_50MISSILES
  MakeNonRotatingSprite('50Missiles', _MTRX_50MISSILES, 3);

  // MT_BOOMPACK
  MakeNonRotatingSprite('BoomPack', _MTRX_BOOMPACK, 3);

  // MT_BIOMINE1
  MakeNonRotatingSprite('WeakBiomine', _MTRX_BIOMINE1, 3);

  // MT_BIOMINE2
  MakeNonRotatingSprite('PowerBiomine', _MTRX_BIOMINE2, 3);

  // MT_ALIENFODDER
  MakeRotatingSprite('AlienFodder', _MTRX_ALIENFODDER, 3, nil, 68, 101, false, false);

  // MT_DEFENCEDRONE_STUB1
  MakeRotatingSprite('DroneB', _MTRX_DEFENCEDRONE_STUB1, 1, nil, 63, 67, false, false);

  // MT_DEFENCEDRONE_STUB2
  MakeRotatingSprite('DroneB', _MTRX_DEFENCEDRONE_STUB2, 1, nil, 63, 67, false, false);

  // MT_BATTLEDRONE1
  MakeRotatingSprite('DroneA', _MTRX_BATTLEDRONE1, 1, nil, 91, 50, false, false);

  // MT_MISSILEBOAT
  MakeRotatingSprite('DroneC', _MTRX_MISSILEBOAT, 1, nil, 83, 68, false, false);

  // MT_STORMBIRDHEAVYBOMBER
  MakeRotatingSprite('HeavyFighter', _MTRX_STORMBIRDHEAVYBOMBER, 1, nil, 86, 54, false, false);

  // MT_SKYFIREASSULTFIGHTER
  MakeRotatingSprite('LightAssault', _MTRX_SKYFIREASSULTFIGHTER, 1, nil, 62, 51, false, false);

  // MT_SPAWNER
  MakeRotatingSprite('Spawner', _MTRX_SPAWNER, 1, nil, 146, 154, false, false);

  // MT_EXODROID
  MakeRotatingSprite('ExoDroid', _MTRX_EXODROID, 3, nil, 113, 188, false, false);

  // MT_SNAKEDEAMON
  MakeNonRotatingSprite('SnakeDemonBadassHead', _MTRX_SNAKEDEAMON, 3, nil, 57, 109, false, false);

  // MT_MINE
  MakeNonRotatingSprite('Airmine', _MTRX_MINE, 3, nil, 51, 93, false, false);

  // MT_ROTATINGRADAR1
  MakeRotatingSprite('RadarDish', _MTRX_ROTATINGRADAR1, 1, nil, 53, 91, false, false);

  // MT_SHIELDGENERATOR1
  MakeNonRotatingSprite('ShieldGen', _MTRX_SHIELDGENERATOR1, 3, nil, 34, 135, false, false);

  // MT_SECONDCOOLAND1
  MakeNonRotatingSprite('SecondCoolant', _MTRX_SECONDCOOLAND1, 1, nil, 64, 183, false, false);

  // MT_BIOMECHUP
  MakeOneSprite('BioMech9', _MTRX_BIOMECHUP, nil, 45, 89, false, false);

  // MT_ENGINECORE
  MakeNonRotatingSprite('EngineCore', _MTRX_ENGINECORE, 1, nil, 59, 178, false, false);

  // MT_DEFENCEDRONE1
  MakeRotatingSprite('DroneB', _MTRX_DEFENCEDRONE1, 1, nil, 63, 67, false, false);

  // MT_BATTLEDRONE2
  MakeRotatingSprite('DroneA', _MTRX_BATTLEDRONE2, 1, nil, 91, 50, false, false);

  // MT_SKYFIREASSULTFIGHTER2
  MakeRotatingSprite('LightAssault', _MTRX_SKYFIREASSULTFIGHTER2, 1, nil, 62, 51, false, false);

  // MT_SKYFIREASSULTFIGHTER3
  MakeRotatingSprite('LightAssault', _MTRX_SKYFIREASSULTFIGHTER3, 1, nil, 62, 51, false, false);

  // MT_SKYFIREASSULTFIGHTER4
  MakeRotatingSprite('LightAssault', _MTRX_SKYFIREASSULTFIGHTER4, 1, nil, 62, 51, false, false);

  // MT_BIOMECH
  MakeRotatingSprite('BioMech', _MTRX_BIOMECH, 1, nil, 73, 60, false, false);

  // MT_DEFENCEDRONE2
  MakeRotatingSprite('DroneB', _MTRX_DEFENCEDRONE2, 1, nil, 63, 67, false, false);

  bmp := TRadixBitmap.Create;

  for j := 0 to numsprinfo - 1 do
  begin
    spr := @SPRITEINFO[j];
    bl := nil;
    for i := 0 to bnumlumps - 1 do
      if radixlumpname(blumps[i]) = spr.rname then
      begin
        bl := @blumps[i];
        break;
      end;

    if bl = nil then
    begin
      spr.rname := remove_underline(spr.rname);
      for i := 0 to bnumlumps - 1 do
        if radixlumpname(blumps[i]) = spr.rname then
        begin
          bl := @blumps[i];
          break;
        end;
    end;

    if bl = nil then
      Continue;

    f.Seek(bl.position + (bl.width - 1) * SizeOf(radixcolumn_t), sFromBeginning);
    f.Read(rcol, SizeOf(radixcolumn_t));
    f.Seek(bl.position, sFromBeginning);

    buf := malloc(rcol.offs + rcol.size);
    f.Read(buf^, rcol.offs + rcol.size);

    bmp.width := bl.width;
    bmp.height := bl.height;

    bmp.Clear(254);

    pc := Pradixcolumn_tArray(buf);

    for x := 0 to bl.width - 1 do
      for y := pc[x].start to pc[x].start + pc[x].size - 1 do
      begin
        z := pc[x].offs - pc[x].start + y;
        z := buf[z];
        if z < 255 then
          bmp.Pixels[x, y] := z;
      end;

    if spr.translation <> nil then
      bmp.ApplyTranslationTable(spr.translation);

    if (spr.dname = 'XR38B1') or (spr.dname = 'XR38B2') or (spr.dname = 'XR38B8') then
    begin
      for x := 0 to bmp.width - 1 do
        if bmp.Pixels[x, 0] = 0 then
          bmp.Pixels[x, 0] := 254;
    end
    else if (spr.dname = 'XR38A5') or (spr.dname = 'XR38A6') or (spr.dname = 'XR38C4') or (spr.dname = 'XR38C5') then
    begin
      for x := 0 to bmp.width - 1 do
        if bmp.Pixels[x, bmp.height - 1] = 0 then
          bmp.Pixels[x, bmp.height - 1] := 254;
    end;

    if spr.defaultoffs then
      RX_CreateDoomPatch(bmp.Image, bl.width, bl.height, false, p, size)
    else if spr.centeroffs then
      RX_CreateDoomPatch(bmp.Image, bl.width, bl.height, false, p, size, bl.width div 2, bl.height div 2)
    else
      RX_CreateDoomPatch(bmp.Image, bl.width, bl.height, false, p, size, spr.xoffs, spr.yoffs);

    stmp := spr.dname;

    wadwriter.AddData(stmp, p, size);

    memfree(pointer(buf), rcol.offs + rcol.size);
    memfree(p, size);
  end;

  bmp.Free;

  wadwriter.AddSeparator('S_END');

  memfree(pointer(blumps), bnumlumps * SizeOf(radixbitmaplump_t));
end;

function TRadixToWADConverter.GenerateMusic: boolean;
var
  i, j: integer;
  mbuffer: pointer;
  msize: integer;
begin
  result := ReadLump(lumps, numlumps, 'IntroMusic', mbuffer, msize);
  if not result then
    exit;

  result := true;
  wadwriter.AddData('D_INTRO', mbuffer, msize);
  memfree(mbuffer, msize);

  for i := 1 to 3 do
    for j := 1 to 9 do
    begin
      if ReadLump(lumps, numlumps, 'MusicModule[' + itoa(i) +'][' + itoa(j) + ']', mbuffer, msize) then
      begin
        wadwriter.AddData('D_E' + itoa(i) + 'M' + itoa(j), mbuffer, msize);
        memfree(mbuffer, msize);
      end;
    end;
end;

function TRadixToWADConverter.GenerateCockpitOverlay: boolean;
var
  l: integer;
  startpos: integer;
  sizes: packed array[0..3] of smallint;
  positions: packed array[0..3] of smallint;
  idx: integer;
  i: integer;
  imgpos: integer;
  x, y: integer;
  b: byte;
  bmp: TRadixBitmap;
  p: pointer;
  size: integer;

  procedure imgpos2xy;
  var
    x1: integer;
    x2: integer;
    y1: integer;
    y2: integer;
  begin
    x := imgpos mod 320;
    y := imgpos div 320;
    x1 := x div 80;
    x2 := x mod 80;
    y1 := y div 50;
    y2 := y mod 50;
    x := x2 * 4 + y1;
    y := y2 * 4 + x1;
  end;

begin
  l := FindLump(lumps, numlumps, 'CockPitOverlay');
  if l < 0 then
  begin
    result := false;
    exit;
  end;
  result := true;


  bmp := TRadixBitmap.Create;
  bmp.width := 320;
  bmp.height := 200;
  bmp.Clear(254);

  startpos := lumps[l].position;
  f.Seek(startpos, sFromBeginning);

  f.Read(sizes, SizeOf(sizes));
  positions[0] := 12;
  positions[1] := sizes[0] + positions[0];
  positions[2] := sizes[1] + positions[1];
  positions[3] := sizes[2] + positions[2];
  for idx := 0 to 3 do
  begin
    imgpos := 320 * 50 * idx;
    f.Seek(startpos + positions[idx], sFromBeginning);
    for i := 0 to sizes[idx] - 1 do
    begin
      f.Read(b, SizeOf(byte));
      if b = 255 then
        break;
      if b = 0 then
      begin
        f.Read(b, SizeOf(b));
        imgpos := imgpos + b;
      end
      else
      begin
        if imgpos < 320 * 200 then
        begin
          imgpos2xy;
          bmp.Pixels[x, y] := b;
        end;
        imgpos := imgpos + 1;
      end;
    end;
  end;

  RX_CreateDoomPatch(bmp.Image, 320, 200, false, p, size, 0, 0);

  wadwriter.AddData('COCKPIT', p, size);

  memfree(p, size);
  bmp.Free;
end;

procedure TRadixToWADConverter.WritePK3Entry;
begin
  if aliases = nil then
    exit;
  if aliases.Count = 0 then
    exit;

  wadwriter.AddString(S_RADIXINF, aliases.Text);
end;

procedure TRadixToWADConverter.Convert(const fname: string);
begin
  if not fexists(fname) then
    exit;

  Clear;

  f := TFile.Create(fname, fOpenReadOnly);
  wadwriter := TWadWriter.Create;
  aliases := TDStringList.Create;
  textures := TDStringList.Create;

  ReadHeader;
  ReadDirectory;
  GeneratePalette;
  GenerateTranslationTables;
  GenerateTextures('PNAMES', 'TEXTURE1');
  GenerateLevels;
  GenerateFlats;
  GenerateMainGraphics;
  GenerateAdditionalGraphics;
  GenerateSmallFont;
  GenerateBigFonts;
  GenerateDosFonts;
  GenerateMenuTranslation;
  GenerateSprites;
  GenerateMusic;
  GenerateCockpitOverlay;
  WritePK3Entry;
end;

procedure TRadixToWADConverter.SaveToFile(const fname: string);
begin
  wadwriter.SaveToFile(fname);
end;

procedure TRadixToWADConverter.SaveToSream(const strm: TDStream);
begin
  wadwriter.SaveToStream(strm);
end;

procedure Radix2WAD(const fin, fout: string);
var
  cnv: TRadixToWADConverter;
begin
  cnv := TRadixToWADConverter.Create;
  try
    cnv.Convert(fin);
    cnv.SaveToFile(fout);
  finally
    cnv.Free;
  end;
end;

procedure Radix2Stream(const fin: string; const strm: TDStream);
var
  cnv: TRadixToWADConverter;
begin
  cnv := TRadixToWADConverter.Create;
  try
    cnv.Convert(fin);
    cnv.SaveToSream(strm);
  finally
    cnv.Free;
  end;
end;

procedure Radix2CSV(const fin: string; const pathout: string);
var
  cnv: TRadixToWADConverter;
begin
  cnv := TRadixToWADConverter.Create;
  try
    cnv.Convert(fin);
    cnv.GenerateCSVs(pathout);
  finally
    cnv.Free;
  end;
end;

end.

