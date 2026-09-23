-- Opt-in assistance for idle land combatants. Native forecasts, never base stats alone.
GC_Auto={}; local T=GC_Auto;
local enabled=false; local acted={}; local manual={}; local turn=-1; local owner=-1;
local elapsed=0; local grace=2; local cursor=0; local ids={}; local pending=nil; local attackOwned=false;
local selected=function() return false; end; local report=function() end;
local function Unit(id) local p=Players[Game.GetLocalPlayer()]; return p and p:GetUnits():FindID(id); end
local function Info(unit) return unit and GameInfo.Units[unit:GetType()]; end
local function Distance(unit,plot) return Map.GetPlotDistance(unit:GetX(),unit:GetY(),plot:GetX(),plot:GetY()); end
function T.Initialize(selection,callback)
  selected=selection; report=callback; acted={}; manual={}; ids={}; cursor=0;
  owner=Game.GetLocalPlayer(); turn=Game.GetCurrentGameTurn and Game.GetCurrentGameTurn() or -1;
end
local function ClearRetreat(reason)
  local old=pending; pending=nil;
  if old then
    local unit=Unit(old.id);
    if unit and old.owner==Game.GetLocalPlayer() and UnitManager.CanStartCommand(unit,UnitCommandTypes.CANCEL) then UnitManager.RequestCommand(unit,UnitCommandTypes.CANCEL); end
    print("[GC][AUTO_RETREAT_STOP] reason="..reason);
  end
end
function T.SetEnabled(value)
  enabled=value==true; grace=2; elapsed=0;
  if not enabled then
    ClearRetreat("disabled"); if attackOwned then GC_Attack.Cancel("auto_disabled"); attackOwned=false; end
  end
  report(enabled and "自动交战已开启：只处理闲置陆地战斗单位" or "自动交战已关闭");
  print("[GC][AUTO_MODE] enabled="..tostring(enabled));
end
function T.IsEnabled() return enabled; end
function T.Protect(id)
  manual[id]=Game.GetCurrentGameTurn();
  if pending and pending.id==id then ClearRetreat("manual_input"); end
end
function T.OnManualOrder(player,id)
  if player==Game.GetLocalPlayer() then T.Protect(id); end
end
function T.OnOperationAdded(player,id)
  if player==Game.GetLocalPlayer() and not GC_March.HasTask(id) and not GC_Pursuit.HasTask(id)
      and not attackOwned and not (pending and pending.id==id) then manual[id]=Game.GetCurrentGameTurn(); end
end
function T.OnCommand(player,id)
  if player~=Game.GetLocalPlayer() then return; end
  -- Native command is already starting: relinquish without cancelling it.
  manual[id]=Game.GetCurrentGameTurn();
  if pending and pending.id==id then pending=nil; end
end
function T.OnCleared(player,id)
  if pending and pending.owner==player and pending.id==id then pending.cleared=true; end
end
function T.OnEnded(player,id,op)
  if pending and pending.owner==player and pending.id==id and op==UnitOperationTypes.MOVE_TO then pending.ended=true; end
end
function T.Interrupt(reason)
  ClearRetreat(reason);
  if attackOwned then GC_Attack.Cancel(reason); attackOwned=false; end
  grace=2;
end
function T.Idle(unit)
  local info=Info(unit); local id=unit and unit:GetID(); local now=Game.GetCurrentGameTurn();
  if not info or info.Domain~="DOMAIN_LAND" or ((info.Combat or 0)<=0 and (info.RangedCombat or 0)<=0 and (info.Bombard or 0)<=0)
      or unit:IsDelayedDeath() or unit:GetFormationUnitCount()>1 or unit:GetMovesRemaining()<=0 or unit:GetAttacksRemaining()<=0 then return false; end
  if acted[id]==now or manual[id]==now or selected(id) or GC_March.HasTask(id) or GC_Pursuit.HasTask(id) then return false; end
  local head=UI.GetHeadSelectedUnit and UI.GetHeadSelectedUnit();
  if head and head:GetOwner()==unit:GetOwner() and head:GetID()==id then return false; end
  if not UnitManager.GetActivityType or not ActivityTypes or ActivityTypes.ACTIVITY_AWAKE==nil then return false; end
  if UnitManager.GetActivityType(unit)~=ActivityTypes.ACTIVITY_AWAKE then return false; end
  if unit.GetFortifyTurns and unit:GetFortifyTurns()>0 then return false; end
  return true;
end
function T.Forecast(unit,target)
  local op=GC_Attack.Operation(unit,target); if not op then return nil; end
  if not CombatManager.SimulateAttackInto or not CombatResultParameters or not CombatTypes then return nil; end
  local info=Info(unit); local kind=CombatTypes.MELEE;
  if (info.Bombard or 0)>0 then kind=CombatTypes.BOMBARD;
  elseif (info.RangedCombat or 0)>0 then kind=CombatTypes.RANGED; end
  local ok,result=pcall(CombatManager.SimulateAttackInto,unit:GetComponentID(),kind,target.x,target.y);
  if not ok or type(result)~="table" then return nil; end
  local k=CombatResultParameters; local a,d=result[k.ATTACKER],result[k.DEFENDER];
  if type(a)~="table" or type(d)~="table" then return nil; end
  for _,row in ipairs({a,d}) do
    for _,key in ipairs({k.COMBAT_STRENGTH,k.STRENGTH_MODIFIER,k.DAMAGE_TO,k.FINAL_DAMAGE_TO,k.MAX_HIT_POINTS}) do
      if type(row[key])~="number" then return nil; end
    end
  end
  local gap=a[k.COMBAT_STRENGTH]+a[k.STRENGTH_MODIFIER]-d[k.COMBAT_STRENGTH]-d[k.STRENGTH_MODIFIER];
  local extra=12;
  if GameInfo.GlobalParameters and GameInfo.GlobalParameters.COMBAT_MAX_EXTRA_DAMAGE then extra=tonumber(GameInfo.GlobalParameters.COMBAT_MAX_EXTRA_DAMAGE.Value) or extra; end
  local survives=a[k.FINAL_DAMAGE_TO]+math.max(10,extra/2)<a[k.MAX_HIT_POINTS];
  local kill=d[k.FINAL_DAMAGE_TO]>=d[k.MAX_HIT_POINTS];
  local good=survives and d[k.DAMAGE_TO]>0 and (kill or (gap>=-5 and d[k.DAMAGE_TO]>=a[k.DAMAGE_TO]-3));
  return {good=good,gap=gap,loss=a[k.DAMAGE_TO],damage=d[k.DAMAGE_TO],kill=kill};
end
local function Nearby(unit,radius)
  local start=Map.GetPlot(unit:GetX(),unit:GetY()); local plots={start}; local seen={[start:GetIndex()]=true}; local first=1;
  for step=1,radius do
    local last=#plots;
    for index=first,last do
      local plot=plots[index];
      for direction=0,5 do
        local p=Map.GetAdjacentPlot(plot:GetX(),plot:GetY(),direction);
        if p and not seen[p:GetIndex()] then plots[#plots+1]=p; seen[p:GetIndex()]=true; end
      end
    end
    first=last+1;
  end
  local enemies={}; local vis=PlayersVisibility[unit:GetOwner()];
  for _,plot in ipairs(plots) do
    if vis:IsVisible(plot:GetX(),plot:GetY()) then
      local target=GC_Attack.Target(plot:GetIndex());
      if target then
        local enemy=Players[target.owner]:GetUnits():FindID(target.id); local i=Info(enemy);
        if i and ((i.Combat or 0)>0 or (i.RangedCombat or 0)>0 or (i.Bombard or 0)>0) then
          target.range=math.max(1,enemy:GetRange()); enemies[#enemies+1]=target;
        end
      end
    end
  end
  table.sort(enemies,function(a,b)
    local da=Map.GetPlotDistance(unit:GetX(),unit:GetY(),a.x,a.y); local db=Map.GetPlotDistance(unit:GetX(),unit:GetY(),b.x,b.y);
    if da~=db then return da<db; end; if a.owner~=b.owner then return a.owner<b.owner; end; return a.id<b.id;
  end);
  return enemies;
end
local function Danger(plot,enemies)
  local margin=100; local covering=0;
  for _,e in ipairs(enemies) do
    local d=Map.GetPlotDistance(plot:GetX(),plot:GetY(),e.x,e.y)-e.range;
    margin=math.min(margin,d); if d<=0 then covering=covering+1; end
  end
  return margin,covering;
end
function T.Retreat(unit,enemies)
  local here=Map.GetPlot(unit:GetX(),unit:GetY()); local oldMargin,oldCount=Danger(here,enemies);
  local vis=PlayersVisibility[unit:GetOwner()]; local choices={};
  for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do
    local plot=Map.GetPlotByIndex(id);
    if id~=here:GetIndex() and vis:IsVisible(plot:GetX(),plot:GetY()) then
      local margin,count=Danger(plot,enemies);
      if margin>oldMargin and count<=oldCount then choices[#choices+1]={plot=plot,margin=margin,count=count,distance=Distance(unit,plot)}; end
    end
  end
  table.sort(choices,function(a,b)
    if a.count~=b.count then return a.count<b.count; end
    if a.margin~=b.margin then return a.margin>b.margin; end
    if a.distance~=b.distance then return a.distance<b.distance; end; return a.plot:GetIndex()<b.plot:GetIndex();
  end);
  for index=1,math.min(24,#choices) do
    local plot=choices[index].plot;
    -- Both checks ensure a visible complete path and neutral/own land only.
    if GC_Attack.ValidateApproach(unit,plot) and GC_March.ValidateStep(unit,plot) then
      local path=UnitManager.GetMoveToPathEx(unit,plot:GetIndex()); local safe=true;
      for _,id in ipairs(path.plots) do
        local margin,count=Danger(Map.GetPlotByIndex(id),enemies);
        if margin<oldMargin or count>oldCount then safe=false; break; end
      end
      if safe then return plot; end
    end
  end
end
function T.Update(delta)
  local now=Game.GetCurrentGameTurn(); local playerID=Game.GetLocalPlayer();
  if owner~=playerID then
    if owner~=-1 then T.SetEnabled(false); end
    owner=playerID; acted={}; manual={}; ids={}; cursor=0;
  end
  if turn~=now then
    turn=now; acted={}; for id,t in pairs(manual) do if t~=now then manual[id]=nil; end; end; grace=2; ids={}; cursor=0;
    if pending then ClearRetreat("turn_changed"); end
  end
  if not enabled then return; end
  local player=Players[playerID];
  if not player or not player:IsTurnActive() or GC_March.IsPaused() then T.Interrupt("paused"); return; end
  if pending then
    local p=pending; local unit=Unit(p.id);
    if not UI.IsGameCoreBusy() and (not unit or p.cleared or p.ended or (unit:GetX()==p.x and unit:GetY()==p.y)) then
      if unit and (unit:GetX()~=p.x or unit:GetY()~=p.y) then ClearRetreat("partial_stop"); else pending=nil; end
      report("自动避让结束；本回合不重复接管");
    elseif UI.GetElapsedTime()-p.since>20 then T.SetEnabled(false); report("自动避让结果未确认，已关闭自动交战"); end
    return;
  end
  if attackOwned and not GC_Attack.IsBusy() then
    attackOwned=false;
    if GC_Attack.LastStop()=="timeout" or GC_Attack.LastStop()=="approach_timeout" then T.SetEnabled(false); return; end
  end
  if UI.IsGameCoreBusy() or GC_Attack.IsBusy() or GC_Pursuit.IsBusy() or GC_March.IsBusy() then return; end
  if UI.GetInterfaceMode and UI.GetInterfaceMode()~=InterfaceModeTypes.SELECTION then return; end
  grace=math.max(0,grace-delta); if grace>0 then return; end
  elapsed=elapsed+delta; if elapsed<.4 then return; end; elapsed=0;
  if cursor>=#ids then ids={}; for _,unit in player:GetUnits():Members() do ids[#ids+1]=unit:GetID(); end; table.sort(ids); cursor=0; end
  cursor=cursor+1; local unit=ids[cursor] and Unit(ids[cursor]); if not T.Idle(unit) then return; end
  local targets=Nearby(unit,math.min(8,math.max(1,unit:GetRange()))); local best=nil; local losing=false;
  for index=1,math.min(8,#targets) do
    local target=targets[index]; local prediction=T.Forecast(unit,target);
    if prediction then
      if prediction.good then
        local score=(prediction.kill and 1000 or 0)+prediction.damage-prediction.loss;
        if not best or score>best.score then best={target=target,score=score}; end
      else losing=true; end
    end
  end
  if best then
    acted[unit:GetID()]=now;
    local target=best.target; local op=GC_Attack.Operation(unit,target);
    if not op then return; end
    local plan={kind="attack",owner=playerID,turn=now,target=target,orders={{id=unit:GetID(),priority=1}},waiting={},direct=1,approaching=0,directOnly=true,
      authorize=function(actor,current)
        if not actor or manual[actor:GetID()]==Game.GetCurrentGameTurn() or selected(actor:GetID()) then return false; end
        if UnitManager.GetActivityType(actor)~=ActivityTypes.ACTIVITY_AWAKE or GC_March.HasTask(actor:GetID()) or GC_Pursuit.HasTask(actor:GetID()) then return false; end
        local head=UI.GetHeadSelectedUnit and UI.GetHeadSelectedUnit();
        if head and head:GetOwner()==actor:GetOwner() and head:GetID()==actor:GetID() then return false; end
        local forecast=T.Forecast(actor,current); return forecast and forecast.good;
      end};
    attackOwned=GC_Attack.Start(plan,report);
    print("[GC][AUTO_ATTACK] unit="..unit:GetID().." target="..target.owner..":"..target.id);
  elseif losing then
    acted[unit:GetID()]=now;
    local plot=T.Retreat(unit,Nearby(unit,8));
    if not plot then report("自动避让：没有确认更安全的可达格，保持待命"); print("[GC][AUTO_HOLD] unit="..unit:GetID()); return; end
    pending={id=unit:GetID(),owner=playerID,x=plot:GetX(),y=plot:GetY(),since=UI.GetElapsedTime()};
    UnitManager.RequestOperation(unit,UnitOperationTypes.MOVE_TO,GC_Rally.Parameters(plot));
    report("自动避让：向更远离可见敌军的位置移动");
    print("[GC][AUTO_RETREAT] unit="..unit:GetID().." plot="..plot:GetIndex());
  end
end
