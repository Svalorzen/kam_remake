unit KM_HandSpectator;
{$I KaM_Remake.inc}
interface
uses
  KM_Hand, KM_FogOfWar,
  KM_CommonClasses, KM_Defaults;


type
  //Wrap to let choose FOW player sees (and let 1 player control several towns
  //or several players to control 1 town in future)
  TKMSpectator = class
  private
    fHandIndex: TKMHandID;
    fHighlight: TObject; //Unit/House/Group that is shown highlighted to draw players attention
    fHighlightEnd: Cardinal; //Highlight has a short time to live
    fSelected: TObject;
    fLastSelected: TObject;
    fIsSelectedMyObj: Boolean; // We can select ally's house/unit
    fLastSpecSelectedObjUID: array [0..MAX_HANDS-1] of Integer; //UIDs of last selected objects for each hand while spectating/watching replay
    fFOWIndex: TKMHandID; //Unit/House/Group selected by player and shown in UI
    fFogOfWarOpen: TKMFogOfWarOpen; //Stub for MapEd
    fFogOfWar: TKMFogOfWarCommon; //Pointer to current FOW view, updated by UpdateFogOfWarIndex
    procedure SetHighlight(Value: TObject);
    procedure SetSelected(Value: TObject);
    procedure SetHandIndex(const Value: TKMHandID);
    procedure SetFOWIndex(const Value: TKMHandID);
    procedure UpdateFogOfWarIndex;
    function GetLastSpecSelectedObj: TObject;
    function IsLastSelectObjectValid(aObject: TObject): Boolean;
    procedure UpdateNewSelected(var aNewSelected: TObject; aAllowSelectAllies: Boolean = False); overload;
  public
    constructor Create(aHandIndex: TKMHandID);
    destructor Destroy; override;
    property Highlight: TObject read fHighlight write SetHighlight;
    property Selected: TObject read fSelected write SetSelected;
    property LastSelected: TObject read fLastSelected;
    property IsSelectedMyObj: Boolean read fIsSelectedMyObj write fIsSelectedMyObj;
    function Hand: TKMHand;
    property HandID: TKMHandID read fHandIndex write SetHandIndex;
    property FOWIndex: TKMHandID read fFOWIndex write SetFOWIndex;
    property FogOfWar: TKMFogOfWarCommon read fFogOfWar;
    property LastSpecSelectedObj: TObject read GetLastSpecSelectedObj;
    function HitTestCursor(aIncludeAnimals: Boolean = False): TObject;
    function HitTestCursorWGroup(aIncludeAnimals: Boolean = False): TObject;
    procedure UpdateNewSelected; overload;
    procedure UpdateSelect;
    procedure Load(LoadStream: TKMemoryStream);
    procedure Save(SaveStream: TKMemoryStream);
    procedure UpdateState(aTick: Cardinal);
  end;


implementation
uses
  KM_Game, KM_GameCursor, KM_HandsCollection,
  KM_Units, KM_UnitGroup, KM_UnitWarrior, KM_Houses,
  KM_Utils, KM_CommonUtils,
  KM_GameTypes;


{ TKMSpectator }
constructor TKMSpectator.Create(aHandIndex: TKMHandID);
var
  I: Integer;
begin
  inherited Create;

  fHandIndex := aHandIndex;

  //Stub that always returns REVEALED
  fFogOfWarOpen := TKMFogOfWarOpen.Create;
  UpdateFogOfWarIndex;

  for I := Low(fLastSpecSelectedObjUID) to High(fLastSpecSelectedObjUID) do
    fLastSpecSelectedObjUID[I] := UID_NONE;
end;


destructor TKMSpectator.Destroy;
begin
  Highlight := nil;
  Selected := nil;
  fFogOfWarOpen.Free;
  inherited;
end;


procedure TKMSpectator.UpdateFogOfWarIndex;
begin
  //fGame = nil in Tests
  if (gGame <> nil) and (gGame.GameMode in [gmMultiSpectate, gmMapEd, gmReplaySingle, gmReplayMulti]) then
    if FOWIndex = -1 then
      fFogOfWar := fFogOfWarOpen
    else
      fFogOfWar := gHands[FOWIndex].FogOfWar
  else
    fFogOfWar := gHands[HandID].FogOfWar;
end;


//Return last seleted object for current chosen hand
function TKMSpectator.GetLastSpecSelectedObj: TObject;
var
  Obj: TObject;
  UID: Integer;
begin
  Result := nil;
  UID := fLastSpecSelectedObjUID[fHandIndex];
  if UID <> UID_NONE then
  begin
    Obj := gHands.GetObjectByUID(UID);
    if IsLastSelectObjectValid(Obj) then
      Result := Obj
    else
      fLastSpecSelectedObjUID[fHandIndex] := UID_NONE;  // Last selected object is not valid anymore, so reset UID
  end;
end;


function TKMSpectator.IsLastSelectObjectValid(aObject: TObject): Boolean;
begin
  Result := (aObject <> nil)
    and not ((aObject is TKMUnit) and TKMUnit(aObject).IsDeadOrDying)    //Don't allow the player to select dead units
    and not (aObject is TKMUnitAnimal)                                   //...or animals
    and not ((aObject is TKMUnitGroup) and TKMUnitGroup(aObject).IsDead) //We can not select dead groups (with no warriors)
    and not ((aObject is TKMHouse) and TKMHouse(aObject).IsDestroyed);   //Don't allow the player to select destroyed houses
end;


procedure TKMSpectator.Load(LoadStream: TKMemoryStream);
begin
  LoadStream.CheckMarker('Spectator');
  LoadStream.Read(fHandIndex);
  UpdateFogOfWarIndex;
end;


procedure TKMSpectator.Save(SaveStream: TKMemoryStream);
begin
  SaveStream.PlaceMarker('Spectator');
  SaveStream.Write(fHandIndex);
end;


function TKMSpectator.Hand: TKMHand;
begin
  Result := gHands[fHandIndex];
end;


//Test if there's object below that player can interact with
//Units and Houses, not Groups
function TKMSpectator.HitTestCursor(aIncludeAnimals: Boolean = False): TObject;
begin
  Result := gHands.GetUnitByUID(gGameCursor.ObjectUID);
  if ((Result is TKMUnit) and TKMUnit(Result).IsDeadOrDying)
  or ((Result is TKMUnitAnimal) and not aIncludeAnimals) then
    Result := nil;

  //If there's no unit try pick a house on the Cell below
  if Result = nil then
  begin
    Result := gHands.HousesHitTest(gGameCursor.Cell.X, gGameCursor.Cell.Y);
    if (Result is TKMHouse) and TKMHouse(Result).IsDestroyed then
      Result := nil;
  end;
end;


//Test if there's object below that player can interact with
//Units and Houses and Groups
function TKMSpectator.HitTestCursorWGroup(aIncludeAnimals: Boolean = False): TObject;
var
  G: TKMUnitGroup;
begin
  Result := HitTestCursor(aIncludeAnimals);

  if Result is TKMUnitWarrior then
  begin
    if gGame.GameMode in [gmMultiSpectate, gmMapEd, gmReplaySingle, gmReplayMulti]  then
      G := gHands.GetGroupByMember(TKMUnitWarrior(Result))
    else
      G := gHands[fHandIndex].UnitGroups.GetGroupByMember(TKMUnitWarrior(Result));

    //Warrior might not be assigned to a group while walking out of the Barracks
    if G <> nil then
      Result := G
    else
      Result := nil; //Can't select warriors until they have been assigned a group
  end;
end;


procedure TKMSpectator.UpdateNewSelected;
var
  TmpSelected: TObject;
begin
  //We do not want to change Selected object actually, just update fIsSelectedMyObj field is good enought
  TmpSelected := Selected;
  UpdateNewSelected(TmpSelected);
end;


procedure TKMSpectator.UpdateNewSelected(var aNewSelected: TObject; aAllowSelectAllies: Boolean = False);
var
  OwnerIndex: TKMHandID;
begin
  if gGame.GameMode in [gmMultiSpectate, gmMapEd, gmReplaySingle, gmReplayMulti] then
    Exit;

  OwnerIndex := GetGameObjectOwnerIndex(aNewSelected);
  if OwnerIndex <> -1 then
  begin
    if OwnerIndex <> fHandIndex then  // check if we selected our unit/ally's or enemy's
    begin
      if (ALLOW_SELECT_ALLY_UNITS or
          ((gHands[OwnerIndex].IsHuman or not gGame.IsCampaign) //Do not allow to select allied AI in campaigns
            and aAllowSelectAllies)
        and (Hand.Alliances[OwnerIndex] = atAlly))
          or (ALLOW_SELECT_ENEMIES and (Hand.Alliances[OwnerIndex] = atEnemy)) then // Enemies can be selected for debug
        fIsSelectedMyObj := False
      else
        aNewSelected := nil;
    end else
      fIsSelectedMyObj := True;
  end;
end;


//Select anything player CAN select below cursor
procedure TKMSpectator.UpdateSelect;
var
  NewSelected: TObject;
  UID: Integer;
begin
  NewSelected := gHands.GetUnitByUID(gGameCursor.ObjectUID);

  //In-game player can select only own and ally Units
  UpdateNewSelected(NewSelected);

  //Don't allow the player to select dead units
  if ((NewSelected is TKMUnit) and TKMUnit(NewSelected).IsDeadOrDying)
    or (NewSelected is TKMUnitAnimal) then //...or animals
    NewSelected := nil;

  //If Id belongs to some Warrior, try to select his group instead
  if NewSelected is TKMUnitWarrior then
  begin
    NewSelected := gHands.GetGroupByMember(TKMUnitWarrior(NewSelected));
    UpdateNewSelected(NewSelected);
  end;

  //Update selected groups selected unit
  if NewSelected is TKMUnitGroup then
    TKMUnitGroup(NewSelected).SelectedUnit := TKMUnitGroup(NewSelected).MemberByUID(gGameCursor.ObjectUID);

  //If there's no unit try pick a house on the Cell below
  if NewSelected = nil then
  begin
    NewSelected := gHands.HousesHitTest(gGameCursor.Cell.X, gGameCursor.Cell.Y);

    //In-game player can select only own and ally Units
    UpdateNewSelected(NewSelected, True);

    //Don't allow the player to select destroyed houses
    if (NewSelected is TKMHouse) and TKMHouse(NewSelected).IsDestroyed then
      NewSelected := nil;
  end;

  //Don't clear the old selection unless we found something new
  if NewSelected <> nil then
    Selected := NewSelected;

  // In a replay we want in-game statistics (and other things) to be shown for the owner of the last select object
  if gGame.GameMode in [gmMultiSpectate, gmReplaySingle, gmReplayMulti] then
  begin
    UID := UID_NONE;
    if Selected is TKMHouse then
    begin
      HandID := TKMHouse(Selected).Owner;
      UID := TKMHouse(Selected).UID;
    end;
    if Selected is TKMUnit then
    begin
      HandID := TKMUnit(Selected).Owner;
      UID := TKMUnit(Selected).UID;
    end;
    if Selected is TKMUnitGroup then
    begin
      HandID := TKMUnitGroup(Selected).Owner;
      UID := TKMUnitGroup(Selected).UID;
    end;
    if (Selected <> nil) and (UID <> UID_NONE) then
      fLastSpecSelectedObjUID[fHandIndex] := UID;
  end;

end;


procedure TKMSpectator.SetFOWIndex(const Value: TKMHandID);
begin
  fFOWIndex := Value;
  UpdateFogOfWarIndex;
end;


procedure TKMSpectator.SetHighlight(Value: TObject);
begin
  //We don't increase PointersCount of object because of savegames identicality over MP
  //Objects report on their destruction and set it to nil
  fHighlight := Value;
  fHighlightEnd := TimeGet + 3000;
end;


procedure TKMSpectator.SetHandIndex(const Value: TKMHandID);
begin
  Assert(MULTIPLAYER_CHEATS or (gGame.GameMode <> gmMulti));
  fHandIndex := Value;

  if not (gGame.GameMode in [gmMultiSpectate, gmMapEd, gmReplaySingle, gmReplayMulti]) then
    Selected := nil;

  UpdateFogOfWarIndex;
end;


procedure TKMSpectator.SetSelected(Value: TObject);
begin
  fLastSelected := fSelected;

  //We don't increase PointersCount of object because of savegames identicality over MP
  //Objects report on their destruction and set it to nil
  fSelected := Value;
end;


procedure TKMSpectator.UpdateState;
begin
  //Hide the highlight
  if TimeGet > fHighlightEnd then
    fHighlight := nil;
  //Units should be deselected when they go inside a house
  if Selected is TKMUnit then
    if not TKMUnit(Selected).Visible then
      Selected := nil;
end;


end.
