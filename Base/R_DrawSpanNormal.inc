    if ds_scale = ds64x64 then
    begin
    {$DEFINE SCALE64x64}
    {$UNDEF SCALE128x128}
    {$UNDEF SCALE256x256}
    {$UNDEF SCALE512x512}
    {$UNDEF SCALE1024x1024}
    {$UNDEF SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end
    else if ds_scale = ds128x128 then
    begin
    {$UNDEF SCALE64x64}
    {$DEFINE SCALE128x128}
    {$UNDEF SCALE256x256}
    {$UNDEF SCALE512x512}
    {$UNDEF SCALE1024x1024}
    {$UNDEF SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end
    else if ds_scale = ds256x256 then
    begin
    {$UNDEF SCALE64x64}
    {$UNDEF SCALE128x128}
    {$DEFINE SCALE256x256}
    {$UNDEF SCALE512x512}
    {$UNDEF SCALE1024x1024}
    {$UNDEF SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end
    else if ds_scale = ds512x512 then
    begin
    {$UNDEF SCALE64x64}
    {$UNDEF SCALE128x128}
    {$UNDEF SCALE256x256}
    {$DEFINE SCALE512x512}
    {$UNDEF SCALE1024x1024}
    {$UNDEF SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end
    else if ds_scale = ds1024x1024 then
    begin
    {$UNDEF SCALE64x64}
    {$UNDEF SCALE128x128}
    {$UNDEF SCALE256x256}
    {$UNDEF SCALE512x512}
    {$DEFINE SCALE1024x1024}
    {$UNDEF SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end
    else
    begin
    {$UNDEF SCALE64x64}
    {$UNDEF SCALE128x128}
    {$UNDEF SCALE256x256}
    {$UNDEF SCALE512x512}
    {$UNDEF SCALE1024x1024}
    {$DEFINE SCALE2048x2048}
    {$I R_DrawSpanNormal_Main.inc}
    end;

