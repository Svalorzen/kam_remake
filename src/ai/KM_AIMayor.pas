unit KM_AIMayor;
{$I KaM_Remake.inc}
interface
uses
  KM_AIMayorBalance, KM_AICityPlanner, KM_AISetup,
  KM_PathfindingRoad,
  KM_ResHouses, KM_HouseCollection,
  KM_CommonClasses, KM_Defaults, KM_Points,
  KM_NavMeshDefences;


type
  //Mayor is the one who manages the town
  TKMayor = class
  private
    fOwner: TKMHandID;
    fSetup: TKMHandAISetup;
    fBalance: TKMayorBalance;
    fCityPlanner: TKMCityPlanner;
    fPathFindingRoad: TPathFindingRoad;
    fPathFindingRoadShortcuts: TPathFindingRoadShortcuts;

    fRoadBelowStore: Boolean;
    fDefenceTowersPlanned: Boolean;
    fDefenceTowers: TKMPointTagList;

    WarfareRatios: TWarfareDemands;

    procedure SetArmyDemand(aFootmen, aPikemen, aHorsemen, aArchers: Single);

    function TryBuildHouse(aHouse: TKMHouseType): Boolean;
    function TryConnectToRoad(const aLoc: TKMPoint): Boolean;
    function GetMaxPlans: Byte;

    procedure CheckAutoRepair;
    procedure CheckUnitCount;
    procedure CheckWareFlow;
    procedure CheckHouseCount;
    procedure CheckHousePlans;
    procedure CheckRoadsCount;
    procedure CheckExhaustedMines;
    procedure CheckWeaponOrderCount;
    procedure CheckArmyDemand;
    procedure PlanDefenceTowers;
    procedure TryBuildDefenceTower;
  public
    constructor Create(aPlayer: TKMHandID; aSetup: TKMHandAISetup);
    destructor Destroy; override;

    property CityPlanner: TKMCityPlanner read fCityPlanner;

    procedure AfterMissionInit;
    procedure OwnerUpdate(aPlayer: TKMHandID);
    function BalanceText: UnicodeString;

    procedure UpdateState(aTick: Cardinal);
    procedure Save(SaveStream: TKMemoryStream);
    procedure Load(LoadStream: TKMemoryStream);
  end;


implementation
uses
  Classes, Math,
  KM_Game, KM_Hand, KM_HandsCollection,
  KM_AIFields, KM_Terrain,
  KM_Houses, KM_HouseSchool,
  KM_Units, KM_UnitsCollection, KM_UnitActionWalkTo, KM_UnitTaskGoEat, KM_UnitTaskDelivery,
  KM_Resource, KM_ResWares,
  KM_NavMesh, KM_CommonUtils;


const //Sample list made by AntonP
  WarriorHouses: array [0..44] of TKMHouseType = (
  htSchool, htInn, htQuary, htQuary, htQuary,
  htWoodcutters, htWoodcutters, htWoodcutters, htWoodcutters, htWoodcutters,
  htSawmill, htSawmill, htWoodcutters, htGoldMine, htCoalMine,
  htGoldMine, htCoalMine, htMetallurgists, htCoalMine, htCoalMine,
  htIronMine, htIronMine, htCoalMine, htIronMine, htWeaponSmithy,
  htWeaponSmithy, htWineyard, htWineyard, htWineyard, htStore,
  htBarracks, htFarm, htFarm, htFarm, htMill,
  htMill, htBakery, htBakery, htSchool, htIronSmithy,
  htIronSmithy, htFarm, htSwine, htWeaponSmithy, htArmorSmithy
  );

  //Vital (Store, School, Inn)
  //Mining_Core (Quary x3, Woodcutters x3, Sawmill)
  //Mining_Gold (CoalMine x2, GoldMine, Metallurgists)
  //Food_Basic (Farm, Mill, Bakery, Wineyard)

  //Food

  //Warfare_Leather (Woodcutters x2, Sawmill, Swine x4, Tannery x2, Armor x2, Weapon x3)
  //Warfare_Iron (Coal x4, Iron x2, IronSmithy x2, Armor, Weapon x2)

  //Hiring_Army (Barracks)
  //Hiring_Army2 (School, CoalMine x2, GoldMine)

  WOOD_BLOCK_RAD = 5.8;


{ TKMayor }
constructor TKMayor.Create(aPlayer: TKMHandID; aSetup: TKMHandAISetup);
begin
  inherited Create;

  fOwner := aPlayer;
  fSetup := aSetup;

  fBalance := TKMayorBalance.Create(fOwner);
  fCityPlanner := TKMCityPlanner.Create(fOwner);
  fPathFindingRoad := TPathFindingRoad.Create(fOwner);
  fPathFindingRoadShortcuts := TPathFindingRoadShortcuts.Create(fOwner);
  fDefenceTowers := TKMPointTagList.Create;
end;


destructor TKMayor.Destroy;
begin
  fBalance.Free;
  fCityPlanner.Free;
  fPathFindingRoad.Free;
  fPathFindingRoadShortcuts.Free;
  fDefenceTowers.Free;

  inherited;
end;


procedure TKMayor.AfterMissionInit;
begin
  fCityPlanner.AfterMissionInit;
  CheckArmyDemand;
  CheckAutoRepair;
  fBalance.StoneNeed := GetMaxPlans * 2.5;
end;


// Check existing unit count vs house count and train missing citizens
procedure TKMayor.CheckUnitCount;
var
  P: TKMHand;
  UnitReq: array [CITIZEN_MIN..CITIZEN_MAX] of Integer;

  // Check that AI has enough Gold to train serfs/workers
  function HasEnoughGoldForAux: Boolean;
  begin
    //Producing gold or (Gold > 10)
    Result := (P.Stats.GetWaresProduced(wtGold) > 1)
              or (P.Stats.GetWareBalance(wtGold) > 20);
  end;

  function TryToTrain(aSchool: TKMHouseSchool; aUnitType: TKMUnitType; aRequiredCount: Integer): Boolean;
  begin
    // We summ up requirements for e.g. Recruits required at Towers and Barracks
    if P.Stats.GetUnitQty(aUnitType) < (aRequiredCount + UnitReq[aUnitType]) then
    begin
      Dec(UnitReq[aUnitType]); //So other schools don't order same unit
      aSchool.AddUnitToQueue(aUnitType, 1);
      Result := True;
    end
    else
      Result := False;
  end;

  function RecruitsNeeded: Integer;
  var AxesLeft: Integer;
  begin
    if P.Stats.GetHouseQty(htBarracks) = 0 then
      Result := 0
    else
      if gGame.IsPeaceTime then
      begin
        //Keep enough recruits to equip using all weapons once PT ends
        //Iron soldiers
        Result := Min(P.Stats.GetWareBalance(wtMetalArmor),
                      P.Stats.GetWareBalance(wtArbalet) + P.Stats.GetWareBalance(wtHallebard)
                      + Min(P.Stats.GetWareBalance(wtSword), P.Stats.GetWareBalance(wtMetalShield)));
        //Leather soldiers we can make
        Inc(Result, Min(P.Stats.GetWareBalance(wtArmor),
                        P.Stats.GetWareBalance(wtBow) + P.Stats.GetWareBalance(wtPike)
                        + Min(P.Stats.GetWareBalance(wtAxe), P.Stats.GetWareBalance(wtShield))));
        //Militia with leftover axes
        AxesLeft := P.Stats.GetWareBalance(wtAxe) - Min(P.Stats.GetWareBalance(wtArmor), P.Stats.GetWareBalance(wtShield));
        if AxesLeft > 0 then
          Inc(Result, AxesLeft);
      end
      else
        Result := fSetup.RecruitCount * P.Stats.GetHouseQty(htBarracks);
  end;

var
  I,K: Integer;
  H: TKMHouseType;
  UT: TKMUnitType;
  Schools: array of TKMHouseSchool;
  HS: TKMHouseSchool;
  serfCount: Integer;
begin
  //todo: When training new units make sure we have enough gold left to train
  //stonemason-woodcutter-carpenter-2miners-metallurgist. In other words -
  //dont waste gold if it's not producing yet

  P := gHands[fOwner];

  //Citizens
  //Count overall unit requirement (excluding Barracks and ownerless houses)
  FillChar(UnitReq, SizeOf(UnitReq), #0); //Clear up
  for H := HOUSE_MIN to HOUSE_MAX do
    if (gRes.Houses[H].OwnerType <> utNone) and (H <> htBarracks) then
      Inc(UnitReq[gRes.Houses[H].OwnerType], P.Stats.GetHouseQty(H));

  //Schools
  //Count overall schools count and exclude already training units from UnitReq
  SetLength(Schools, P.Stats.GetHouseQty(htSchool));
  K := 1;
  HS := TKMHouseSchool(P.FindHouse(htSchool, K));
  while HS <> nil do
  begin
    Schools[K-1] := HS;
    for I := 0 to HS.QueueLength - 1 do //Decrease requirement for each unit in training
      if HS.Queue[I] <> utNone then
        Dec(UnitReq[HS.Queue[I]]); //Can be negative and compensated by e.g. ReqRecruits
    Inc(K);
    HS := TKMHouseSchool(P.FindHouse(htSchool, K));
  end;

  //Order the training. Keep up to 2 units in the queue so the school doesn't have to wait
  for K := 0 to High(Schools) do
  begin
    HS := Schools[K];
    if (HS <> nil) and (HS.QueueCount < 2) then
    begin
      //Order citizen training
      for UT := Low(UnitReq) to High(UnitReq) do
        if (UnitReq[UT] > 0) //Skip units that houses dont need (Serfs/Workers)
        and (UnitReq[UT] > P.Stats.GetUnitQty(UT)) then
        begin
          Dec(UnitReq[UT]); //So other schools don't order same unit
          HS.AddUnitToQueue(UT, 1);
          Break; //Don't need more UnitTypes yet
        end;

      // If we are here then a citizen to train wasn't found, so try other unit types (citizens get top priority)
      // Serf factor is like this: Serfs = (10/FACTOR)*Total_Building_Count) (from: http://atfreeforum.com/knights/viewtopic.php?t=465)

      // While still haven't found a match...
      while (HS.QueueCount < 2) do
      begin
        // If we are low on Gold don't hire more ppl (next school will fail this too, so we can exit)
        if not HasEnoughGoldForAux then Exit;

        serfCount := Round(fSetup.SerfsPerHouse * (P.Stats.GetHouseQty(htAny) + P.Stats.GetUnitQty(utWorker)/2));

        if not TryToTrain(HS, utSerf, serfCount) then
          if not TryToTrain(HS, utWorker, fSetup.WorkerCount) then
            if not gGame.CheckTime(fSetup.RecruitDelay) then //Recruits can only be trained after this time
              Break
            else
              if not TryToTrain(HS, utRecruit, RecruitsNeeded) then
                Break; //There's no unit demand at all
      end;
    end;
  end;
end;


procedure TKMayor.CheckArmyDemand;
var Footmen, Pikemen, Horsemen, Archers: Integer;
begin
  gHands[fOwner].AI.General.DefencePositions.GetArmyDemand(Footmen, Pikemen, Horsemen, Archers);
  SetArmyDemand(Footmen, Pikemen, Horsemen, Archers);
end;


//Check that we have weapons ordered for production
procedure TKMayor.CheckWeaponOrderCount;
const
  //Order weapons in portions to avoid overproduction of one ware over another
  //(e.g. Shields in armory until Leather is available)
  PORTIONS = 8;
var
  I,K: Integer;
  H: TKMHouse;
  ResOrder: Integer;
begin
  for I := 0 to gHands[fOwner].Houses.Count - 1 do
  begin
    H := gHands[fOwner].Houses[I];

    ResOrder := H.ResOrder[1] + H.ResOrder[2] + H.ResOrder[3] + H.ResOrder[4];

    if not H.IsDestroyed and (ResOrder = 0) then
    case H.HouseType of
      htArmorSmithy:     for K := 1 to 4 do
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtMetalShield then
                              H.ResOrder[K] := Round(WarfareRatios[wtMetalShield] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtMetalArmor then
                              H.ResOrder[K] := Round(WarfareRatios[wtMetalArmor] * PORTIONS);
      htArmorWorkshop:   for K := 1 to 4 do
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtShield then
                              H.ResOrder[K] := Round(WarfareRatios[wtShield] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtArmor then
                              H.ResOrder[K] := Round(WarfareRatios[wtArmor] * PORTIONS);
      htWeaponSmithy:    for K := 1 to 4 do
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtSword then
                              H.ResOrder[K] := Round(WarfareRatios[wtSword] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtHallebard then
                              H.ResOrder[K] := Round(WarfareRatios[wtHallebard] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtArbalet then
                              H.ResOrder[K] := Round(WarfareRatios[wtArbalet] * PORTIONS);
      htWeaponWorkshop:  for K := 1 to 4 do
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtAxe then
                              H.ResOrder[K] := Round(WarfareRatios[wtAxe] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtPike then
                              H.ResOrder[K] := Round(WarfareRatios[wtPike] * PORTIONS)
                            else
                            if gRes.Houses[H.HouseType].ResOutput[K] = wtBow then
                              H.ResOrder[K] := Round(WarfareRatios[wtBow] * PORTIONS);
    end;
  end;
end;


procedure TKMayor.PlanDefenceTowers;
const
  DISTANCE_BETWEEN_TOWERS = 7;
var
  P: TKMHand;
  PL1, PL2: TKMHandID;
  pom: boolean;
  //Outline1, Outline2: TKMWeightSegments;
  I, K, DefCount: Integer;
  // DefCount: Integer;
  Point1, Point2: TKMPoint;
  //Loc: TKMPoint;
  Ratio: Single;
  //SegLength: Single;
  DefLines: TKMDefenceLines;
begin
  if fDefenceTowersPlanned then
    Exit;
  fDefenceTowersPlanned := True;
  P := gHands[fOwner];
  if not P.Locks.HouseCanBuild(htWatchTower) then
    Exit;
  pom := not gAIFields.NavMesh.Defences.FindDefenceLines(fOwner, DefLines) OR (DefLines.Count < 1);
  if pom then
    Exit;

  for I := 0 to DefLines.Count - 1 do
    with DefLines.Lines[I] do
    begin
      Point1 := gAIFields.NavMesh.Nodes[ DefLines.Lines[I].Nodes[0] ];
      Point2 := gAIFields.NavMesh.Nodes[ DefLines.Lines[I].Nodes[1] ];
      PL1 := gAIFields.Influences.GetBestAllianceOwner(fOwner, Point1, atAlly);
      PL2 := gAIFields.Influences.GetBestAllianceOwner(fOwner, Point2, atAlly);
      if (PL1 <> fOwner) AND (PL2 <> fOwner) AND (PL1 <> PLAYER_NONE) AND (PL2 <> PLAYER_NONE) then
        continue;
      DefCount := Ceil( KMLength(Point1, Point2) / DISTANCE_BETWEEN_TOWERS );
      for K := 0 to DefCount - 1 do
      begin
        Ratio := (K + 1) / (DefCount + 1);
        fDefenceTowers.Add( KMPointRound(KMLerp(Point1, Point2, Ratio)), gAIFields.Influences.GetBestAllianceOwnership(fOwner, Polygon, atEnemy));
      end;
    end;

  //Get defence Outline with weights representing how important each segment is
  //gAIFields.NavMesh.GetDefenceOutline(fOwner, Outline1, Outline2);

  //Make list of defence positions
  //for I := 0 to High(Outline2) do
  //begin
  //  //Longer segments will get several towers
  //  SegLength := KMLength(Outline2[I].A, Outline2[I].B);
  //  DefCount := Max(Trunc(SegLength / DISTANCE_BETWEEN_TOWERS), 1);
  //  for K := 0 to DefCount - 1 do
  //  begin
  //    Ratio := (K + 1) / (DefCount + 1);
  //    Loc := KMPointRound(KMLerp(Outline2[I].A, Outline2[I].B, Ratio));
  //    fDefenceTowers.Add(Loc, Trunc(1000*Outline2[I].Weight));
  //  end;
  //end;
  fDefenceTowers.SortByTag;
  fDefenceTowers.Inverse; //So highest weight is first
end;


procedure TKMayor.TryBuildDefenceTower;
const
  SEARCH_RAD = 6;
  MAX_ROAD_DISTANCE = 50;
var
  P: TKMHand;
  IY, IX: Integer;
  Loc: TKMPoint;
  DistSqr, BestDistSqr: Integer;
  BestLoc: TKMPoint;

  NodeList: TKMPointList;
  H: TKMHouse;
  LocTo: TKMPoint;
  RoadConnectID: Byte;
  RoadExists: Boolean;
begin
  P := gHands[fOwner];
  //Take the first tower from the list
  Loc := fDefenceTowers[0];
  fDefenceTowers.Delete(0);
  //Look for a place for the tower
  BestDistSqr := High(BestDistSqr);
  BestLoc := KMPOINT_ZERO;
  for IY := Max(1, Loc.Y-SEARCH_RAD) to Min(gTerrain.MapY, Loc.Y+SEARCH_RAD) do
    for IX := Max(1, Loc.X-SEARCH_RAD) to Min(gTerrain.MapX, Loc.X+SEARCH_RAD) do
    begin
      DistSqr := KMLengthSqr(Loc, KMPoint(IX, IY));
      if (DistSqr < BestDistSqr) and P.CanAddHousePlanAI(IX, IY, htWatchTower, False) then
      begin
        BestLoc := KMPoint(IX, IY);
        BestDistSqr := DistSqr;
      end;
    end;
  if (BestLoc.X > 0) then
  begin
    //See if the road required is too long (tower might be across unwalkable terrain)
    H := P.Houses.FindHouse(htAny, BestLoc.X, BestLoc.Y, 1, False);
    if H = nil then Exit; //We are screwed, no houses left
    LocTo := H.PointBelowEntrance;

    //Find nearest complete house to get the road connect ID
    H := P.Houses.FindHouse(htAny, BestLoc.X, BestLoc.Y, 1, True);
    if H = nil then Exit; //We are screwed, no houses left
    RoadConnectID := gTerrain.GetRoadConnectID(H.PointBelowEntrance);

    NodeList := TKMPointList.Create;
    RoadExists := fPathFindingRoad.Route_ReturnToWalkable(BestLoc, LocTo, RoadConnectID, NodeList);
    //If length of road is short enough, build the tower
    if RoadExists and (NodeList.Count <= MAX_ROAD_DISTANCE) then
    begin
      gHands[fOwner].AddHousePlan(htWatchTower, BestLoc);
      TryConnectToRoad(KMPointBelow(BestLoc));
    end;
    NodeList.Free;
  end;
end;


function TKMayor.GetMaxPlans: Byte;
begin
  Result := Ceil(fSetup.WorkerCount / 4);
end;


//We want to connect to nearest road piece (not necessarily built yet)
function TKMayor.TryConnectToRoad(const aLoc: TKMPoint): Boolean;
var
  I: Integer;
  P: TKMHand;
  H: TKMHouse;
  LocTo: TKMPoint;
  RoadConnectID: Byte;
  NodeList: TKMPointList;
  RoadExists: Boolean;
begin
  Result := False;
  P := gHands[fOwner];

  //Find nearest wip or ready house
  H := P.Houses.FindHouse(htAny, aLoc.X, aLoc.Y, 1, False);
  if H = nil then Exit; //We are screwed, no houses left
  LocTo := H.PointBelowEntrance;

  //Find nearest complete house to get the road connect ID
  H := P.Houses.FindHouse(htAny, aLoc.X, aLoc.Y, 1, True);
  if H = nil then Exit; //We are screwed, no houses left
  RoadConnectID := gTerrain.GetRoadConnectID(H.PointBelowEntrance);

  NodeList := TKMPointList.Create;
  try
    RoadExists := fPathFindingRoad.Route_ReturnToWalkable(aLoc, LocTo, RoadConnectID, NodeList);

    if not RoadExists then
      Exit;

    for I := 0 to NodeList.Count - 1 do
      //We must check if we can add the plan ontop of plans placed earlier in this turn
      if P.CanAddFieldPlan(NodeList[I], ftRoad) then
        P.BuildList.FieldworksList.AddField(NodeList[I], ftRoad);
    Result := True;
  finally
    NodeList.Free;
  end;
end;


//Try to place a building plan for requested house
//Report back if failed to do so (that will allow requester to choose different action)
function TKMayor.TryBuildHouse(aHouse: TKMHouseType): Boolean;
var
  I, K: Integer;
  Loc: TKMPoint;
  P: TKMHand;
  NodeTagList: TKMPointTagList;
  Weight: Cardinal;
begin
  Result := False;
  P := gHands[fOwner];

  //Skip disabled houses
  if not P.Locks.HouseCanBuild(aHouse) then Exit;

  //Number of simultaneous WIP houses is limited
  if (P.Stats.GetHouseWip(htAny) > GetMaxPlans) then Exit;

  //Maybe we get more lucky next tick
  //todo: That only works if FindPlaceForHouse is quick, right now it takes ~11ms for iron/gold/coal mines (to decide that they can't be placed).
  //      If there's no place for the house we try again and again and again every update, so it's very inefficient
  //      I think the best solution would be to make FindPlaceForHouse only take a long time if we succeed in finding a place for the house, if we
  //      fail it should be quick. Doing a flood fill with radius=40 should really be avoided anyway, 11ms is a long time for placing 1 house.
  //      We could also make it not try to place houses again each update if it failed the first time, if we can't make FindPlaceForHouse quick when it fails.
  if not fCityPlanner.FindPlaceForHouse(aHouse, Loc) then Exit;

  //Place house before road, so that road is made around it
  P.AddHousePlan(aHouse, Loc);

  //Try to connect newly planned house to road network
  //if it is not possible - scrap the plan
  if not TryConnectToRoad(KMPointBelow(Loc)) then
  begin
    P.RemHousePlan(Loc);
    Exit;
  end;

  //Build fields for Farm
  if aHouse = htFarm then
  begin
    NodeTagList := TKMPointTagList.Create;
    try
      for I := Min(Loc.Y - 2, gTerrain.MapY - 1) to Min(Loc.Y + 2 + AI_FIELD_HEIGHT - 1, gTerrain.MapY - 1) do
      for K := Max(Loc.X - AI_FIELD_WIDTH, 1) to Min(Loc.X + AI_FIELD_WIDTH, gTerrain.MapX - 1) do
        if P.CanAddFieldPlan(KMPoint(K,I), ftCorn) then
        begin
          //Base weight is distance from door (weight X higher so nice rectangle is formed)
          Weight := Abs(K - Loc.X)*3 + Abs(I - 2 - Loc.Y);
          //Prefer fields below the farm
          if (I < Loc.Y + 2) then
            Inc(Weight, 100);
          //Avoid building on row with roads (so we can expand from this house)
          if I = Loc.Y + 1 then
            Inc(Weight, 1000);
          NodeTagList.Add(KMPoint(K, I), Weight);
        end;

      NodeTagList.SortByTag;
      for I := 0 to Min(NodeTagList.Count, 16) - 1 do
        P.BuildList.FieldworksList.AddField(NodeTagList[I], ftCorn);
    finally
      NodeTagList.Free;
    end;
  end;

  //Build fields for Wineyard
  if aHouse = htWineyard then
  begin
    NodeTagList := TKMPointTagList.Create;
    try
      for I := Min(Loc.Y - 2, gTerrain.MapY - 1) to Min(Loc.Y + 2 + AI_FIELD_HEIGHT - 1, gTerrain.MapY - 1) do
      for K := Max(Loc.X - AI_FIELD_WIDTH, 1) to Min(Loc.X + AI_FIELD_WIDTH, gTerrain.MapX - 1) do
        if P.CanAddFieldPlan(KMPoint(K,I), ftWine) then
        begin
          //Base weight is distance from door (weight X higher so nice rectangle is formed)
          Weight := Abs(K - Loc.X)*3 + Abs(I - 2 - Loc.Y);
          //Prefer fields below the farm
          if (I < Loc.Y + 2) then
            Inc(Weight, 100);
          //Avoid building on row with roads (so we can expand from this house)
          if I = Loc.Y + 1 then
            Inc(Weight, 1000);
          NodeTagList.Add(KMPoint(K, I), Weight);
        end;

      NodeTagList.SortByTag;
      for I := 0 to Min(NodeTagList.Count, 10) - 1 do
        P.BuildList.FieldworksList.AddField(NodeTagList[I], ftWine);
    finally
      NodeTagList.Free;
    end;
  end;

  //Block any buildings nearby
  if aHouse = htWoodcutters then
    gAIFields.Influences.AddAvoidBuilding(Loc.X-1, Loc.Y, WOOD_BLOCK_RAD); //X-1 because entrance is on right

  //Build more roads around 2nd Store
  if aHouse = htStore then
    for I := Max(Loc.Y - 3, 1) to Min(Loc.Y + 2, gTerrain.MapY - 1) do
    for K := Max(Loc.X - 2, 1) to Min(Loc.X + 2, gTerrain.MapY - 1) do
    if P.CanAddFieldPlan(KMPoint(K, I), ftRoad) then
      P.BuildList.FieldworksList.AddField(KMPoint(K, I), ftRoad);

  Result := True;
end;


//todo: Check if planned houses are being connected with roads
//(worker could die while digging a road piece or elevation changed to impassable)
procedure TKMayor.CheckHousePlans;
begin
  //
end;


//Manage ware distribution
procedure TKMayor.CheckWareFlow;
var
  I: Integer;
  S: TKMHouseStore;
  Houses: TKMHousesCollection;
begin
  Houses := gHands[fOwner].Houses;

  //Iterate through all Stores and block certain wares to reduce serf usage
  for I := 0 to Houses.Count - 1 do
    if (Houses[I].HouseType = htStore)
    and Houses[I].IsComplete
    and not Houses[I].IsDestroyed then
    begin
      S := TKMHouseStore(Houses[I]);

      //We like to always keep a supply of these
      S.NotAcceptFlag[wtWood] := S.CheckResIn(wtWood) > 50;
      S.NotAcceptFlag[wtStone] := S.CheckResIn(wtStone) > 50;
      S.NotAcceptFlag[wtGold] := S.CheckResIn(wtGold) > 50;

      //Storing these causes lots of congestion with very little gain
      //Auto build AI aims for perfectly balanced village where these goods don't need storing
      //Keep them only until we have the house which consumes them.
      S.NotAcceptFlag[wtTrunk] := gHands[fOwner].Stats.GetHouseQty(htSawmill) > 0;
      S.NotAcceptFlag[wtGoldOre] := gHands[fOwner].Stats.GetHouseQty(htMetallurgists) > 0;
      S.NotAcceptFlag[wtIronOre] := gHands[fOwner].Stats.GetHouseQty(htIronSmithy) > 0;
      S.NotAcceptFlag[wtCoal] := gHands[fOwner].Stats.GetHouseQty(htMetallurgists) +
                                  gHands[fOwner].Stats.GetHouseQty(htIronSmithy) > 0;
      S.NotAcceptFlag[wtSteel] := gHands[fOwner].Stats.GetHouseQty(htWeaponSmithy) +
                                   gHands[fOwner].Stats.GetHouseQty(htArmorSmithy) > 0;
      S.NotAcceptFlag[wtCorn] := gHands[fOwner].Stats.GetHouseQty(htMill) +
                                  gHands[fOwner].Stats.GetHouseQty(htSwine) +
                                  gHands[fOwner].Stats.GetHouseQty(htStables) > 0;
      S.NotAcceptFlag[wtLeather] := gHands[fOwner].Stats.GetHouseQty(htArmorWorkshop) > 0;
      S.NotAcceptFlag[wtFlour] := gHands[fOwner].Stats.GetHouseQty(htBakery) > 0;
      //Pigs and skin cannot be blocked since if swinefarm is full of one it stops working (blocks other)
      //S.NotAcceptFlag[wtSkin] := gHands[fOwner].Stats.GetHouseQty(htTannery) > 0;
      //S.NotAcceptFlag[wtPig] := gHands[fOwner].Stats.GetHouseQty(htButchers) > 0;
    end;
end;


//Demolish any exhausted mines, they will be rebuilt if needed
procedure TKMayor.CheckExhaustedMines;
var
  I: Integer;
  Houses: TKMHousesCollection;
  Loc: TKMPoint;
begin
  Houses := gHands[fOwner].Houses;

  //Wait until resource is depleted and output is empty
  for I := 0 to Houses.Count - 1 do
  if not Houses[I].IsDestroyed
  and Houses[I].ResourceDepletedMsgIssued
  and (Houses[I].CheckResOut(wtAll) = 0) then
  begin
    //Set it so we can build over coal that was removed
    if Houses[I].HouseType = htCoalMine then
    begin
      Loc := Houses[I].Entrance;
      gAIFields.Influences.RemAvoidBuilding(KMRect(Loc.X-2, Loc.Y-2, Loc.X+3, Loc.Y+1));
    end;
    Houses[I].DemolishHouse(fOwner);
  end;
end;


procedure TKMayor.CheckHouseCount;
var
  P: TKMHand;

  function MaxPlansForTowers: Integer;
  begin
    Result := GetMaxPlans;
    //Once there are 2 towers wip then allow balance to build something
    if (fBalance.Peek <> htNone) and (P.Stats.GetHouseWip(htWatchTower) >= 2) then
      Result := Result - 1;
    Result := Max(1, Result);
  end;

const
  MAX_TRIES = 10; //We could get into infinite loop on some scripted maps, f.e. Furrioir Warriors

var
  K: Integer;
  H: TKMHouseType;
begin
  P := gHands[fOwner];

  //Try to express needs in terms of Balance = Production - Demand
  fBalance.Refresh;

  //Peek - see if we can build this house
  //Take - take this house into building
  //Reject - we can't build this house (that could affect other houses in queue)

  //Build towers if village is done, or peacetime is nearly over
  if P.Locks.HouseCanBuild(htWatchTower) then
    if ((fBalance.Peek = htNone) and (P.Stats.GetHouseWip(htAny) = 0)) //Finished building
    or ((gGame.GameOptions.Peacetime <> 0) and gGame.CheckTime(600 * Max(0, gGame.GameOptions.Peacetime - 15))) then
      PlanDefenceTowers;

  if fDefenceTowersPlanned then
    while (fDefenceTowers.Count > 0) and (P.Stats.GetHouseWip(htAny) < MaxPlansForTowers) do
      TryBuildDefenceTower;

  K := 0;
  while (P.Stats.GetHouseWip(htAny) < GetMaxPlans) and (K < Max(GetMaxPlans, MAX_TRIES)) do
  begin
    Inc(K);
    H := fBalance.Peek;

    //There are no more suggestions
    if H = htNone then
      Break;

    //See if we can build that
    if TryBuildHouse(H) then
    begin
      fBalance.Take;
      fBalance.Refresh; //Balance will be changed by the construction of this house
    end
    else
      fBalance.Reject;
  end;

  //Check if we need to demolish depleted mining houses
  CheckExhaustedMines;

  //Verify all plans are being connected with roads
  CheckHousePlans;
end;


procedure TKMayor.CheckRoadsCount;
const
  SHORTCUT_CHECKS_PER_UPDATE = 10;
var
  P: TKMHand;
  Store: TKMHouse;
  StoreLoc: TKMPoint;
  I, K: Integer;
  FromLoc, ToLoc: TKMPoint;
  NodeList: TKMPointList;
  RoadExists: Boolean;
begin
  P := gHands[fOwner];

  //This is one time task to build roads around Store
  //When town becomes larger add road around Store to make traffic smoother
  if not fRoadBelowStore and (P.Stats.GetHouseQty(htAny) > 14) then
  begin
    fRoadBelowStore := True;

    Store := P.Houses.FindHouse(htStore, 0, 0, 1);
    if Store = nil then Exit;
    StoreLoc := Store.Entrance;

    for I := Max(StoreLoc.Y - 3, 1) to Min(StoreLoc.Y + 2, gTerrain.MapY - 1) do
    for K := StoreLoc.X - 2 to StoreLoc.X + 2 do
    if P.CanAddFieldPlan(KMPoint(K, I), ftRoad) then
      P.BuildList.FieldworksList.AddField(KMPoint(K, I), ftRoad);
  end;

  //Check if we need to connect separate branches of road network
  //Town has no plan and usually roadnetwork looks like a tree,
  //where we can improve it by connecting near branches with shortcuts.
  NodeList := TKMPointList.Create;
  try
    //See where our citizens are walking and build shortcuts where possible
    for I := 0 to gHands[fOwner].Units.Count - 1 do
    begin
      //Checking for shortcuts is slow, so skip some units randomly each update
      if KaMRandom(gHands[fOwner].Stats.GetUnitQty(utSerf), 'TKMayor.CheckRoadsCount') >= SHORTCUT_CHECKS_PER_UPDATE then
        Continue;
      if not gHands[fOwner].Units[I].IsDeadOrDying
      and (gHands[fOwner].Units[I].Action is TKMUnitActionWalkTo) then
        if ((gHands[fOwner].Units[I] is TKMUnitSerf) and (gHands[fOwner].Units[I].Task is TKMTaskDeliver)
                                                     and (TKMTaskDeliver(gHands[fOwner].Units[I].Task).DeliverKind <> dkToUnit))
        or ((gHands[fOwner].Units[I] is TKMUnitCitizen) and (gHands[fOwner].Units[I].Task is TKMTaskGoEat)) then
        begin
          FromLoc := TKMUnitActionWalkTo(gHands[fOwner].Units[I].Action).WalkFrom;
          ToLoc := TKMUnitActionWalkTo(gHands[fOwner].Units[I].Action).WalkTo;
          //Unit's route must be using road network, not f.e. delivering to soldiers
          if gTerrain.Route_CanBeMade(FromLoc, ToLoc, tpWalkRoad, 0) then
          begin
            //Check for shortcuts we could build
            NodeList.Clear;
            RoadExists := fPathFindingRoadShortcuts.Route_Make(FromLoc, ToLoc, NodeList);

            if not RoadExists then
              Break;

            for K := 0 to NodeList.Count - 1 do
              //We must check if we can add the plan ontop of plans placed earlier in this turn
              if P.CanAddFieldPlan(NodeList[K], ftRoad) then
                P.BuildList.FieldworksList.AddField(NodeList[K], ftRoad);
          end;
        end;
    end;
  finally
    NodeList.Free;
  end;
end;


procedure TKMayor.OwnerUpdate(aPlayer: TKMHandID);
begin
  fOwner := aPlayer;
  fBalance.OwnerUpdate(aPlayer);
  fCityPlanner.OwnerUpdate(aPlayer);
  fPathFindingRoad.OwnerUpdate(aPlayer);
  fPathFindingRoadShortcuts.OwnerUpdate(aPlayer);
end;


//Tell Mayor what proportions of army is needed
//Input values are normalized
procedure TKMayor.SetArmyDemand(aFootmen, aPikemen, aHorsemen, aArchers: Single);

  function IsIronProduced: Boolean;
  begin
    Result := (  gHands[fOwner].Stats.GetHouseQty(htIronMine)
               + gHands[fOwner].Stats.GetHouseWip(htIronMine)
               + gHands[fOwner].Stats.GetHousePlans(htIronMine)) > 0;
  end;

  function GroupBlocked(aGT: TKMGroupType; aIron: Boolean): Boolean;
  begin
    if aIron then
      case aGT of
        gtMelee:     Result := gHands[fOwner].Locks.GetUnitBlocked(utSwordsman);
        gtAntiHorse: Result := gHands[fOwner].Locks.GetUnitBlocked(utHallebardman);
        gtRanged:    Result := gHands[fOwner].Locks.GetUnitBlocked(utArbaletman);
        gtMounted:   Result := gHands[fOwner].Locks.GetUnitBlocked(utCavalry);
        else          Result := True;
      end
    else
      case aGT of
        gtMelee:     Result := gHands[fOwner].Locks.GetUnitBlocked(utMilitia) and
                                gHands[fOwner].Locks.GetUnitBlocked(utAxeFighter);
        gtAntiHorse: Result := gHands[fOwner].Locks.GetUnitBlocked(utPikeman);
        gtRanged:    Result := gHands[fOwner].Locks.GetUnitBlocked(utBowman);
        gtMounted:   Result := gHands[fOwner].Locks.GetUnitBlocked(utHorseScout);
        else          Result := True;
      end;
  end;

  function GetUnitRatio(aUT: TKMUnitType): Byte;
  begin
    if gHands[fOwner].Locks.GetUnitBlocked(aUT) then
      Result := 0 //This warrior is blocked
    else
      if (fSetup.ArmyType = atIronAndLeather)
      and GroupBlocked(UnitGroups[aUT], not (aUT in WARRIORS_IRON)) then
        Result := 2 //In mixed army type, if our compliment is blocked we need to make double
      else
        Result := 1;
  end;

var
  Summ: Single;
  Footmen, Pikemen, Horsemen, Archers: Single;
  IronPerMin, LeatherPerMin: Single;
  WT: TKMWareType;
  WarfarePerMinute: TWarfareDemands;
begin
  Summ := aFootmen + aPikemen + aHorsemen + aArchers;
  if Summ = 0 then
  begin
    Footmen := 0;
    Pikemen := 0;
    Horsemen := 0;
    Archers := 0;
  end
  else
  begin
    Footmen := aFootmen / Summ;
    Pikemen := aPikemen / Summ;
    Horsemen := aHorsemen / Summ;
    Archers := aArchers / Summ;
  end;

  //Store ratios localy in Mayor to place weapon orders
  //Leather
  WarfareRatios[wtArmor] :=      Footmen  * GetUnitRatio(utAxeFighter)
                                 + Horsemen * GetUnitRatio(utHorseScout)
                                 + Pikemen  * GetUnitRatio(utPikeman)
                                 + Archers  * GetUnitRatio(utBowman);
  WarfareRatios[wtShield] :=     Footmen  * GetUnitRatio(utAxeFighter)
                                 + Horsemen * GetUnitRatio(utHorseScout);
  WarfareRatios[wtAxe] :=        Footmen  * Max(GetUnitRatio(utAxeFighter), GetUnitRatio(utMilitia))
                                 + Horsemen * GetUnitRatio(utHorseScout);
  WarfareRatios[wtPike] :=       Pikemen  * GetUnitRatio(utPikeman);
  WarfareRatios[wtBow] :=        Archers  * GetUnitRatio(utBowman);
  //Iron
  WarfareRatios[wtMetalArmor] := Footmen  * GetUnitRatio(utSwordsman)
                                 + Horsemen * GetUnitRatio(utCavalry)
                                 + Pikemen  * GetUnitRatio(utHallebardman)
                                 + Archers  * GetUnitRatio(utArbaletman);
  WarfareRatios[wtMetalShield] :=Footmen  * GetUnitRatio(utSwordsman)
                                 + Horsemen * GetUnitRatio(utCavalry);
  WarfareRatios[wtSword] :=      Footmen  * GetUnitRatio(utSwordsman)
                                 + Horsemen * GetUnitRatio(utCavalry);
  WarfareRatios[wtHallebard] :=  Pikemen  * GetUnitRatio(utHallebardman);
  WarfareRatios[wtArbalet] :=    Archers  * GetUnitRatio(utArbaletman);

  WarfareRatios[wtHorse] := Horsemen * (GetUnitRatio(utCavalry) + GetUnitRatio(utHorseScout));

  //How many warriors we would need to equip per-minute
  IronPerMin := fSetup.WarriorsPerMinute(atIron);
  LeatherPerMin := fSetup.WarriorsPerMinute(atLeather);

  //If the AI is meant to make both but runs out, we must make it up with leather
  if (fSetup.ArmyType = atIronAndLeather) and not IsIronProduced then
    LeatherPerMin := LeatherPerMin + IronPerMin; //Once iron runs out start making leather to replace it

  //Make only iron first then if it runs out make leather
  if (fSetup.ArmyType = atIronThenLeather) and IsIronProduced then
    LeatherPerMin := 0; //Don't make leather until the iron runs out

  for WT := WEAPON_MIN to WEAPON_MAX do
    if WT in WARFARE_IRON then
      WarfarePerMinute[WT] := WarfareRatios[WT] * IronPerMin
    else
      WarfarePerMinute[WT] := WarfareRatios[WT] * LeatherPerMin;

  //Horses require separate calculation
  WarfarePerMinute[wtHorse] := Horsemen * (  GetUnitRatio(utCavalry) * IronPerMin
                                            + GetUnitRatio(utHorseScout) * LeatherPerMin);

  //Update warfare needs accordingly
  fBalance.SetArmyDemand(WarfarePerMinute);
end;


procedure TKMayor.CheckAutoRepair;
var I: Integer;
begin
  with gHands[fOwner] do
    if HandType = hndComputer then
      for I := 0 to Houses.Count - 1 do
        Houses[I].BuildingRepair := fSetup.AutoRepair;
end;


function TKMayor.BalanceText: UnicodeString;
begin
  Result := fBalance.BalanceText;
end;


procedure TKMayor.UpdateState(aTick: Cardinal);
begin
  //Checking mod result against MAX_HANDS causes first update to happen ASAP
  if (aTick + Byte(fOwner)) mod (MAX_HANDS * 10) <> MAX_HANDS then Exit;

  CheckAutoRepair;

  //Train new units (citizens, serfs, workers and recruits) if needed
  CheckUnitCount;

  CheckArmyDemand;
  CheckWeaponOrderCount;

  if fSetup.AutoBuild then
  begin
    CheckHouseCount;

    //Manage wares ratios and block stone to Store
    CheckWareFlow;

    //Build more roads if necessary
    CheckRoadsCount;
  end;
end;


procedure TKMayor.Save(SaveStream: TKMemoryStream);
begin
  SaveStream.Write(fOwner);
  SaveStream.Write(fRoadBelowStore);
  SaveStream.Write(fDefenceTowersPlanned);
  fDefenceTowers.SaveToStream(SaveStream);

  SaveStream.Write(WarfareRatios, SizeOf(WarfareRatios));

  fBalance.Save(SaveStream);
  fCityPlanner.Save(SaveStream);
  fPathFindingRoad.Save(SaveStream);
  fPathFindingRoadShortcuts.Save(SaveStream);
end;


procedure TKMayor.Load(LoadStream: TKMemoryStream);
begin
  LoadStream.Read(fOwner);
  LoadStream.Read(fRoadBelowStore);
  LoadStream.Read(fDefenceTowersPlanned);
  fDefenceTowers.LoadFromStream(LoadStream);

  LoadStream.Read(WarfareRatios, SizeOf(WarfareRatios));

  fBalance.Load(LoadStream);
  fCityPlanner.Load(LoadStream);
  fPathFindingRoad.Load(LoadStream);
  fPathFindingRoadShortcuts.Load(LoadStream);
end;


end.
