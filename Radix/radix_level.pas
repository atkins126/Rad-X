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
//   Radix level
//
//------------------------------------------------------------------------------
//  Site: https://sourceforge.net/projects/rad-x/
//------------------------------------------------------------------------------

{$I RAD.inc}

unit radix_level;

interface

uses
  d_delphi,
  w_wadwriter;

function RX_CreateDoomLevel(const levelname: string;
  const rlevel: pointer; const rsize: integer;
  const markflats: PBooleanArray; const wadwriter: TWadWriter): boolean;

function RX_CreateRadixMapCSV(const levelname: string; const apath: string;
  const rlevel: pointer; const rsize: integer): boolean;

implementation

uses
  doomdef,
  radix_defs,
  radix_things,
  m_crc32,
  doomdata,
  w_wad;

const
  RADIXMAPMAGIC = $FFFFFEE7;
  RADIXSECTORNAMESIZE = 26;
  RADIXNUMPLAYERSTARTS = 8;

// Sector Flags
const
  RSF_DARKNESS = 1;
  RSF_FOG = 2;
  RSF_FLOORSLOPE = 4;
  RSF_CEILINGSLOPE = 8;
  RSF_CEILINGSKY = 16;
  RSF_FLOORSKY = 64;

// Wall Flags
const
  RWF_SINGLESIDED = 1;
  RWF_FLOORWALL = 2;
  RWF_CEILINGWALL = 4;
  // 20200216 -> new flags
  RWF_TWOSIDEDCOMPLETE = 16;
  RWF_PEGTOP_FLOOR = 32;
  RWF_PEGBOTTOM_FLOOR = 64;
  RWF_PEGTOP_CEILING = 128;
  RWF_PEGBOTTOM_CEILING = 256;
  RWF_ACTIVATETRIGGER = 1024;
  // JVAL 20200218 - Mark stub walls
  RWF_STUBWALL = $40000000;

type
  radixlevelheader_t = packed record
    id: LongWord;
    numtriggers: integer;
    numsprites: integer;
    _unknown1: packed array[0..16] of byte;
    numwalls: integer;
    numsectors: integer;
    _unknown2: packed array[0..3] of byte;
    numthings: integer;
    _unknown3: packed array[0..19] of byte;
    orthogonalmap: smallint;
    _unknown4: packed array[0..1] of byte;
    playerstartoffsets: integer;
  end;

  radixplayerstart_t = packed record
    x, y, z: integer;
    angle: byte;
  end;

const
  RADIXGRIDSIZE = 40960;

type
  radixgrid_t = packed array[0..RADIXGRIDSIZE - 1] of smallint;
  Pradixgrid_t = ^radixgrid_t;

type
  // Radix sector - size is 142 bytes
  radixsector_t = packed record
    _unknown1: packed array[0..1] of byte; // Always [1, 0]
    nameid: packed array[0..RADIXSECTORNAMESIZE - 1] of char;
    floortexture: smallint;
    ceilingtexture: smallint;
    floorheight: smallint;
    ceilingheight: smallint;
    lightlevel: byte;
    flags: byte;
    // Floor slope
    fa: integer;
    fb: integer;
    fc: integer;
    fd: integer;
    // Ceiling slope
    ca: integer;
    cb: integer;
    cc: integer;
    cd: integer;
    // Texture angle
    floorangle: LongWord;
    ceilingangle: LongWord;
    // Texture rotation - floor and ceiling height data for slopes
    heightnodesx: packed array[0..2] of integer;
    floorangle_x: integer;  // Pivot for rotating floor texture - x coord
    heightnodesy: packed array[0..2] of integer;
    floorangle_y: integer;  // Pivot for rotating floor texture - y coord
    floorheights: packed array[0..2] of integer;
    ceilingangle_x: integer;  // Pivot for rotating ceiling texture - x coord
    ceilingheights: packed array[0..2] of integer;
    ceilingangle_y: integer;  // Pivot for rotating ceiling texture - y coord
  end;
  Pradixsector_t = ^radixsector_t;
  radixsector_tArray = array[0..$FFF] of radixsector_t;
  Pradixsector_tArray = ^radixsector_tArray;

  // Radix wall - size os 86 bytes
  radixwall_t = packed record
    _unknown1: packed array[0..9] of byte;
    v1_x: integer;
    v1_y: integer;
    v2_x: integer;
    v2_y: integer;
    frontsector: smallint;
    backsector: smallint;
    _unknown2: packed array[0..41] of byte;
    flags: LongWord;
    bitmapoffset: smallint; // 20200216 - bitmapoffset
    wfloortexture: smallint;
    wceilingtexture: smallint;
    hitpoints: smallint; // 20200216 - VALUE = 100 -> default , VALUE = 2000 -> special ?
    trigger: smallint;  // 20200216 - Trigger id
  end;
  Pradixwall_t = ^radixwall_t;
  radixwall_tArray = array[0..$FFF] of radixwall_t;
  Pradixwall_tArray = ^radixwall_tArray;

  // Radix thing - Size is 34 bytes
  radixthing_t = packed record
    skill: byte;
    _unknown1: smallint;
    _unknown2: smallint;
    x: integer;
    y: integer;
    angle: byte;
    ground: smallint;
    _unknown7: smallint;
    _unknown8: integer;
    radix_type: integer;
    speed: smallint;
    thing_key: smallint;
    height_speed: smallint;
    _unknown12: smallint;
  end;
  Pradixthing_t = ^radixthing_t;
  radixthing_tArray = array[0..$FFF] of radixthing_t;
  Pradixthing_tArray = ^radixthing_tArray;

const
  MAX_RADIX_SPRITE_PARAMS = 64;

type
  radixsprite_t = packed record
    unknown1: byte; // always 1
    enabled: byte;  // 0-> disabled/hiden, 1 -> enabled/shown
    nameid: packed array[0..25] of char;
    extradata: smallint;
    // Offset to parameters
    // All parameters from all sprites are stored in a table
    // dataoffset point to the first item (from _unknown3 to the last of the params)
    dataoffset: smallint;
    sprite_type: smallint;
    _unknown3: packed array[0..1] of smallint;
    _unknown4: word; // 20200217
    params: packed array[0..MAX_RADIX_SPRITE_PARAMS - 1] of smallint;
  end;
  Pradixsprite_t = ^radixsprite_t;
  radixsprite_tArray = array[0..$FFF] of radixsprite_t;
  Pradixsprite_tArray = ^radixsprite_tArray;

const
  MAX_RADIX_TRIGGER_SPRITES = 150; // 133 max in radix.dat v2 remix

const
// activationflags of radixspritetrigger_t
  SPR_FLG_ACTIVATE = 0;
  SPR_FLG_DEACTIVATE = 1;
  SPR_FLG_ACTIVATEONSPACE = 2;
  SPR_FLG_TONGLE = 3;

type
  radixspritetrigger_t = packed record
    _unknown1: smallint;
    spriteid: smallint;
    trigger: smallint;
    activationflags: smallint;  // JVAL: 20200301 - SPR_FLG_ flags
    _unknown2: packed array[0..1] of smallint;
  end;
  Pradixspritetrigger_t = ^radixspritetrigger_t;
  radixspritetrigger_tArray = array[0..$FFF] of radixspritetrigger_t;
  Pradixspritetrigger_tArray = ^radixspritetrigger_tArray;

  radixtrigger_t = packed record
    _unknown1: byte; // always 1
    enabled: byte;  // 0-> disabled/hiden, 1 -> enabled/shown
    nameid: packed array[0..25] of char;
    numsprites: smallint;
    _unknown2: smallint; // Always 0
    _unknown3: word; // 20200217
    sprites: packed array[0..MAX_RADIX_TRIGGER_SPRITES - 1] of radixspritetrigger_t;
  end;
  Pradixtrigger_t = ^radixtrigger_t;
  radixtrigger_tArray = packed array[0..$FFF] of radixtrigger_t;
  Pradixtrigger_tArray = ^radixtrigger_tArray;

const
  RADIX_MAP_X_MULT = 1;
  RADIX_MAP_X_ADD = -32767;
  RADIX_MAP_Y_MULT = -1;
  RADIX_MAP_Y_ADD = 0;

function Radix_v10_levelCRC(const lname: string): string;
begin
  if lname ='E1M1' then result := '508E903B'
  else if lname ='E1M2' then result := '6456995C'
  else if lname ='E1M3' then result := '4FCE4AC0'
  else if lname ='E1M4' then result := 'D341760C'
  else if lname ='E1M5' then result := 'EE73818A'
  else if lname ='E1M6' then result := '827D20E4'
  else if lname ='E1M7' then result := 'D30FD83B'
  else if lname ='E1M8' then result := '66256496'
  else if lname ='E1M9' then result := 'CB48D934'
  else if lname ='E2M1' then result := '5351174C'
  else if lname ='E2M2' then result := 'A89AA971'
  else if lname ='E2M3' then result := 'C48C5B0E'
  else if lname ='E2M4' then result := '7CD6BAA6'
  else if lname ='E2M5' then result := '39D60BA5'
  else if lname ='E2M6' then result := 'A01810C0'
  else if lname ='E2M7' then result := '3BD5E170'
  else if lname ='E2M8' then result := '91FF1A54'
  else if lname ='E2M9' then result := '0A65F0FA'
  else if lname ='E3M1' then result := '0F790FDC'
  else if lname ='E3M2' then result := '51B675E4'
  else if lname ='E3M3' then result := '0D288E2B'
  else if lname ='E3M4' then result := '86B0E033'
  else if lname ='E3M5' then result := 'F948451E'
  else if lname ='E3M6' then result := '3020CCF0'
  else if lname ='E3M7' then result := '18F8424C'
  else if lname ='E3M8' then result := '100FEEFD'
  else if lname ='E3M9' then result := '6EDAD08A'
  else result := '';
  result := strupper(result);
end;

function Radix_v11_levelCRC(const lname: string): string;
begin
  if lname ='E1M1' then result := '9332AD1B'
  else if lname ='E1M2' then result := 'BC330015'
  else if lname ='E1M3' then result := '4FCE4AC0'
  else if lname ='E1M4' then result := 'D341760C'
  else if lname ='E1M5' then result := 'EE73818A'
  else if lname ='E1M6' then result := '827D20E4'
  else if lname ='E1M7' then result := 'D30FD83B'
  else if lname ='E1M8' then result := '66256496'
  else if lname ='E1M9' then result := 'CB48D934'
  else result := '';
  result := strupper(result);
end;

// radix 2.0 crc32
function Radix_v2_levelCRC(const lname: string): string;
begin
  if lname ='E1M1' then result := '1e621abe'
  else if lname ='E1M2' then result := '59b387ad'
  else if lname ='E1M3' then result := 'd29684c0'
  else if lname ='E1M4' then result := 'd341760c'
  else if lname ='E1M5' then result := '6baf74a2'
  else if lname ='E1M6' then result := '827d20e4'
  else if lname ='E1M7' then result := 'd30fd83b'
  else if lname ='E1M8' then result := '5b4c0e64'
  else if lname ='E1M9' then result := 'cb48d934'
  else if lname ='E2M1' then result := '5351174c'
  else if lname ='E2M2' then result := 'a89aa971'
  else if lname ='E2M3' then result := '76fc4e82'
  else if lname ='E2M4' then result := '3e7efcc7'
  else if lname ='E2M5' then result := '39d60ba5'
  else if lname ='E2M6' then result := 'a01810c0'
  else if lname ='E2M7' then result := '3bd5e170'
  else if lname ='E2M8' then result := '91ff1a54'
  else if lname ='E2M9' then result := 'd014181f'
  else if lname ='E3M1' then result := '0f790fdc'
  else if lname ='E3M2' then result := '51b675e4'
  else if lname ='E3M3' then result := '0d288e2b'
  else if lname ='E3M4' then result := '86b0e033'
  else if lname ='E3M5' then result := '714ef22b'
  else if lname ='E3M6' then result := '5b73ac44'
  else if lname ='E3M7' then result := '18f8424c'
  else if lname ='E3M8' then result := '8fe243cd'
  else if lname ='E3M9' then result := '6edad08a'
  else result := '';
  result := strupper(result);
end;

function RX_CreateDoomLevel(const levelname: string;
  const rlevel: pointer; const rsize: integer;
  const markflats: PBooleanArray; const wadwriter: TWadWriter): boolean;
var
  ms: TAttachableMemoryStream;
  header: radixlevelheader_t;
  rsectors: Pradixsector_tArray;
  rwalls: Pradixwall_tArray;
  rthings: Pradixthing_tArray;
  rsprites: Pradixsprite_tArray;
  rtriggers: Pradixtrigger_tArray;
  doomthings: Pmapthing_tArray;
  numdoomthings: integer;
  doomlinedefs: Pmaplinedef_tArray;
  numdoomlinedefs: integer;
  doomsidedefs: Pmapsidedef_tArray;
  numdoomsidedefs: integer;
  doomvertexes: Pmapvertex_tArray;
  numdoomvertexes: integer;
  doomsectors: Pmapsector_tArray;
  numdoomsectors: integer;
  doommapscript: TDStringList;
  i, j: integer;
  minx, maxx, miny, maxy: integer;
  sectormapped: PBooleanArray;
  tmpwall: radixwall_t;
  rplayerstarts: packed array[0..RADIXNUMPLAYERSTARTS - 1] of radixplayerstart_t;
  lcrc32: string;
  islevel_v: integer;

  procedure fix_wall_coordX(var xx: integer);
  begin
    if levelname = 'E3M2' then
      xx := xx div 4
    else
      xx := RADIX_MAP_X_MULT * xx + RADIX_MAP_X_ADD;
  end;

  procedure fix_wall_coordY(var yy: integer);
  begin
    yy := RADIX_MAP_Y_MULT * yy + RADIX_MAP_Y_ADD;
  end;

  function RadixSkillToDoomSkill(const sk: integer): integer;
  begin
    if (sk = 0) or (sk = 1) then
      result := MTF_EASY or MTF_NORMAL or MTF_HARD
    else if sk = 2 then
      result := MTF_NORMAL or MTF_HARD
    else if sk = 3 then
      result := MTF_HARD
    else
      result := MTF_EASY or MTF_NORMAL or MTF_HARD or MTF_NOTSINGLE;
  end;

  // angle is in 0-256
  procedure AddThingToWad(const x, y, z: smallint; const angle: smallint; const mtype: word; const options: smallint);
  var
    mthing: Pmapthing_t;
    xx, yy: integer;
  begin
    realloc(pointer(doomthings), numdoomthings * SizeOf(mapthing_t), (numdoomthings + 1) * SizeOf(mapthing_t));
    mthing := @doomthings[numdoomthings];
    inc(numdoomthings);
    xx := x;
    yy := y;
    fix_wall_coordX(xx);
    fix_wall_coordY(yy);
    mthing.x := xx;
    mthing.y := yy;
    // z ?
    mthing.angle := round((angle / 256) * 360);
    mthing._type := mtype;
    mthing.options := options;
  end;

  procedure AddPlayerStarts;
  var
    j: integer;
  begin
    // Player starts - DoomEdNum 1 thru 4
    for j := 0 to 3 do
      AddThingToWad(rplayerstarts[j].x, rplayerstarts[j].y, rplayerstarts[j].z, rplayerstarts[j].angle, j + 1, 7);
    // Deathmatch starts - DoomEdNum 11
    for j := 4 to RADIXNUMPLAYERSTARTS - 1 do
      AddThingToWad(rplayerstarts[j].x, rplayerstarts[j].y, rplayerstarts[j].z, rplayerstarts[j].angle, 11, 7);
  end;

  procedure ReadRadixGrid;
  var
    grid: Pradixgrid_t;
    grid_X_size: integer;
    grid_Y_size: integer;
    i_grid_x, i_grid_y: integer;
    g, l, k: smallint;
  begin
    if header.orthogonalmap <> 0 then
    begin
      grid_X_size := 320;
      grid_Y_size := 128;
    end
    else
    begin
      grid_X_size := 1280;
      grid_Y_size := 32;
    end;
    grid := mallocz(grid_X_size * grid_Y_size * SizeOf(smallint));

    for i_grid_y := 0 to grid_Y_size - 1 do
    begin
      i_grid_x := 0;
      repeat
        ms.Read(g, SizeOf(smallint));
        if g = -32000 then
        begin
          ms.Read(g, SizeOf(smallint));
          ms.Read(l, SizeOf(smallint));
          for k := 0 to l - 1 do
          begin
            grid[i_grid_y * grid_X_size + i_grid_x] := g;
            inc(i_grid_x);
          end;
        end
        else
        begin
          grid[i_grid_y * grid_X_size + i_grid_x] := g;
          inc(i_grid_x);
        end;
      until i_grid_x >= grid_X_size;
    end;

    memfree(pointer(grid), grid_X_size * grid_Y_size * SizeOf(smallint));
  end;

  function get_flat_texture(const id: integer): char8_t;
  begin
    result := stringtochar8(RX_FLAT_PREFIX + IntToStrzFill(4, id + 1));
    markflats[id + 1] := true;
  end;

  procedure AddSectorToWAD(const ss: Pradixsector_t);
  var
    dsec: Pmapsector_t;
  begin
    realloc(pointer(doomsectors), numdoomsectors * SizeOf(mapsector_t), (numdoomsectors  + 1) * SizeOf(mapsector_t));
    //Create classic map
    dsec := @doomsectors[numdoomsectors];
    dsec.floorheight := ss.floorheight;
    dsec.ceilingheight := ss.ceilingheight;
    if ss.flags and RSF_FLOORSKY <> 0 then
      dsec.floorpic := stringtochar8('F_SKY1')
    else
      dsec.floorpic := get_flat_texture(ss.floortexture);
    if ss.flags and RSF_CEILINGSKY <> 0 then
      dsec.ceilingpic := stringtochar8('F_SKY1')
    else
      dsec.ceilingpic := get_flat_texture(ss.ceilingtexture);
    dsec.lightlevel := ss.lightlevel * 4 + 2;
    dsec.special := 0;
    dsec.tag := 0;


    // Create extra data stored in MAP header
    doommapscript.Add('sectorid ' + itoa(numdoomsectors));
    doommapscript.Add('xmul ' + itoa(RADIX_MAP_X_MULT));
    doommapscript.Add('xadd ' + itoa(RADIX_MAP_X_ADD));
    doommapscript.Add('ymul ' + itoa(RADIX_MAP_Y_MULT));
    doommapscript.Add('yadd ' + itoa(RADIX_MAP_Y_ADD));

    if ss.flags and RSF_FLOORSLOPE <> 0 then
      doommapscript.Add('floorslope ' + itoa(ss.fa) + ' ' + itoa(ss.fb) + ' ' + itoa(ss.fc) + ' ' + itoa(ss.fd));

    if ss.flags and RSF_CEILINGSLOPE <> 0 then
      doommapscript.Add('ceilingslope ' + itoa(ss.ca) + ' ' + itoa(ss.cb) + ' ' + itoa(ss.cc) + ' ' + itoa(ss.cd));

    if ss.flags and (RSF_FLOORSLOPE or RSF_CEILINGSLOPE) <> 0 then
    begin
      doommapscript.Add('heightnodesx ' + itoa(ss.heightnodesx[0]) + ' ' + itoa(ss.heightnodesx[1]) + ' ' + itoa(ss.heightnodesx[2]));
      doommapscript.Add('heightnodesy ' + itoa(ss.heightnodesy[0]) + ' ' + itoa(ss.heightnodesy[1]) + ' ' + itoa(ss.heightnodesy[2]));
      if ss.flags and RSF_FLOORSLOPE <> 0 then
        doommapscript.Add('floorheights ' + itoa(ss.floorheights[0]) + ' ' + itoa(ss.floorheights[1]) + ' ' + itoa(ss.floorheights[2]));
      if ss.flags and RSF_CEILINGSLOPE <> 0 then
        doommapscript.Add('ceilingheights ' + itoa(ss.ceilingheights[0]) + ' ' + itoa(ss.ceilingheights[1]) + ' ' + itoa(ss.ceilingheights[2]));
    end;

    if ss.floorangle <> 0 then
    begin
      doommapscript.Add('floorangle ' + itoa(ss.floorangle));
      doommapscript.Add('floorangle_x ' + itoa(ss.floorangle_x));
      doommapscript.Add('floorangle_y ' + itoa(ss.floorangle_x));
    end;
    if ss.ceilingangle <> 0 then
    begin
      doommapscript.Add('ceilingangle ' + itoa(ss.ceilingangle));
      doommapscript.Add('ceilingangle_x ' + itoa(ss.ceilingangle_x));
      doommapscript.Add('ceilingangle_y ' + itoa(ss.ceilingangle_y));
    end;
    doommapscript.Add('');

    inc(numdoomsectors);
  end;

  function AddVertexToWAD(const x, y: smallint): integer;
  var
    j: integer;
  begin
    for j := 0 to numdoomvertexes - 1 do
      if (doomvertexes[j].x = x) and (doomvertexes[j].y = y) then
      begin
        result := j;
        exit;
      end;
    realloc(pointer(doomvertexes), numdoomvertexes * SizeOf(mapvertex_t), (numdoomvertexes  + 1) * SizeOf(mapvertex_t));
    doomvertexes[numdoomvertexes].x := x;
    doomvertexes[numdoomvertexes].y := y;
    result := numdoomvertexes;
    inc(numdoomvertexes);
  end;

  function AddSidedefToWAD(const toff, roff: smallint;
    const toptex, bottomtex, midtex: char8_t; const sector: smallint): integer;
  var
    j: integer;
    pside: Pmapsidedef_t;
  begin
    for j := 0 to numdoomsidedefs - 1 do
      if (doomsidedefs[j].textureoffset = toff) and (doomsidedefs[j].rowoffset = roff) and
         (doomsidedefs[j].toptexture = toptex) and (doomsidedefs[j].bottomtexture = bottomtex) and (doomsidedefs[j].midtexture = midtex) and
         (doomsidedefs[j].sector = sector) then
      begin
        result := j;
        exit;
      end;
    realloc(pointer(doomsidedefs), numdoomsidedefs * SizeOf(mapsidedef_t), (numdoomsidedefs  + 1) * SizeOf(mapsidedef_t));
    pside := @doomsidedefs[numdoomsidedefs];
    pside.textureoffset := toff;
    pside.rowoffset := roff;
    pside.toptexture := toptex;
    pside.bottomtexture := bottomtex;
    pside.midtexture := midtex;
    pside.sector := sector;
    result := numdoomsidedefs;
    inc(numdoomsidedefs);
  end;

  procedure AddWallToWAD(const w: Pradixwall_t);
  var
    dline: Pmaplinedef_t;
    v1, v2: integer;
    s1, s2: integer;
    news1, news2: boolean;
    toptex, bottomtex, midtex: char8_t;
    ftex, ctex: integer;
  begin
    // Front Sidedef
    news1 := true;
    news2 := true;
    ftex := w.wfloortexture + 1; // Add 1 to compensate for stub texture RDXW0000
    ctex := w.wceilingtexture + 1; // Add 1 to compensate for stub texture RDXW0000
    if w.frontsector >= 0 then
    begin
      if (w.flags and RWF_STUBWALL = 0) and
         (rsectors[w.frontsector].floortexture = 0) and
         (rsectors[w.frontsector].ceilingtexture = 0) and
         (rsectors[w.frontsector].floorheight = rsectors[w.frontsector].ceilingheight) then // sos <- WHAT ABOUT DOORS ?
         s1 := -1
      else
      begin
        if w.flags and RWF_SINGLESIDED <> 0 then
        begin
          toptex := stringtochar8('-');
          bottomtex := stringtochar8('-');
          midtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex));
        end
        else
        begin
          if w.flags and RWF_FLOORWALL <> 0 then
            bottomtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex))
          else
            bottomtex := stringtochar8('-');
          if w.flags and RWF_CEILINGWALL <> 0 then
            toptex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ctex))
          else
            toptex := stringtochar8('-');
          if w.flags and RWF_TWOSIDEDCOMPLETE <> 0 then
            midtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex))
          else
            midtex := stringtochar8('-');
        end;
        s1 := AddSidedefToWAD(w.bitmapoffset, 0, toptex, bottomtex, midtex, w.frontsector);
        news1 := s1 = numdoomsidedefs - 1;
      end;
    end
    else
      s1 := -1;

    // Back Sidedef
    if w.backsector >= 0 then
    begin
      if (rsectors[w.backsector].floortexture = 0) and
         (rsectors[w.backsector].ceilingtexture = 0) and
         (rsectors[w.backsector].floorheight = rsectors[w.backsector].ceilingheight) then
         s2 := -1
      else
      begin
        if w.flags and RWF_SINGLESIDED <> 0 then
        begin
          toptex := stringtochar8('-');
          bottomtex := stringtochar8('-');
          midtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex));
        end
        else
        begin
          if w.flags and RWF_FLOORWALL <> 0 then
            bottomtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex))
          else
            bottomtex := stringtochar8('-');
          if w.flags and RWF_CEILINGWALL <> 0 then
            toptex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ctex))
          else
            toptex := stringtochar8('-');
          if w.flags and RWF_TWOSIDEDCOMPLETE <> 0 then
            midtex := stringtochar8(RX_WALL_PREFIX + IntToStrzFill(4, ftex))
          else
            midtex := stringtochar8('-');
        end;
        s2 := AddSidedefToWAD(0, 0, toptex, bottomtex, midtex, w.backsector);
        news2 := s2 = numdoomsidedefs - 1;
      end;
    end
    else
      s2 := -1;

    // Find vertexes
    v1 := AddVertexToWAD(w.v1_x, w.v1_y);
    v2 := AddVertexToWAD(w.v2_x, w.v2_y);

    // Add Doom lidedef
    realloc(pointer(doomlinedefs), numdoomlinedefs * SizeOf(maplinedef_t), (numdoomlinedefs  + 1) * SizeOf(maplinedef_t));
    dline := @doomlinedefs[numdoomlinedefs];
    inc(numdoomlinedefs);

    if s1 < 0 then
    begin
      dline.v1 := v2;
      dline.v2 := v1;
    end
    else
    begin
      dline.v1 := v1;
      dline.v2 := v2;
    end;

    dline.flags := 0;
    if (s1 >= 0) and (s2 >= 0) then
      dline.flags := dline.flags or ML_TWOSIDED;
//    if w.flags and RWF_PEGTOP_FLOOR <> 0 then
//    if w.flags and RWF_PEGBOTTOM_FLOOR <> 0 then
//    if w.flags and RWF_PEGTOP_CEILING <> 0 then
//    if w.flags and RWF_PEGBOTTOM_CEILING <> 0 then
//      dline.flags := dline.flags or ML_DONTPEGBOTTOM;
//      dline.flags := dline.flags or ML_DONTPEGTOP;

    if w.flags and RWF_STUBWALL <> 0 then
      dline.flags := dline.flags or ML_DONTDRAW;

    dline.special := 0;
    dline.tag := 0;

    if s1 < 0 then
    begin
      dline.sidenum[0] := s2;
      dline.sidenum[1] := -1;
    end
    else
    begin
      dline.sidenum[0] := s1;
      dline.sidenum[1] := s2;
    end;

    if (dline.flags and ML_TWOSIDED = 0) and (dline.sidenum[0] >= 0) then
    begin
      dline.flags := dline.flags or ML_BLOCKING;
      if doomsidedefs[dline.sidenum[0]].midtexture = stringtochar8('-') then
      begin
        if news1 and news2 then
          doomsidedefs[dline.sidenum[0]].midtexture := doomsidedefs[dline.sidenum[0]].toptexture
        else
          dline.sidenum[0] := AddSidedefToWAD(0, 0, stringtochar8('-'), stringtochar8('-'), doomsidedefs[dline.sidenum[0]].toptexture, doomsidedefs[dline.sidenum[0]].sector);
      end;
    end;
  end;

  function fix_level_v10: boolean;
  begin
    result := false;
    if levelname = 'E3M6' then
    begin
      result := true;
      doomsectors[62].ceilingheight := 1408;
    end;
  end;

  function fix_level_v11: boolean;
  var
    j: integer;
  begin
    result := false;
    if levelname = 'E1M1' then
    begin
      result := true;
      for j := 0 to numdoomsidedefs - 1 do
        if doomsidedefs[j].sector = 206 then
          doomsidedefs[j].sector := 0
        else if doomsidedefs[j].sector = 211 then
          doomsidedefs[j].sector := 212;
    end;
  end;

  function fix_level_v2: boolean;
  var
    j: integer;
    v1, v2: integer;
    sd: integer;
  begin
    result := false;
    if levelname = 'E1M1' then
    begin
      result := true;
      for j := 0 to numdoomsidedefs - 1 do
        if doomsidedefs[j].sector = 206 then
          doomsidedefs[j].sector := 0
        else if doomsidedefs[j].sector = 211 then
          doomsidedefs[j].sector := 212;
    end
    else if levelname = 'E2M1' then
    begin
      result := true;
      for j := 0 to numdoomsidedefs - 1 do
        if doomsidedefs[j].sector = 64 then
          doomsidedefs[j].sector := 65;
    end
    else if levelname = 'E2M4' then
    begin
      result := true;
      v1 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = 1473) and (doomvertexes[j].y = -1344) then
        begin
          v1 := j;
          break;
        end;
      v2 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = 1537) and (doomvertexes[j].y = -1344) then
        begin
          v2 := j;
          break;
        end;

      if (v1 >= 0) and (v2 >= 0) then
        for j := 0 to numdoomlinedefs - 1 do
        begin
          if doomlinedefs[j].v1 = v1 then
            doomlinedefs[j].v1 := v2;
          if doomlinedefs[j].v2 = v1 then
            doomlinedefs[j].v2 := v2;
        end;
    end
    else if levelname = 'E2M5' then
    begin
      result := true;
      for j := 0 to numdoomsidedefs - 1 do
        if doomsidedefs[j].sector = 2 then
          doomsidedefs[j].sector := 1;
    end
    else if levelname = 'E2M7' then
    begin
      result := true;
      for j := 0 to numdoomsidedefs - 1 do
        if doomsidedefs[j].sector = 102 then
          doomsidedefs[j].sector := 52;

      v1 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = -19135) and (doomvertexes[j].y = -4096) then
        begin
          v1 := j;
          break;
        end;
      v2 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = -19135) and (doomvertexes[j].y = -4160) then
        begin
          v2 := j;
          break;
        end;

      if (v1 >= 0) and (v2 >= 0) then
        for j := 0 to numdoomlinedefs - 1 do
        begin
          if doomlinedefs[j].v1 = v1 then
            doomlinedefs[j].v1 := v2;
          if doomlinedefs[j].v2 = v1 then
            doomlinedefs[j].v2 := v2;
        end;

      sd := doomlinedefs[19].sidenum[1];
      if sd >= 0 then
        doomsidedefs[sd].toptexture := doomsidedefs[sd].bottomtexture;
    end
    else if levelname = 'E3M1' then
    begin
      result := true;
      sd := doomlinedefs[45].sidenum[0];

      doomlinedefs[31].sidenum[1] := -1;
      doomlinedefs[31].sidenum[0] := sd;
      doomlinedefs[31].flags := doomlinedefs[31].flags and not ML_TWOSIDED;
      doomlinedefs[31].flags := doomlinedefs[31].flags or ML_BLOCKING;

      doomlinedefs[37].sidenum[1] := -1;
      doomlinedefs[37].sidenum[0] := sd;
      doomlinedefs[37].flags := doomlinedefs[37].flags and not ML_TWOSIDED;
      doomlinedefs[37].flags := doomlinedefs[37].flags or ML_BLOCKING;

      doomlinedefs[39].sidenum[1] := -1;
      doomlinedefs[39].sidenum[0] := sd;
      doomlinedefs[39].flags := doomlinedefs[39].flags and not ML_TWOSIDED;
      doomlinedefs[39].flags := doomlinedefs[39].flags or ML_BLOCKING;

      doomlinedefs[43].sidenum[1] := -1;
      doomlinedefs[43].sidenum[0] := sd;
      doomlinedefs[43].flags := doomlinedefs[43].flags and not ML_TWOSIDED;
      doomlinedefs[43].flags := doomlinedefs[43].flags or ML_BLOCKING;

      doomlinedefs[85].sidenum[1] := -1;
      doomlinedefs[85].sidenum[0] := sd;
      doomlinedefs[85].flags := doomlinedefs[85].flags and not ML_TWOSIDED;
      doomlinedefs[85].flags := doomlinedefs[85].flags or ML_BLOCKING;

      doomlinedefs[86].sidenum[1] := -1;
      doomlinedefs[86].sidenum[0] := sd;
      doomlinedefs[86].flags := doomlinedefs[86].flags and not ML_TWOSIDED;
      doomlinedefs[86].flags := doomlinedefs[86].flags or ML_BLOCKING;
    end
    else if levelname = 'E3M3' then
    begin
      result := true;
      sd := doomlinedefs[320].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].sector := 48;

      sd := doomlinedefs[321].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].sector := 48;

      sd := doomlinedefs[587].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].sector := 48;

      sd := doomlinedefs[590].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].sector := 48;
    end
    else if levelname = 'E3M7' then
    begin
      result := true;
      v1 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = -32703) and (doomvertexes[j].y = -3520) then
        begin
          v1 := j;
          break;
        end;
      v2 := -1;
      for j := 0 to numdoomvertexes - 1 do
        if (doomvertexes[j].x = -32703) and (doomvertexes[j].y = -3584) then
        begin
          v2 := j;
          break;
        end;

      if (v1 >= 0) and (v2 >= 0) then
        for j := 0 to numdoomlinedefs - 1 do
        begin
          if doomlinedefs[j].v1 = v1 then
            doomlinedefs[j].v1 := v2;
          if doomlinedefs[j].v2 = v1 then
            doomlinedefs[j].v2 := v2;
        end;

      doomlinedefs[410].sidenum[1] := -1;
      doomlinedefs[410].flags := doomlinedefs[86].flags and not ML_TWOSIDED;
      doomlinedefs[410].flags := doomlinedefs[86].flags or ML_BLOCKING;
      sd := doomlinedefs[410].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].midtexture := doomsidedefs[sd].bottomtexture;

      doomlinedefs[411].sidenum[1] := -1;
      doomlinedefs[411].flags := doomlinedefs[86].flags and not ML_TWOSIDED;
      doomlinedefs[411].flags := doomlinedefs[86].flags or ML_BLOCKING;
      sd := doomlinedefs[411].sidenum[0];
      if sd >= 0 then
        doomsidedefs[sd].midtexture := doomsidedefs[sd].bottomtexture;
    end;
  end;

  // Slpit long linedefs
  function split_long_lidedefs: boolean;
  const
//    SPLITDELTA = 520.0;
//    SPLITSIZE = 512.0;
    SPLITDELTA = 260.0;
    SPLITSIZE = 256.0;
  var
    j: integer;
    cnt: integer;
    flen: float;
    dx, dy: integer;
    dline1, dline2: Pmaplinedef_t;
    newx, newy: integer;
    newv: integer;
  begin
    cnt := numdoomlinedefs;
    result := false;
    for j := 0 to cnt - 1 do
    begin
      dline1 := @doomlinedefs[j];
      dx := doomvertexes[dline1.v1].x - doomvertexes[dline1.v2].x;
      dy := doomvertexes[dline1.v1].y - doomvertexes[dline1.v2].y;
      flen := sqr(dx) + sqr(dy);
      if flen > SPLITDELTA * SPLITDELTA then
      begin
        flen := sqrt(flen);

        newx := doomvertexes[dline1.v1].x - round(SPLITSIZE * dx / flen);
        newy := doomvertexes[dline1.v1].y - round(SPLITSIZE * dy / flen);

        newv := AddVertexToWAD(newx, newy);

        realloc(pointer(doomlinedefs), numdoomlinedefs * SizeOf(maplinedef_t), (numdoomlinedefs  + 1) * SizeOf(maplinedef_t));
        dline2 := @doomlinedefs[numdoomlinedefs];
        inc(numdoomlinedefs);

        dline2^ := dline1^;

        dline1.v2 := newv;
        dline2.v1 := newv;
        result := true;
      end;
    end;
  end;

begin
  ms := TAttachableMemoryStream.Create;
  ms.Attach(rlevel, rsize);
  lcrc32 := strupper(GetBufCRC32(ms.memory, ms.Size));
  if Radix_v2_levelCRC(levelname) = lcrc32 then
    islevel_v := 2
  else if Radix_v10_levelCRC(levelname) = lcrc32 then
    islevel_v := 10
  else if Radix_v11_levelCRC(levelname) = lcrc32 then
    islevel_v := 11
  else
    islevel_v := 0;


  // Read Radix level header
  ms.Read(header, SizeOf(radixlevelheader_t));
  if header.id <> RADIXMAPMAGIC then
  begin
    result := false;
    ms.Free;
    exit;
  end;
  result := true;

  // Read Radix sectors
  rsectors := malloc(header.numsectors * SizeOf(radixsector_t));
  ms.Read(rsectors^, header.numsectors * SizeOf(radixsector_t));

  // Read Radix walls
  rwalls := malloc(header.numwalls * SizeOf(radixwall_t));
  ms.Read(rwalls^, header.numwalls * SizeOf(radixwall_t));
  for i := 0 to header.numwalls - 1 do
  begin
    fix_wall_coordX(rwalls[i].v1_x);
    fix_wall_coordY(rwalls[i].v1_y);
    fix_wall_coordX(rwalls[i].v2_x);
    fix_wall_coordY(rwalls[i].v2_y);
  end;

  // Read and unpack the 320x128 or 1280x32 grid (RLE compressed)
  // Used for advancing the position of input stream
  ReadRadixGrid;

  // Read Radix things
  rthings := malloc(header.numthings * SizeOf(radixthing_t));
  ms.Read(rthings^, header.numthings * SizeOf(radixthing_t));

  // Read Trigger's grid
  ReadRadixGrid;

  // Read Radix sprites
  rsprites := mallocz(header.numsprites * SizeOf(radixsprite_t)); // SOS -> use mallocz
  for i := 0 to header.numsprites - 1 do
  begin
    ms.Read(rsprites[i], 40); // Read the first 40 bytes
    ms.Read(rsprites[i].params, rsprites[i].extradata);
  end;

  // Read Radix triggers
  rtriggers := mallocz(header.numtriggers * SizeOf(radixtrigger_t)); // SOS -> use mallocz
  for i := 0 to header.numtriggers - 1 do
  begin
    ms.Read(rtriggers[i], 34); // Read the first 34 bytes
    for j := 0 to rtriggers[i].numsprites - 1 do
      ms.Read(rtriggers[i].sprites[j], SizeOf(radixspritetrigger_t));
  end;

  // Read Radix player starts
  ms.Seek(header.playerstartoffsets, sFromBeginning);
  ms.Read(rplayerstarts, SizeOf(rplayerstarts));

  doomthings := nil;
  numdoomthings := 0;
  doomlinedefs := nil;
  numdoomlinedefs := 0;
  doomsidedefs := nil;
  numdoomsidedefs := 0;
  doomvertexes := nil;
  numdoomvertexes := 0;
  doomsectors := nil;
  numdoomsectors := 0;

  // Create script entry for map - holds extra info
  doommapscript := TDStringList.Create;

  // Create Player starts
  AddPlayerStarts;

  // Create Doom Sectors
  for i := 0 to header.numsectors - 1 do
    AddSectorToWAD(@rsectors[i]);

  // Create Doom Vertexes, Linesdefs & Sidedefs
  for i := 0 to header.numwalls - 1 do
    AddWallToWAD(@rwalls[i]);

  for i := 0 to header.numthings - 1 do
  begin
    if rthings[i].radix_type > 0 then
      AddThingToWad(rthings[i].x, rthings[i].y, 0, rthings[i].angle, rthings[i].radix_type + _DOOM_THING_2_RADIX_, RadixSkillToDoomSkill(rthings[i].skill));
  end;

  // Find Doom map bounding box;
  minx := 100000;
  maxx := -100000;
  miny := 100000;
  maxy := -100000;
  for i := 0 to numdoomvertexes - 1 do
  begin
    if doomvertexes[i].x > maxx then
      maxx := doomvertexes[i].x;
    if doomvertexes[i].x < minx then
      minx := doomvertexes[i].x;
    if doomvertexes[i].y > maxy then
      maxy := doomvertexes[i].y;
    if doomvertexes[i].y < miny then
      miny := doomvertexes[i].y;
  end;

  if islevel_v = 2 then
    fix_level_v2
  else if islevel_v = 11 then
    fix_level_v11
  else if islevel_v = 10 then
    fix_level_v10;

//  repeat until not split_long_lidedefs;

  // Find mapped sectors
  sectormapped := mallocz(numdoomsectors);
  for i := 0 to numdoomsidedefs - 1 do
    sectormapped[doomsidedefs[i].sector] := true;

  // Create stub unmapped sectors
  ZeroMemory(@tmpwall, SizeOf(radixwall_t));
  tmpwall.backsector := -1;
  tmpwall.flags := RWF_SINGLESIDED or RWF_STUBWALL;
  tmpwall.wfloortexture := 1;
  for i := 0 to numdoomsectors - 1 do
    if not sectormapped[i] then
    begin
      tmpwall.frontsector := i;

      tmpwall.v1_x := minx + i * 16 + 8;
      tmpwall.v1_y := maxy + 128;
      tmpwall.v2_x := minx + i * 16;
      tmpwall.v2_y := maxy + 136;
      AddWallToWAD(@tmpwall);

      tmpwall.v1_x := minx + i * 16;
      tmpwall.v1_y := maxy + 136;
      tmpwall.v2_x := minx + i * 16 + 8;
      tmpwall.v2_y := maxy + 144;
      AddWallToWAD(@tmpwall);

      tmpwall.v1_x := minx + i * 16 + 8;
      tmpwall.v1_y := maxy + 144;
      tmpwall.v2_x := minx + i * 16 + 8;
      tmpwall.v2_y := maxy + 128;
      AddWallToWAD(@tmpwall);
    end;

  memfree(pointer(sectormapped), numdoomsectors);

  wadwriter.AddString(levelname, doommapscript.Text);
  wadwriter.AddData('THINGS', doomthings, numdoomthings * SizeOf(mapthing_t));
  wadwriter.AddData('LINEDEFS', doomlinedefs, numdoomlinedefs * SizeOf(maplinedef_t));
  wadwriter.AddData('SIDEDEFS', doomsidedefs, numdoomsidedefs * SizeOf(mapsidedef_t));
  wadwriter.AddData('VERTEXES', doomvertexes, numdoomvertexes * SizeOf(mapvertex_t));
  wadwriter.AddSeparator('SEGS');
  wadwriter.AddSeparator('SSECTORS');
  wadwriter.AddSeparator('NODES');
  wadwriter.AddData('SECTORS', doomsectors, numdoomsectors * SizeOf(mapsector_t));
  wadwriter.AddSeparator('REJECT');
  wadwriter.AddSeparator('BLOCKMAP');

  // Free Radix data
  memfree(pointer(rsectors), header.numsectors * SizeOf(radixsector_t));
  memfree(pointer(rwalls), header.numwalls * SizeOf(radixwall_t));
  memfree(pointer(rthings), header.numthings * SizeOf(radixthing_t));
  memfree(pointer(rsprites), header.numsprites * SizeOf(radixsprite_t));
  memfree(pointer(rtriggers), header.numtriggers * SizeOf(radixtrigger_t));

  // Free Doom data
  memfree(pointer(doomthings), numdoomthings * SizeOf(mapthing_t));
  memfree(pointer(doomlinedefs), numdoomlinedefs * SizeOf(maplinedef_t));
  memfree(pointer(doomsidedefs), numdoomsidedefs * SizeOf(mapsidedef_t));
  memfree(pointer(doomvertexes), numdoomvertexes * SizeOf(mapvertex_t));
  memfree(pointer(doomsectors), numdoomsectors * SizeOf(mapsector_t));

  // Free Extra Radix Scripted Data
  doommapscript.Free;

  ms.Free;
end;

function RX_CreateRadixMapCSV(const levelname: string; const apath: string;
  const rlevel: pointer; const rsize: integer): boolean;
var
  ms: TAttachableMemoryStream;
  header: radixlevelheader_t;
  rsectors: Pradixsector_tArray;
  rwalls: Pradixwall_tArray;
  rthings: Pradixthing_tArray;
  rsprites: Pradixsprite_tArray;
  rtriggers: Pradixtrigger_tArray;
  csvsectors: TDStringList;
  csvwalls: TDStringList;
  csvthings: TDStringList;
  csvsprites: TDStringList;
  csvtriggers: TDStringList;
  i, j: integer;
  path: string;

  // angle is in 0-256
  procedure AddThingToCSV(const th: Pradixthing_t);
  var
    stmp: string;
  begin
    if csvthings.Count = 0 then
      csvthings.Add(
      'skill,' +
      'unknown1,' +
      'unknown2,' +
      'x,' +
      'y,' +
      'angle,' +
      'ground,' +
      'unknown7,' +
      'unknown8,' +
      'radix_type,' +
      'speed,' +
      'thing_key,' +
      'height_speed,' +
      'unknown12');

    sprintf(stmp, '%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d', [
    th.skill,
    th._unknown1,
    th._unknown2,
    th.x,
    th.y,
    th.angle,
    th.ground,
    th._unknown7,
    th._unknown8,
    th.radix_type,
    th.speed,
    th.thing_key,
    th.height_speed,
    th._unknown12]);

    csvthings.Add(stmp);
  end;

  procedure AddSpriteToCSV(const spr: Pradixsprite_t; const id: integer);
  var
    stmp: string;
    ii: integer;
  begin
    if csvsprites.Count = 0 then
    begin
      stmp := 'id,unknown1,enabled,name,extradata,dataoffset,type,';
      for ii := 0 to 1 do
        stmp := stmp + 'unknown3_' + itoa(ii) + ',';
      stmp := stmp +'unknown4' + ',';
      for ii := 0 to MAX_RADIX_SPRITE_PARAMS - 1 do
        stmp := stmp + 'param_' + itoa(ii) + ',';
      csvsprites.Add(stmp);
    end;

    stmp := itoa(id) + ',' + itoa(spr.unknown1) + ',';
    stmp := stmp + itoa(spr.enabled) + ',';

    for ii := 0 to 25 do
    begin
      if spr.nameid[ii] = #0 then
        break
      else
        stmp := stmp + spr.nameid[ii];
    end;
    stmp := stmp + ',';

    stmp := stmp + itoa(spr.extradata) + ',';
    stmp := stmp + itoa(spr.dataoffset) + ',';
    stmp := stmp + itoa(spr.sprite_type) + ',';

    for ii := 0 to 1 do
      stmp := stmp + itoa(spr._unknown3[ii]) + ',';
    stmp := stmp + uitoa(spr._unknown4) + ',';
    for ii := 0 to MAX_RADIX_SPRITE_PARAMS - 1 do
      stmp := stmp + itoa(spr.params[ii]) + ',';

    csvsprites.Add(stmp);
  end;

  procedure AddTriggerToCSV(const tr: Pradixtrigger_t; const id: integer);
  var
    stmp: string;
    ii, jj: integer;
  begin
    if csvtriggers.Count = 0 then
    begin
      stmp := 'id,unknown1,enabled,name,numsprites,unknown2,unknown3,';
      for ii := 0 to 47 {MAX_RADIX_TRIGGER_SPRITES - 1} do
      begin
        stmp := stmp + 's_unk_1_' + itoa(ii) + ',';
        stmp := stmp + 'sprite_' + itoa(ii) + ',';
        stmp := stmp + 'trigger_' + itoa(ii) + ',';
        stmp := stmp + 'activationflags_' + itoa(ii) + ',';
        stmp := stmp + 'spritedata_' + itoa(ii) + ',';
      end;
      csvtriggers.Add(stmp);
    end;

    stmp := itoa(id) + ',' + itoa(tr._unknown1) + ',';
    stmp := stmp + itoa(tr.enabled) + ',';

    for ii := 0 to 25 do
    begin
      if tr.nameid[ii] = #0 then
        break
      else
        stmp := stmp + tr.nameid[ii];
    end;
    stmp := stmp + ',';

    stmp := stmp + itoa(tr.numsprites) + ',';
    stmp := stmp + itoa(tr._unknown2) + ',';
    stmp := stmp + uitoa(tr._unknown3) + ',';

    for ii := 0 to 47 {MAX_RADIX_TRIGGER_SPRITES - 1} do
    begin
      stmp := stmp + itoa(tr.sprites[ii]._unknown1) + ',';
      stmp := stmp + itoa(tr.sprites[ii].spriteid) + ',';
      stmp := stmp + itoa(tr.sprites[ii].trigger) + ',';
      stmp := stmp + itoa(tr.sprites[ii].activationflags) + ',';
      for jj := 0 to 1 do
        stmp := stmp + itoa(tr.sprites[ii]._unknown2[jj]) + ' ';
      stmp := stmp + ',';
    end;

    csvtriggers.Add(stmp);
  end;

  procedure ReadRadixGridAndCreateCSV(const gid: integer);
  var
    grid: Pradixgrid_t;
    grid_X_size: integer;
    grid_Y_size: integer;
    i_grid_x, i_grid_y: integer;
    g, l, k: smallint;
    csvgrid: TDStringList;
    csvgridtable: TDStringList;
    stmp: string;
    sitem: string;
  begin
    if header.orthogonalmap <> 0 then
    begin
      grid_X_size := 320;
      grid_Y_size := 128;
    end
    else
    begin
      grid_X_size := 1280;
      grid_Y_size := 32;
    end;
    grid := mallocz(grid_X_size * grid_Y_size * SizeOf(smallint));

    for i_grid_y := 0 to grid_Y_size - 1 do
    begin
      i_grid_x := 0;
      repeat
        ms.Read(g, SizeOf(smallint));
        if g = -32000 then
        begin
          ms.Read(g, SizeOf(smallint));
          ms.Read(l, SizeOf(smallint));
          for k := 0 to l - 1 do
          begin
            grid[i_grid_y * grid_X_size + i_grid_x] := g;
            inc(i_grid_x);
          end;
        end
        else
        begin
          grid[i_grid_y * grid_X_size + i_grid_x] := g;
          inc(i_grid_x);
        end;
      until i_grid_x >= grid_X_size;
    end;


    csvgrid := TDStringList.Create;
    csvgrid.Add('x=' + itoa(grid_X_size));
    csvgrid.Add('y=' + itoa(grid_Y_size));

    csvgridtable := TDStringList.Create;
    csvgridtable.Add('x,y,value');

    for i_grid_y := 0 to grid_Y_size - 1 do
    begin
      stmp := '';
      for i_grid_x := 0 to grid_X_size - 1 do
      begin
        g := grid[i_grid_y * grid_X_size + i_grid_x];
        sitem := itoa(g);
        while length(sitem) < 6 do sitem := ' ' + sitem;
        stmp := stmp + sitem + ' ';
        if g <> -1 then
          csvgridtable.Add(itoa(i_grid_x) + ',' + itoa(i_grid_y) + ',' + itoa(g));
      end;
      csvgrid.Add(stmp);
    end;
    
    csvgrid.SaveToFile(path + levelname + '_grid' + itoa(gid) + '.txt');
    csvgrid.Free;

    csvgridtable.SaveToFile(path + levelname + '_gridtable' + itoa(gid) + '.txt');
    csvgridtable.Free;

    memfree(pointer(grid), grid_X_size * grid_Y_size * SizeOf(smallint));
  end;

  procedure AddSectorToCSV(const ss: Pradixsector_t; const id: integer);
  var
    stmp: string;
    ii: integer;
  begin
    if csvsectors.Count = 0 then
      csvsectors.Add(
      'id,'+
      'unknown1_0,'+
      'unknown1_1,' +
      'name,' +
      'floortexture,' +
      'ceilingtexture,' +
      'floorheight,' +
      'ceilingheight,' +
      'lightlevel,' +
      'flags,' +
      'fa,' +
      'fb,' +
      'fc,' +
      'fd,' +
      'ca,' +
      'cb,' +
      'cc,' +
      'cd,' +
      'floorangle,' +
      'ceilingangle,'+
      'heightnodesx_1,' +
      'heightnodesx_2,' +
      'heightnodesx_3,' +
      'floorangle_x,' +
      'heightnodesy_1,' +
      'heightnodesy_2,' +
      'heightnodesy_3,' +
      'floorangle_y,' +
      'floorheight_1,' +
      'floorheight_2,' +
      'floorheight_3,' +
      'ceilingangle_x,' +
      'ceilingheight_1,' +
      'ceilingheight_2,' +
      'ceilingheight_3,' +
      'ceilingangle_y');

    stmp := itoa(id) + ',' + itoa(ss._unknown1[0]) + ',' + itoa(ss._unknown1[1]) + ',';

    ii := 0;
    while ii < RADIXSECTORNAMESIZE do
    begin
      if ss.nameid[ii] = #0 then
        break
      else
        stmp := stmp + ss.nameid[ii];
      inc(ii);
    end;
    stmp := stmp + ',';

    stmp := stmp +
    itoa(ss.floortexture) + ',' +
    itoa(ss.ceilingtexture) + ',' +
    itoa(ss.floorheight) + ',' +
    itoa(ss.ceilingheight) + ',' +
    itoa(ss.lightlevel) + ',' +
    itoa(ss.flags) + ',' +
    itoa(ss.fa) + ',' +
    itoa(ss.fb) + ',' +
    itoa(ss.fc) + ',' +
    itoa(ss.fd) + ',' +
    itoa(ss.ca) + ',' +
    itoa(ss.cb) + ',' +
    itoa(ss.cc) + ',' +
    itoa(ss.cd) + ',' +
    itoa(ss.floorangle) + ',' +
    itoa(ss.ceilingangle) + ',';

    stmp := stmp +
    itoa(ss.heightnodesx[0]) + ',' +
    itoa(ss.heightnodesx[1]) + ',' +
    itoa(ss.heightnodesx[2]) + ',' +
    itoa(ss.floorangle_x) + ',' +
    itoa(ss.heightnodesy[0]) + ',' +
    itoa(ss.heightnodesy[1]) + ',' +
    itoa(ss.heightnodesy[2]) + ',' +
    itoa(ss.floorangle_y) + ',';

    stmp := stmp +
    itoa(ss.floorheights[0]) + ',' +
    itoa(ss.floorheights[1]) + ',' +
    itoa(ss.floorheights[2]) + ',' +
    itoa(ss.ceilingangle_x) + ',' +
    itoa(ss.ceilingheights[0]) + ',' +
    itoa(ss.ceilingheights[1]) + ',' +
    itoa(ss.ceilingheights[2]) + ',' +
    itoa(ss.ceilingangle_y) + ',';

    csvsectors.Add(stmp);
  end;

  procedure AddWallToCSV(const w: Pradixwall_t; const id: integer);
  var
    ii: integer;
    stmp: string;
  begin
    if csvwalls.Count = 0 then
    begin
      stmp := 'id,';
      for ii := 0 to 9 do
        stmp := stmp + 'unknown1_' + itoa(ii) + ',';

      stmp := stmp + 'v1_x' + ',';
      stmp := stmp + 'v1_y' + ',';
      stmp := stmp + 'v2_x' + ',';
      stmp := stmp + 'v2_y' + ',';
      stmp := stmp + 'frontsector' + ',';
      stmp := stmp + 'backsector' + ',';

      for ii := 0 to 41 do
      stmp := stmp + 'unknown2_' + itoa(ii) + ',';

      stmp := stmp + 'flags' + ',';

      stmp := stmp + 'bitmapoffset' + ',';

      stmp := stmp + 'floortexture' + ',';
      stmp := stmp + 'ceilingtexture' + ',';
      stmp := stmp + 'hitpoints' + ',';
      stmp := stmp + 'trigger' + ',';

      csvwalls.Add(stmp);
    end;

    stmp := itoa(id) + ',';
    for ii := 0 to 9 do
      stmp := stmp + itoa(w._unknown1[ii]) + ',';

    stmp := stmp + itoa(w.v1_x) + ',';
    stmp := stmp + itoa(w.v1_y) + ',';
    stmp := stmp + itoa(w.v2_x) + ',';
    stmp := stmp + itoa(w.v2_y) + ',';
    stmp := stmp + itoa(w.frontsector) + ',';
    stmp := stmp + itoa(w.backsector) + ',';

    for ii := 0 to 41 do
    stmp := stmp + itoa(w._unknown2[ii]) + ',';

    stmp := stmp + itoa(w.flags) + ',';
    stmp := stmp + itoa(w.bitmapoffset) + ',';
    stmp := stmp + itoa(w.wfloortexture) + ',';
    stmp := stmp + itoa(w.wceilingtexture) + ',';

    stmp := stmp + itoa(w.hitpoints) + ',';
    stmp := stmp + itoa(w.trigger) + ',';

    csvwalls.Add(stmp);
  end;

begin
  ms := TAttachableMemoryStream.Create;
  ms.Attach(rlevel, rsize);

  // Read Radix level header
  ms.Read(header, SizeOf(radixlevelheader_t));
  if header.id <> RADIXMAPMAGIC then
  begin
    result := false;
    ms.Free;
    exit;
  end;
  result := true;

  path := apath;
  if path <> '' then
    if path[length(path)] <> '\' then
      path := path + '\';

  // Read Radix sectors
  rsectors := malloc(header.numsectors * SizeOf(radixsector_t));
  ms.Read(rsectors^, header.numsectors * SizeOf(radixsector_t));

  // Read Radix walls
  rwalls := malloc(header.numwalls * SizeOf(radixwall_t));
  ms.Read(rwalls^, header.numwalls * SizeOf(radixwall_t));

  // Read and unpack the 320x128 or 1280x32 grid (RLE compressed)
  // Used for advancing the position of input stream
  ReadRadixGridAndCreateCSV(1);

  // Read Radix things
  rthings := malloc(header.numthings * SizeOf(radixthing_t));
  ms.Read(rthings^, header.numthings * SizeOf(radixthing_t));

  // Read trigger's grid
  ReadRadixGridAndCreateCSV(2);

  // Read Radix sprites
  rsprites := mallocz(header.numsprites * SizeOf(radixsprite_t)); // SOS -> use mallocz
  for i := 0 to header.numsprites - 1 do
  begin
    ms.Read(rsprites[i], 40); // Read the first 40 bytes
    ms.Read(rsprites[i].params, rsprites[i].extradata);
  end;

  // Read Radix triggers
  rtriggers := mallocz(header.numtriggers * SizeOf(radixtrigger_t)); // SOS -> use mallocz
  for i := 0 to header.numtriggers - 1 do
  begin
    ms.Read(rtriggers[i], 34); // Read the first 34 bytes
    for j := 0 to rtriggers[i].numsprites - 1 do
      ms.Read(rtriggers[i].sprites[j], SizeOf(radixspritetrigger_t));
  end;

  // Read final grid ?
//  ReadRadixGridAndCreateCSV(3);

  csvsectors := TDStringList.Create;
  csvwalls := TDStringList.Create;
  csvthings := TDStringList.Create;
  csvsprites := TDStringList.Create;
  csvtriggers := TDStringList.Create;

  // Add Sectors to CSV
  for i := 0 to header.numsectors - 1 do
    AddSectorToCSV(@rsectors[i], i);

  // Add Walls to CSV
  for i := 0 to header.numwalls - 1 do
    AddWallToCSV(@rwalls[i], i);

  // Add Things to CSV
  for i := 0 to header.numthings - 1 do
  begin
//    if rthings[i].radix_type > 0 then
      AddThingToCSV(@rthings[i]);
  end;

  // Add Sprites to CSV
  for i := 0 to header.numsprites - 1 do
    AddSpriteToCSV(@rsprites[i], i);

  // Add Triggers to CSV
  for i := 0 to header.numtriggers - 1 do
    AddTriggerToCSV(@rtriggers[i], i);

  csvsectors.SaveToFile(path + levelname + '_sectors.txt');
  csvwalls.SaveToFile(path + levelname + '_walls.txt');
  csvthings.SaveToFile(path + levelname + '_things.txt');
  csvsprites.SaveToFile(path + levelname + '_sprites.txt');
  csvtriggers.SaveToFile(path + levelname + '_triggers.txt');

  csvsectors.Free;
  csvwalls.Free;
  csvthings.Free;
  csvsprites.Free;
  csvtriggers.Free;

  // Free Radix data
  memfree(pointer(rsectors), header.numsectors * SizeOf(radixsector_t));
  memfree(pointer(rwalls), header.numwalls * SizeOf(radixwall_t));
  memfree(pointer(rthings), header.numthings * SizeOf(radixthing_t));
  memfree(pointer(rsprites), header.numsprites * SizeOf(radixsprite_t));
  memfree(pointer(rtriggers), header.numtriggers * SizeOf(radixtrigger_t));


  ms.Free;
end;

end.

