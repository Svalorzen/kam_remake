﻿unit KM_RenderUI;
{$I KaM_Remake.inc}
interface
uses
  dglOpenGL,
  {$IFDEF WDC}
  System.Generics.Collections,
  {$ENDIF}
  Controls, Math, KromOGLUtils, StrUtils, SysUtils,
  KM_Defaults, KM_CommonTypes, KM_Points, KM_Pics,
  KM_ResFonts, KM_ResSprites;

type
  TKMAnchors = (anLeft, anTop, anRight, anBottom);
  TKMAnchorsSet = set of TKMAnchors;
  TKMButtonStateSet = set of (bsOver, bsDown, bsDisabled);
  TKMButtonStyle = (bsMenu, bsGame); //Menu buttons are metal, game buttons are stone
  TKMTextAlign = (taLeft, taCenter, taRight);
  TKMTextVAlign = (tvaNone, tvaTop, tvaMiddle, tvaBottom);

  TKMPointDesc = record
    P: TKMPoint;
    Desc: String;
  end;

  TKMRenderUI = class
  private
    {$IFDEF WDC}
    class var ClipXStack: TStack<TKMRangeInt>;
    class var ClipYStack: TStack<TKMRangeInt>;
    {$ENDIF}
    class procedure ApplyClipX        (X1,X2: SmallInt);
    class procedure ApplyClipY        (Y1,Y2: SmallInt);
  public
    class procedure SetupClipX        (X1,X2: SmallInt);
    class procedure SetupClipY        (Y1,Y2: SmallInt);
    class procedure ReleaseClipX;
    class procedure ReleaseClipY;
    class procedure Write3DButton  (aLeft, aTop, aWidth, aHeight: SmallInt; aRX: TRXType; aID: Word; aFlagColor: TColor4;
                                    aState: TKMButtonStateSet; aStyle: TKMButtonStyle; aImageEnabled: Boolean = True);
    class procedure WriteBevel     (aLeft, aTop, aWidth, aHeight: SmallInt; aEdgeAlpha: Single = 1; aBackAlpha: Single = 0.5; aResetTexture: Boolean = True);
    class procedure WritePercentBar(aLeft, aTop, aWidth, aHeight: SmallInt; aPos: Single; aSeam: Single;
                                    aMainColor: Cardinal = icBarColorGreen; aAddColor: Cardinal = icBarColorBlue;
                                    aResetTexture: Boolean = True);
    class procedure WriteReplayBar (aLeft, aTop, aWidth, aHeight: SmallInt; aPos, aPeacetime, aMaxValue: Integer; aMarks: TList<Integer>; aPattern: Word; aHighlightedMark: Integer = -1);
    class procedure WritePicture   (aLeft, aTop, aWidth, aHeight: SmallInt; aAnchors: TKMAnchorsSet; aRX: TRXType; aID: Word;
                                    aEnabled: Boolean = True; aColor: TColor4 = $FFFF00FF; aLightness: Single = 0; aResetTexture: Boolean = True);
    class procedure WritePlot      (aLeft, aTop, aWidth, aHeight: SmallInt; aValues: TKMCardinalArray; aMaxValue: Cardinal;
                                    aColor: TColor4; aLineWidth: Byte);
    class procedure WriteOutline   (aLeft, aTop, aWidth, aHeight, aLineWidth: SmallInt; Col: TColor4);
    class procedure WriteShape     (aLeft, aTop, aWidth, aHeight: SmallInt; Col: TColor4; Outline: TColor4 = $00000000);
    class procedure WritePolyShape (aPoints: array of TKMPoint; aColor: TColor4);
    class procedure WriteLine      (aFromX, aFromY, aToX, aToY: Single; aCol: TColor4; aPattern: Word = $FFFF);
    class procedure WriteText      (aLeft, aTop, aWidth: SmallInt; aText: UnicodeString; aFont: TKMFont; aAlign: TKMTextAlign;
                                    aColor: TColor4 = $FFFFFFFF; aIgnoreMarkup: Boolean = False; aShowMarkup: Boolean = False;
                                    aShowEolSymbol: Boolean = False; aTabWidth: Integer = TAB_WIDTH; aResetTexture: Boolean = True);
    class procedure WriteTexture   (aLeft, aTop, aWidth, aHeight: SmallInt; const aTexture: TTexture; aCol: TColor4);
    class procedure WriteCircle    (aCenterX, aCenterY: SmallInt; aRadius: Byte; aFillColor: TColor4);
    class procedure WriteShadow    (aLeft, aTop, aWidth, aHeight: SmallInt; aBlur: Byte; aCol: TColor4);
  end;


implementation
uses
  KM_Render, KM_Resource;


//X axis uses planes 0,1 and Y axis uses planes 2,3, so that they don't interfere when both axis are
//clipped from both sides
class procedure TKMRenderUI.ApplyClipX(X1,X2: SmallInt);
var
  cp: array[0..3] of Double; //Function uses 8byte floats //ClipPlane X+Y+Z=-D
begin
  glEnable(GL_CLIP_PLANE0);
  glEnable(GL_CLIP_PLANE1);
  FillChar(cp, SizeOf(cp), 0);
  cp[0] := 1; cp[3] := -X1; //Upper edge
  glClipPlane(GL_CLIP_PLANE0, @cp);
  cp[0] := -1; cp[3] := X2; //Lower edge
  glClipPlane(GL_CLIP_PLANE1, @cp);
end;


class procedure TKMRenderUI.ApplyClipY(Y1,Y2: SmallInt);
var
  cp: array[0..3] of Double; //Function uses 8byte floats //ClipPlane X+Y+Z=-D
begin
  glEnable(GL_CLIP_PLANE2);
  glEnable(GL_CLIP_PLANE3);
  FillChar(cp, SizeOf(cp), 0);
  cp[1] := 1; cp[3] := -Y1; //Upper edge
  glClipPlane(GL_CLIP_PLANE2, @cp);
  cp[1] := -1; cp[3] := Y2; //Lower edge
  glClipPlane(GL_CLIP_PLANE3, @cp);
end;


class procedure TKMRenderUI.SetupClipX(X1,X2: SmallInt);
var
  P: TKMRangeInt;
begin
  {$IFDEF WDC}
  if ClipXStack.Count > 0 then
  begin
    P := ClipXStack.Peek;
    ApplyClipX(Max(P.Min, X1), Min(P.Max, X2)); //Make clip areas intersection
  end else
    ApplyClipX(X1,X2);
  ClipXStack.Push(KMRange(X1, X2));
  {$ELSE}
  ApplyClipX(X1,X2);
  {$ENDIF}
end;


class procedure TKMRenderUI.SetupClipY(Y1,Y2: SmallInt);
var
  P: TKMRangeInt;
begin
  {$IFDEF WDC}
  if ClipYStack.Count > 0 then
  begin
    P := ClipYStack.Peek;
    ApplyClipY(Max(P.Min, Y1), Min(P.Max, Y2)); //Make clip areas intersection
  end else
    ApplyClipY(Y1,Y2);
  ClipYStack.Push(KMRange(Y1, Y2));
  {$ELSE}
  ApplyClipY(Y1,Y2);
  {$ENDIF}
end;


//Separate release of clipping planes
class procedure TKMRenderUI.ReleaseClipX;

  procedure ReleaseX;
  begin
    glDisable(GL_CLIP_PLANE0);
    glDisable(GL_CLIP_PLANE1);
  end;

var
  P: TKMRangeInt;
begin
  {$IFDEF WDC}
  if ClipXStack.Count <> 0 then
  begin
    ReleaseX;
    ClipXStack.Pop;
    if ClipXStack.Count <> 0 then
    begin
      P := ClipXStack.Peek;
      ApplyClipX(P.Min, P.Max);
    end;
  end else
  {$ENDIF}
    ReleaseX;
end;


//Separate release of clipping planes
class procedure TKMRenderUI.ReleaseClipY;

  procedure ReleaseY;
  begin
    glDisable(GL_CLIP_PLANE2);
    glDisable(GL_CLIP_PLANE3);
  end;

var
  P: TKMRangeInt;
begin
  {$IFDEF WDC}
  if ClipYStack.Count <> 0 then
  begin
    ReleaseY;
    ClipYStack.Pop;
    if ClipYStack.Count <> 0 then
    begin
      P := ClipYStack.Peek;
      ApplyClipY(P.Min, P.Max);
    end;
  end else
  {$ENDIF}
    ReleaseY;
end;


class procedure TKMRenderUI.Write3DButton(aLeft, aTop, aWidth, aHeight: SmallInt; aRX: TRXType; aID: Word; aFlagColor: TColor4; aState: TKMButtonStateSet; aStyle: TKMButtonStyle; aImageEnabled: Boolean = True);
var
  Down: Byte;
  Chamfer: Byte;
  A,B: TKMPointF;
  InsetX,InsetY: Single;
  c1,c2: Byte;
  BackRX: TRXType;
  BackID: Word;
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  if aStyle = bsMenu then
  begin
    BackRX := rxGuiMain;
    BackID := 9; //GuiMain-3 is a metal background used in main menu
  end else
  begin
    BackRX := rxGui;
    BackID := 402; //Gui-402 is a stone background
  end;

  Down := Byte(bsDown in aState);

  with gGFXData[BackRX, BackID] do
  with gGFXData[BackRX, BackID].Tex do
  if PxWidth * PxHeight <> 0 then //Make sure data was loaded properly
  begin
    A.X := u1 + (u2 - u1) * (aLeft - Down) / 2 / PxWidth;
    B.X := u1 + (u2 - u1) * (aLeft + aWidth - Down) / 2 / PxWidth;
    A.Y := v1 + (v2 - v1) * (aTop - Down) / 2 / PxHeight;
    B.Y := v1 + (v2 - v1) * (aTop + aHeight - Down) / 2 / PxHeight;
    A.X := A.X - (u2 - u1) * ((aLeft + aWidth div 2) div PxWidth) / 2;
    B.X := B.X - (u2 - u1) * ((aLeft + aWidth div 2) div PxWidth) / 2;
    A.Y := A.Y - (v2 - v1) * ((aTop + aHeight div 2) div PxHeight) / 2;
    B.Y := B.Y - (v2 - v1) * ((aTop + aHeight div 2) div PxHeight) / 2;
    A.X := EnsureRange(A.X, u1, u2);
    B.X := EnsureRange(B.X, u1, u2);
    A.Y := EnsureRange(A.Y, v1, v2);
    B.Y := EnsureRange(B.Y, v1, v2);
  end;

  glPushMatrix;
    glTranslatef(aLeft, aTop, 0);

      //Background
      glColor4f(1, 1, 1, 1);
      TRender.BindTexture(gGFXData[BackRX, BackID].Tex.ID);
      glBegin(GL_QUADS);
        glTexCoord2f(A.x,A.y); glVertex2f(0,0);
        glTexCoord2f(B.x,A.y); glVertex2f(aWidth,0);
        glTexCoord2f(B.x,B.y); glVertex2f(aWidth,aHeight);
        glTexCoord2f(A.x,B.y); glVertex2f(0,aHeight);
      glEnd;

      //Render beveled edges
      TRender.BindTexture(0);

      c1 := 1 - Down;
      c2 := Down;
      Chamfer := 2 + Byte(Min(aWidth, aHeight) > 25);

      glPushMatrix;
        //Scale to save on XY+/-Inset coordinates calculations
        glScalef(aWidth, aHeight, 0);
        InsetX := Chamfer / aWidth;
        InsetY := Chamfer / aHeight;
        glBegin(GL_QUADS);
          glColor4f(c1,c1,c1,0.7); glkQuad(0, 0, 1,        0,        1-InsetX, 0+InsetY, 0+InsetX, 0+InsetY);
          glColor4f(c1,c1,c1,0.6); glkQuad(0, 0, 0+InsetX, 0+InsetY, 0+InsetX, 1-InsetY, 0,        1       );
          glColor4f(c2,c2,c2,0.5); glkQuad(1, 0, 1,        1,        1-InsetX, 1-InsetY, 1-InsetX, 0+InsetY);
          glColor4f(c2,c2,c2,0.4); glkQuad(0, 1, 0+InsetX, 1-InsetY, 1-InsetX, 1-InsetY, 1,        1       );
        glEnd;
      glPopMatrix;

    //Render a pic ontop
    if aID <> 0 then
    begin
      glColor4f(1, 1, 1, 1);
      WritePicture(Down, Down, aWidth, aHeight, [], aRX, aID, aImageEnabled, aFlagColor);
    end;

    //Render MouseOver highlight
    if bsOver in aState then
    begin
      glColor4f(1, 1, 1, 0.15);
      glBegin(GL_QUADS);
        glkRect(0, 0, aWidth, aHeight);
      glEnd;
    end;

    //Render darklight when Disabled
    if bsDisabled in aState then
    begin
      glColor4f(0, 0, 0, 0.5);
      glBegin(GL_QUADS);
        glkRect(0, 0, aWidth, aHeight);
      glEnd;
    end;

  glPopMatrix;
end;


class procedure TKMRenderUI.WriteBevel(aLeft, aTop, aWidth, aHeight: SmallInt; aEdgeAlpha: Single = 1; aBackAlpha: Single = 0.5;
                                       aResetTexture: Boolean = True);
begin
  if (aWidth < 0) or (aHeight < 0) then Exit;

  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushMatrix;
    glTranslatef(aLeft, aTop, 0);

    //Background
    glColor4f(0, 0, 0, aBackAlpha);
    glBegin(GL_QUADS);
      glkRect(1, 1, aWidth-1, aHeight-1);
    glEnd;

    //2 Thin outlines rendered on top of background to avoid inset calculations
    if aEdgeAlpha > 0 then
    begin
      //Bright edge
      glBlendFunc(GL_DST_COLOR, GL_ONE);
      glColor3f(0.75 * aEdgeAlpha, 0.75 * aEdgeAlpha, 0.75 * aEdgeAlpha);
      glBegin(GL_LINE_STRIP);
        glVertex2f(aWidth-0.5, 0.5);
        glVertex2f(aWidth-0.5, aHeight-0.5);
        glVertex2f(0.5, aHeight-0.5);
      glEnd;

      //Dark edge
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glColor4f(0, 0, 0, aEdgeAlpha);
      glBegin(GL_LINE_STRIP);
        glVertex2f(0.5, aHeight-0.5);
        glVertex2f(0.5, 0.5);
        glVertex2f(aWidth-0.5, 0.5);
      glEnd;
    end;
  glPopMatrix;
end;


class procedure TKMRenderUI.WritePercentBar(aLeft,aTop,aWidth,aHeight: SmallInt; aPos: Single; aSeam: Single;
                                            aMainColor: Cardinal = icBarColorGreen; aAddColor: Cardinal = icBarColorBlue;
                                            aResetTexture: Boolean = True);
var
  BarWidth: Word;
begin
//  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushMatrix;
    glTranslatef(aLeft, aTop, 0);

    WriteBevel(0, 0, aWidth, aHeight);

    //At least 2px wide to show up from under the shadow
    BarWidth := Round((aWidth - 2) * (aPos)) + 2;
    glColor4ubv(@aMainColor);
    glBegin(GL_QUADS);
      glkRect(1, 1, BarWidth-1, aHeight-1);
    glEnd;

    if (aSeam > 0) then
    begin
      //At least 2px wide to show up from under the shadow
      BarWidth := Round((aWidth - 2) * Min(aPos, aSeam)) + 2;
      glColor4ubv(@aAddColor);
      glBegin(GL_QUADS);
        glkRect(1, 1, BarWidth-1, aHeight-1);
      glEnd;

      //Skip the seam if it matches high border
      if (aSeam < 1) then
        WriteOutline(Round(aSeam * (aWidth - 2)) + 1, 1, 1, aHeight-2, 1, $FFFFFFFF);
    end;

    //Draw shadow on top and left of the bar, just like real one
    glColor4f(0,0,0,0.5); //Set semi-transparent black
    glBegin(GL_LINE_STRIP); //List vertices, order is important
      glVertex2f(1.5,aHeight-1.5);
      glVertex2f(1.5,1.5);
      glVertex2f(aWidth-1.5,1.5);
      glVertex2f(aWidth-1.5,2.5);
      glVertex2f(2.5,2.5);
      glVertex2f(2.5,aHeight-1.5);
    glEnd;
  glPopMatrix;
end;


class procedure TKMRenderUI.WriteReplayBar(aLeft, aTop, aWidth, aHeight: SmallInt; aPos, aPeacetime, aMaxValue: Integer;
                                           aMarks: TList<Integer>; aPattern: Word; aHighlightedMark: Integer = -1);
const
  BAR_COLOR_GREEN: TColor4 = $FF00AA26;
  BAR_COLOR_BLUE: TColor4 = $FFBBAA00;

  function GetPos(aValue: Integer): Word;
  begin
    //At least 2px wide to show up from under the shadow
    Result := Min( High(Word), Round((aWidth - 2) * (Max(0, aValue - 1)/ aMaxValue)) + 2);  //-1 just to draw 1st tick in a better way...
  end;

  procedure WriteWideLine(aX: Word; aColor: Cardinal; aPattern: Word = $FFFF);
  begin
    if InRange(aX, 0, aWidth) then  //Dont allow to render outside of control
    begin
      //Just draw 2 lines...
      WriteLine(aX,     1, aX    , aHeight - 1, aColor, aPattern);
      WriteLine(aX - 1, 1, aX - 1, aHeight - 1, aColor, aPattern);
    end;
  end;

var
  PTPos, Pos: Word;
  Mark: Integer;
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushMatrix;
    glTranslatef(aLeft, aTop, 0);

    WriteBevel(0, 0, aWidth, aHeight);

    PTPos := GetPos(aPeacetime);
    Pos := GetPos(aPos);

    if aPos < aPeacetime then
    begin
      glColor4ubv(@BAR_COLOR_GREEN);
      glBegin(GL_QUADS);
        glkRect(1, 1, Pos - 1, aHeight - 1);
      glEnd;

      WriteWideLine(PTPos, icCyan);
    end
    else
    begin
      glColor4ubv(@BAR_COLOR_GREEN);
      glBegin(GL_QUADS);
        glkRect(1, 1, PTPos, aHeight - 1);
      glEnd;

      glColor4ubv(@BAR_COLOR_BLUE);
      glBegin(GL_QUADS);
        glkRect(PTPos, 1, Pos - 1, aHeight - 1);
      glEnd;
    end;

    for Mark in aMarks do
      WriteWideLine(GetPos(Mark), icYellow, aPattern);

    if aHighlightedMark <> -1 then
      WriteWideLine(GetPos(aHighlightedMark), icOrange);

    //Draw shadow on top and left of the bar, just like real one
    glColor4f(0, 0, 0, 0.5); //Set semi-transparent black
    glBegin(GL_LINE_STRIP); //List vertices, order is important
      glVertex2f(1.5, aHeight - 1.5);
      glVertex2f(1.5, 1.5);
      glVertex2f(aWidth - 1.5, 1.5);
      glVertex2f(aWidth - 1.5, 2.5);
      glVertex2f(2.5, 2.5);
      glVertex2f(2.5, aHeight - 1.5);
    glEnd;
  glPopMatrix;
end;


class procedure TKMRenderUI.WritePicture(aLeft, aTop, aWidth, aHeight: SmallInt; aAnchors: TKMAnchorsSet; aRX: TRXType;
                                         aID: Word; aEnabled: Boolean = True; aColor: TColor4 = $FFFF00FF; aLightness: Single = 0;
                                         aResetTexture: Boolean = True);
var
  OffX, OffY: Integer;
  DrawWidth, DrawHeight: Integer;
begin
  if aID = 0 then Exit;

  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  OffX  := 0;
  OffY  := 0;
  DrawWidth   := gGFXData[aRX, aID].PxWidth;
  DrawHeight  := gGFXData[aRX, aID].PxHeight;

  //Both aAnchors means that we will need to stretch the image
  if (anLeft in aAnchors) and (anRight in aAnchors) then
    DrawWidth := aWidth
  else
  if anLeft in aAnchors then
    //Use defaults
  else
  if anRight in aAnchors then
    OffX := aWidth - DrawWidth
  else
    //No aAnchors means: draw the image in center
    OffX := (aWidth - DrawWidth) div 2;

  if (anTop in aAnchors) and (anBottom in aAnchors) then
    DrawHeight  := aHeight
  else
  if anTop in aAnchors then
    //Use defaults
  else
  if anBottom in aAnchors then
    OffY := aHeight - DrawHeight
  else
    OffY := (aHeight - DrawHeight) div 2;

  with gGFXData[aRX, aID] do
  begin
    glPushMatrix;
      glTranslatef(aLeft + OffX, aTop + OffY, 0);

      //Base layer
      TRender.BindTexture(Tex.ID);
      if aEnabled then glColor3f(1,1,1) else glColor3f(0.33,0.33,0.33);
      glBegin(GL_QUADS);
        glTexCoord2f(Tex.u1,Tex.v1); glVertex2f(0            , 0             );
        glTexCoord2f(Tex.u2,Tex.v1); glVertex2f(0 + DrawWidth, 0             );
        glTexCoord2f(Tex.u2,Tex.v2); glVertex2f(0 + DrawWidth, 0 + DrawHeight);
        glTexCoord2f(Tex.u1,Tex.v2); glVertex2f(0            , 0 + DrawHeight);
      glEnd;

      //Color overlay for unit icons and scrolls
      if Alt.ID <> 0 then
      begin
        TRender.BindTexture(Alt.ID);
        if aEnabled then
          glColor3ub(aColor AND $FF, aColor SHR 8 AND $FF, aColor SHR 16 AND $FF)
        else
          glColor3f(aColor AND $FF / 768, aColor SHR 8 AND $FF / 768, aColor SHR 16 AND $FF / 768);
        glBegin(GL_QUADS);
          glTexCoord2f(Alt.u1,Alt.v1); glVertex2f(0            , 0             );
          glTexCoord2f(Alt.u2,Alt.v1); glVertex2f(0 + DrawWidth, 0             );
          glTexCoord2f(Alt.u2,Alt.v2); glVertex2f(0 + DrawWidth, 0 + DrawHeight);
          glTexCoord2f(Alt.u1,Alt.v2); glVertex2f(0            , 0 + DrawHeight);
        glEnd;
      end;

      //Highlight for active/focused/mouseOver images
      if aLightness <> 0 then
      begin
        TRender.BindTexture(Tex.ID); //Replace AltID if it was used
        if aLightness > 0 then
          glBlendFunc(GL_SRC_ALPHA, GL_ONE)
        else begin
          glBlendFunc(GL_SRC_ALPHA, GL_ZERO);
          aLightness := 1-Abs(aLightness);
        end;
        glColor3f(aLightness, aLightness, aLightness);
        glBegin(GL_QUADS);
          glTexCoord2f(Tex.u1,Tex.v1); glVertex2f(0            , 0             );
          glTexCoord2f(Tex.u2,Tex.v1); glVertex2f(0 + DrawWidth, 0             );
          glTexCoord2f(Tex.u2,Tex.v2); glVertex2f(0 + DrawWidth, 0 + DrawHeight);
          glTexCoord2f(Tex.u1,Tex.v2); glVertex2f(0            , 0 + DrawHeight);
        glEnd;
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      end;

    glPopMatrix;
  end;
  if aResetTexture then
    TRender.BindTexture(0);
end;


class procedure TKMRenderUI.WritePlot(aLeft,aTop,aWidth,aHeight: SmallInt; aValues: TKMCardinalArray; aMaxValue: Cardinal; aColor: TColor4; aLineWidth: Byte);
var
  I: Integer;
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushAttrib(GL_LINE_BIT);
  glPushMatrix;
    //glEnable(GL_LINE_SMOOTH); //Smooth lines actually look odd in KaM
    glTranslatef(aLeft, aTop, 0);
    glLineWidth(aLineWidth);
    glColor4ubv(@aColor);
    glBegin(GL_LINE_STRIP);
      for I := 0 to High(aValues) do
        glVertex2f(I / High(aValues) * aWidth, aHeight - aValues[I] / aMaxValue * aHeight);
    glEnd;
  glPopAttrib;
  glPopMatrix;
end;


class procedure TKMRenderUI.WriteOutline(aLeft, aTop, aWidth, aHeight, aLineWidth: SmallInt; Col: TColor4);
begin
  if aLineWidth = 0 then Exit;

  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushAttrib(GL_LINE_BIT);
    glLineWidth(aLineWidth);
    glColor4ubv(@Col);
    glBegin(GL_LINE_LOOP);
      glkRect(aLeft + aLineWidth / 2, aTop + aLineWidth / 2, aLeft + aWidth - aLineWidth / 2, aTop + aHeight - aLineWidth / 2);
    glEnd;
  glPopAttrib;
end;


//Renders plane with given color and optional 1px outline
class procedure TKMRenderUI.WriteShape(aLeft, aTop, aWidth, aHeight: SmallInt; Col: TColor4; Outline: TColor4 = $00000000);
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushAttrib(GL_LINE_BIT);
    glColor4ubv(@Col);
    glBegin(GL_QUADS);
      glkRect(aLeft, aTop, aLeft + aWidth, aTop + aHeight);
    glEnd;
    glLineWidth(1);
    glColor4ubv(@Outline);
    glBegin(GL_LINE_LOOP);
      glkRect(aLeft + 0.5, aTop + 0.5, aLeft + aWidth - 0.5, aTop + aHeight - 0.5);
    glEnd;
  glPopAttrib;
end;


//Renders polygon shape with given color
class procedure TKMRenderUI.WritePolyShape(aPoints: array of TKMPoint; aColor: TColor4);
var I: Integer;
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glColor4ubv(@aColor);
  glBegin(GL_POLYGON);
    for I := 0 to High(aPoints) do
    begin
      glVertex2f(aPoints[I].X, aPoints[I].Y);
    end;
  glEnd;
end;


class procedure TKMRenderUI.WriteLine(aFromX, aFromY, aToX, aToY: Single; aCol: TColor4; aPattern: Word = $FFFF);
begin
  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glColor4ubv(@aCol);

  glEnable(GL_LINE_STIPPLE);
  glLineStipple(2, aPattern);

  glBegin(GL_LINES);
    glVertex2f(aFromX, aFromY);
    glVertex2f(aToX, aToY);
  glEnd;
  glDisable(GL_LINE_STIPPLE);
end;


{Renders a line of text}
{By default color must be non-transparent white}
class procedure TKMRenderUI.WriteText(aLeft, aTop, aWidth: SmallInt; aText: UnicodeString; aFont: TKMFont; aAlign: TKMTextAlign;
                                      aColor: TColor4 = $FFFFFFFF; aIgnoreMarkup: Boolean = False; aShowMarkup: Boolean = False;
                                      aShowEolSymbol: Boolean = False; aTabWidth: Integer = TAB_WIDTH; aResetTexture: Boolean = True);
var
  I, K, Off: Integer;
  LineCount,dx,dy,LineHeight,BlockWidth,PrevAtlas, LineWidthInc: Integer;
  LineWidth: array of Integer; //Use signed format since some fonts may have negative CharSpacing
  FontData: TKMFontData;
  Let: TKMLetter;
  TmpColor: Integer;
  Colors: array of record
    FirstChar: Word;
    Color: TColor4;
  end;

  procedure DrawLetter;
  begin
    Let := FontData.GetLetter(aText[I]);

    if (PrevAtlas = -1) or (PrevAtlas <> Let.AtlasId) then
    begin
      if PrevAtlas <> -1 then
        glEnd; //End previous draw
      PrevAtlas := Let.AtlasId;
      TRender.BindTexture(FontData.TexID[Let.AtlasId]);
      glBegin(GL_QUADS);
    end;

    glTexCoord2f(Let.u1, Let.v1); glVertex2f(dx            , dy            + Let.YOffset);
    glTexCoord2f(Let.u2, Let.v1); glVertex2f(dx + Let.Width, dy            + Let.YOffset);
    glTexCoord2f(Let.u2, Let.v2); glVertex2f(dx + Let.Width, dy+Let.Height + Let.YOffset);
    glTexCoord2f(Let.u1, Let.v2); glVertex2f(dx            , dy+Let.Height + Let.YOffset);
    Inc(dx, Let.Width + FontData.CharSpacing);
  end;

var
  SetupClipXApplied: Boolean;
begin
  if (aText = '') or (aColor = $00000000) then Exit;

  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  SetLength(Colors, 0);

  SetupClipXApplied := aWidth <> 0;
  if SetupClipXApplied then
    SetupClipX(aLeft, aLeft + aWidth);

  //Look for [$FFFFFF][] patterns that markup text color
  Off := 1;
  if not aIgnoreMarkup then
  repeat
    I := PosEx('[', aText, Off);

    //Check for reset
    if (I <> 0) and (I+1 <= Length(aText)) and (aText[I+1] = ']') then
    begin
      SetLength(Colors, Length(Colors) + 1);
      Colors[High(Colors)].FirstChar := I;
      Colors[High(Colors)].Color := 0;
      if not aShowMarkup then Delete(aText, I, 2);
    end;

    //Check for new color
    if (I <> 0) and (I+8 <= Length(aText))
    and (aText[I+1] = '$') and (aText[I+8] = ']')
    and TryStrToInt(Copy(aText, I+1, 7), TmpColor) then
    begin
      SetLength(Colors, Length(Colors) + 1);
      Colors[High(Colors)].FirstChar := I;
      if aShowMarkup then
        Inc(Colors[High(Colors)].FirstChar, 9); //Don't color the markup itself
      Colors[High(Colors)].Color := Abs(TmpColor) or $FF000000;
      if not aShowMarkup then
      begin
        Delete(aText, I, 9);
        Off := I; //We could try to find 1 more color right after this one (could happen in case of wrap colors)
      end else
        Off := I + 1; //Continue search from the next letter
    end
    else
      Off := I + 1; //Continue search from the next letter

  until(I = 0);


  FontData := gRes.Fonts[aFont]; //Shortcut

  //Calculate line count and each lines width to be able to properly aAlign them
  LineCount := 1;
  if not aShowEolSymbol then
    for I := 1 to Length(aText) do
      if aText[I] = #124 then
        Inc(LineCount);

  SetLength(LineWidth, LineCount+2); //1..n+1 (for last line)

  LineCount := 1;

  for I := 1 to Length(aText) do
  begin
    if aText[I] = #9 then // Tab char
      LineWidthInc := (Floor(LineWidth[LineCount] / aTabWidth) + 1) * aTabWidth - LineWidth[LineCount]
    else
      LineWidthInc := FontData.GetCharWidth(aText[I], aShowEolSymbol);
    Inc(LineWidth[LineCount], LineWidthInc);

    //If EOL or aText end
    if (not aShowEolSymbol and (aText[I] = #124)) or (I = Length(aText)) then
    begin
      if aText[I] <> #9 then // for Tab reduce line width for CharSpacing and also for TAB 'jump'
        LineWidthInc := 0;
      LineWidth[LineCount] := Math.max(0, LineWidth[LineCount] - FontData.CharSpacing - LineWidthInc); //Remove last interletter space and negate double EOLs
      Inc(LineCount);
    end;
  end;

  LineHeight := FontData.BaseHeight + FontData.LineSpacing;

  dec(LineCount);
  BlockWidth := 0;
  for I := 1 to LineCount do
    BlockWidth := Math.Max(BlockWidth, LineWidth[I]);

  case aAlign of
    taLeft:   dx := aLeft;
    taCenter: dx := aLeft + (aWidth - LineWidth[1]) div 2;
    taRight:  dx := aLeft + aWidth - LineWidth[1];
    else      dx := aLeft;
  end;
  dy := aTop;
  LineCount := 1;

  glColor4ubv(@aColor);

  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  K := 0;
  PrevAtlas := -1;
  for I := 1 to Length(aText) do
  begin
    //Loop as there might be adjoined tags on same position
    while (K < Length(Colors)) and (I = Colors[K].FirstChar) do
    begin
      if Colors[K].Color = 0 then
        glColor4ubv(@aColor)
      else
        glColor4ubv(@Colors[K].Color);
      Inc(K);
    end;

    case aText[I] of
      #9:   dx := aLeft + (Floor((dx - aLeft) / aTabWidth) + 1) * aTabWidth;
      #32:  Inc(dx, FontData.WordSpacing);
      #124: if aShowEolSymbol then
              DrawLetter
            else begin
              //KaM uses #124 or vertical bar (|) for new lines in the LIB files,
              //so lets do the same here. Saves complex conversions...
              Inc(dy, LineHeight);
              Inc(LineCount);
              case aAlign of
                taLeft:   dx := aLeft;
                taCenter: dx := aLeft + (aWidth - LineWidth[LineCount]) div 2;
                taRight:  dx := aLeft + aWidth - LineWidth[LineCount];
              end;
            end;
      else  DrawLetter;
    end;
    //When we reach the end, if we painted something then we need to end it
    if (I = Length(aText)) and (PrevAtlas <> -1) then
      glEnd;
  end;

  if aResetTexture then
    TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  if SHOW_TEXT_OUTLINES then
  begin
    glPushMatrix;
      case aAlign of
        taLeft:   glTranslatef(aLeft,                               aTop, 0);
        taCenter: glTranslatef(aLeft + (aWidth - BlockWidth) div 2, aTop, 0);
        taRight:  glTranslatef(aLeft + (aWidth - BlockWidth),       aTop, 0);
      end;

      glColor4f(1,0,0,0.5);
      glBegin(GL_LINE_LOOP);
        glVertex2f(0.5           , 0.5       );
        glVertex2f(BlockWidth+0.5, 0.5       );
        glVertex2f(BlockWidth+0.5, LineHeight*LineCount+0.5);
        glVertex2f(0.5           , LineHeight*LineCount+0.5);
      glEnd;

      glBegin(GL_LINE_LOOP);
        glVertex2f(0.5           , 0.5       );
        glVertex2f(BlockWidth+0.5, 0.5       );
        glVertex2f(BlockWidth+0.5, LineHeight+0.5);
        glVertex2f(0.5           , LineHeight+0.5);
      glEnd;
    glPopMatrix;
  end;

  if SetupClipXApplied then
    ReleaseClipX;
end;


class procedure TKMRenderUI.WriteTexture(aLeft, aTop, aWidth, aHeight: SmallInt; const aTexture: TTexture; aCol: TColor4);
begin
  TRender.BindTexture(aTexture.Tex);

  glColor4ubv(@aCol);
  glBegin(GL_QUADS);
    glTexCoord2f(0, 0);                   glVertex2f(aLeft, aTop);
    glTexCoord2f(aTexture.U, 0);          glVertex2f(aLeft+aWidth, aTop);
    glTexCoord2f(aTexture.U, aTexture.V); glVertex2f(aLeft+aWidth, aTop+aHeight);
    glTexCoord2f(0, aTexture.V);          glVertex2f(aLeft, aTop+aHeight);
  glEnd;

  TRender.BindTexture(0);
end;


class procedure TKMRenderUI.WriteCircle(aCenterX, aCenterY: SmallInt; aRadius: Byte; aFillColor: TColor4);
var
  Ang: Single;
  I: Byte;
begin
  if aRadius = 0 then Exit;

  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glColor4ubv(@aFillColor);
  glBegin(GL_POLYGON);
    for I := 0 to 15 do
    begin
      Ang := I / 8 * Pi;
      glVertex2f(aCenterX + Sin(Ang) * aRadius, aCenterY + Cos(Ang) * aRadius);
    end;
  glEnd;
end;


class procedure TKMRenderUI.WriteShadow(aLeft, aTop, aWidth, aHeight: SmallInt; aBlur: Byte; aCol: TColor4);
  procedure DoNode(aX, aY: Single; aColor: TColor4);
  begin
    glColor4ubv(@aColor);
    glVertex2f(aX, aY);
  end;
var
  bCol: TColor4;
begin
  //Same color, but fully transparent
  bCol := aCol and $FFFFFF;

  TRender.BindTexture(0); // We have to reset texture to default (0), because it could be bind to any other texture (atlas)

  glPushMatrix;
    //Slightly shifted shadow looks nicer
    glTranslatef(aLeft + aBlur / 8, aTop + aBlur / 6, 0);

    glColor4ubv(@aCol);
    glBegin(GL_QUADS);
      glkRect(0, 0, aWidth, aHeight);
    glEnd;

    glBegin(GL_QUAD_STRIP);
      DoNode(-aBlur, 0, bCol);
      DoNode(0, 0, aCol);
      DoNode(-aBlur * 0.7, -aBlur * 0.7, bCol);
      DoNode(0, 0, aCol);
      DoNode(0, -aBlur, bCol);
      DoNode(0, 0, aCol);

      DoNode(aWidth, -aBlur, bCol);
      DoNode(aWidth, 0, aCol);
      DoNode(aWidth + aBlur * 0.7, -aBlur * 0.7, bCol);
      DoNode(aWidth, 0, aCol);
      DoNode(aWidth + aBlur, 0, bCol);
      DoNode(aWidth, 0, aCol);

      DoNode(aWidth + aBlur, aHeight, bCol);
      DoNode(aWidth, aHeight, aCol);
      DoNode(aWidth + aBlur * 0.7, aHeight + aBlur * 0.7, bCol);
      DoNode(aWidth, aHeight, aCol);
      DoNode(aWidth, aHeight + aBlur, bCol);
      DoNode(aWidth, aHeight, aCol);

      DoNode(0, aHeight + aBlur, bCol);
      DoNode(0, aHeight, aCol);
      DoNode(-aBlur * 0.7, aHeight + aBlur * 0.7, bCol);
      DoNode(0, aHeight, aCol);
      DoNode(-aBlur, aHeight, bCol);
      DoNode(0, aHeight, aCol);

      DoNode(-aBlur, 0, bCol);
      DoNode(0, 0, aCol);
    glEnd;
  glPopMatrix;
end;


initialization
begin
  {$IFDEF WDC}
  TKMRenderUI.ClipXStack := TStack<TKMRangeInt>.Create;
  TKMRenderUI.ClipYStack := TStack<TKMRangeInt>.Create;
  {$ENDIF}
end;


finalization
begin
  {$IFDEF WDC}
  TKMRenderUI.ClipXStack.Free;
  TKMRenderUI.ClipYStack.Free;
  {$ENDIF}
end;


end.
