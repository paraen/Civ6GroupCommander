-- One confirmed attack at a time against a locked, visible unit identity.
-- Immediate attacks first, then bounded movement and a fresh native attack check.
GC_Attack={};
local A=GC_Attack;
local batch=nil;
local lastStop=nil;
local internalClears={};
local function ClearUnit(unit)
  internalClears[unit:GetOwner()..":"..unit:GetID()]=true;
  UnitManager.RequestCommand(unit,UnitCommandTypes.CANCEL);
end
function A.ConsumeInternalCommand(owner,id,command)
  local key=owner..":"..id;
  if command==UnitCommandTypes.CANCEL and internalClears[key] then internalClears[key]=nil; return true; end
  return false;
end
function A.IsBusy() return batch~=nil; end
function A.LastStop() return lastStop; end
local function AtWar(owner,other)
  local player=Players[owner];
  return player and player:GetDiplomacy():IsAtWarWith(other);
end
function A.Target(plotID)
  local owner=Game.GetLocalPlayer();
  local plot=plotID and Map.GetPlotByIndex(plotID);
  local vis=PlayersVisibility[owner];
  if not plot or not vis or not vis:IsVisible(plot:GetX(),plot:GetY()) then return nil; end
  local enemies={}; local foreign=false;
  for _,unit in ipairs(Units.GetUnitsInPlotLayerID(plot:GetX(),plot:GetY(),MapLayers.ANY)) do
    if unit:GetOwner()~=owner and vis:IsUnitVisible(unit) then
      if AtWar(owner,unit:GetOwner()) then enemies[#enemies+1]=unit; else foreign=true; end
    end
  end
  if #enemies==0 then return nil; end
  if plot:IsCity() then return nil,"城市攻击尚未适配；请使用原生攻击或选择城外敌军"; end
  if foreign then return nil,"目标格还存在未交战单位；请使用原生单兵操作"; end
  table.sort(enemies,function(a,b)
    local ai,bi=GameInfo.Units[a:GetType()],GameInfo.Units[b:GetType()];
    local ac,bc=(ai.Combat or 0)>0,(bi.Combat or 0)>0;
    if ac~=bc then return ac; end
    if a:GetOwner()~=b:GetOwner() then return a:GetOwner()<b:GetOwner(); end
    return a:GetID()<b:GetID();
  end);
  local unit=enemies[1];
  return {owner=unit:GetOwner(),id=unit:GetID(),plot=plotID,x=plot:GetX(),y=plot:GetY()};
end
function A.CheckTarget(target,owner)
  local vis=PlayersVisibility[owner];
  if not vis or not vis:IsVisible(target.x,target.y) then return nil,"目标已失去视野"; end
  if not AtWar(owner,target.owner) then return nil,"外交关系已变化"; end
  local player=Players[target.owner];
  local unit=player and player:GetUnits():FindID(target.id);
  if not unit or unit:IsDelayedDeath() then return nil,"目标已消灭或消失"; end
  if unit:GetX()~=target.x or unit:GetY()~=target.y then return nil,"目标已移动"; end
  if not vis:IsUnitVisible(unit) then return nil,"目标已不可见"; end
  local current,blocked=A.Target(target.plot);
  if blocked or not current or current.owner~=target.owner or current.id~=target.id then
    return nil,"目标格的守军已变化";
  end
  return unit;
end
local function Eligible(unit)
  if not unit or unit:IsDelayedDeath() then return nil,"单位已不存在"; end
  local info=GameInfo.Units[unit:GetType()];
  if not info or ((info.Combat or 0)<=0 and (info.RangedCombat or 0)<=0 and (info.Bombard or 0)<=0) then
    return nil,"非战斗单位待命";
  end
  if unit:GetFormationUnitCount()>1 then return nil,"护送队待适配，保持链接"; end
  if unit:GetMovesRemaining()<=0 or unit:GetAttacksRemaining()<=0 then return nil,"本回合不能继续攻击"; end
  return info;
end
function A.Operation(unit,target)
  local info,reason=Eligible(unit); if not info then return nil,reason; end
  local args={[UnitOperationTypes.PARAM_X]=target.x,[UnitOperationTypes.PARAM_Y]=target.y,
    [UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.NONE};
  local op=UnitOperationTypes.RANGE_ATTACK;
  if info.Domain=="DOMAIN_AIR" then
    op=UnitOperationTypes.AIR_ATTACK; args[UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.ATTACK;
  elseif (info.RangedCombat or 0)<=0 and (info.Bombard or 0)<=0 then
    if Map.GetPlotDistance(unit:GetX(),unit:GetY(),target.x,target.y)~=1 then
      return nil,"近战须先移动到目标相邻格";
    end
    op=UnitOperationTypes.MOVE_TO; args[UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.ATTACK;
  end
  local warChanges=CombatManager.IsAttackChangeWarState(unit:GetComponentID(),target.x,target.y);
  if warChanges and #warChanges>0 then return nil,"此攻击将引发新的战争"; end
  if not UnitManager.CanStartOperation(unit,op,nil,args) then return nil,"当前位置无法攻击（射程、视线或单位状态）"; end
  return op,args;
end

local function ApproachPlot(unit,plot,destination)
  local owner=unit:GetOwner(); local vis=PlayersVisibility[owner];
  if not plot or not vis:IsVisible(plot:GetX(),plot:GetY()) then return false; end
  if plot:IsWater() or plot:IsImpassable() then return false; end
  local landOwner=plot:GetOwner();
  if landOwner~=-1 and landOwner~=owner and not AtWar(owner,landOwner) then return false; end
  for _,other in ipairs(Units.GetUnitsInPlotLayerID(plot:GetX(),plot:GetY(),MapLayers.ANY)) do
    if vis:IsUnitVisible(other) then
      if other:GetOwner()~=owner then return false; end
      if destination and other:GetID()~=unit:GetID() then
        local info=GameInfo.Units[other:GetType()];
        if not info or info.FormationClass==GameInfo.Units[unit:GetType()].FormationClass then return false; end
      end
    end
  end
  return true;
end
function A.ValidateApproach(unit,plot,reachable)
  if not Eligible(unit) or not ApproachPlot(unit,plot,true) then return false; end
  if not reachable then
    reachable={}; for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[id]=true; end
  end
  if not reachable[plot:GetIndex()] then return false; end
  local args={[UnitOperationTypes.PARAM_X]=plot:GetX(),[UnitOperationTypes.PARAM_Y]=plot:GetY(),
    [UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.NONE};
  local changes=CombatManager.IsAttackChangeWarState(unit:GetComponentID(),plot:GetX(),plot:GetY());
  if changes and #changes>0 then return false; end
  if not UnitManager.CanStartOperation(unit,UnitOperationTypes.MOVE_TO,nil,args) then return false; end
  local path=UnitManager.GetMoveToPathEx(unit,plot:GetIndex());
  if not path or not path.plots or path.plots[#path.plots]~=plot:GetIndex() then return false; end
  local pathTurn=path.turns and path.turns[#path.plots];
  if pathTurn and pathTurn>1 then return false; end
  for _,id in ipairs(path.plots) do if not ApproachPlot(unit,Map.GetPlotByIndex(id),false) then return false; end; end
  return true,args;
end
function A.ApproachCandidates(unit,target,cohesionFloor)
  local info,reason=Eligible(unit);
  if not info then return {},reason; end
  if info.Domain~="DOMAIN_LAND" then return {},"海空单位接敌移动待适配"; end
  local range=1;
  if (info.RangedCombat or 0)>0 or (info.Bombard or 0)>0 then range=math.max(1,unit:GetRange()); end
  local distance=Map.GetPlotDistance(unit:GetX(),unit:GetY(),target.x,target.y);
  local route=UnitManager.GetMoveToPathEx(unit,target.plot); local onRoute={};
  if route and route.plots then for i,id in ipairs(route.plots) do if i>1 then onRoute[id]=true; end; end; end
  local reachable,options={},{};
  for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[id]=true; end
  for id in pairs(reachable) do
    local plot=Map.GetPlotByIndex(id);
    if id~=target.plot and (plot:GetX()~=unit:GetX() or plot:GetY()~=unit:GetY()) then
      local d=Map.GetPlotDistance(plot:GetX(),plot:GetY(),target.x,target.y);
      if (d<distance or distance<=range or onRoute[id]) and (not cohesionFloor or d>=cohesionFloor) then
        options[#options+1]={plot=id,score=math.abs(d-range)*1000+Map.GetPlotDistance(unit:GetX(),unit:GetY(),plot:GetX(),plot:GetY())};
      end
    end
  end
  table.sort(options,function(a,b) if a.score~=b.score then return a.score<b.score; end; return a.plot<b.plot; end);
  local candidates={};
  for i=1,math.min(24,#options) do
    local item=options[i];
    if A.ValidateApproach(unit,Map.GetPlotByIndex(item.plot),reachable) then candidates[#candidates+1]=item; end
  end
  return candidates,#candidates==0 and "没有本回合合法接敌位置" or nil;
end

-- Limit the fast vanguard to two tiles ahead of the slowest mobile member's
-- native reachable frontier. Adjacent firing opportunities remain unrestricted.
function A.CohesionFloor(selected,target,owner)
  local rear=0; local count=0;
  for id in pairs(selected) do
    local unit=Players[owner]:GetUnits():FindID(id); local info=unit and GameInfo.Units[unit:GetType()];
    if info and info.Domain=="DOMAIN_LAND" and ((info.Combat or 0)>0 or (info.RangedCombat or 0)>0) and unit:GetFormationUnitCount()==1 then
      local best=Map.GetPlotDistance(unit:GetX(),unit:GetY(),target.x,target.y);
      for _,plotID in ipairs(UnitManager.GetReachableMovement(unit) or {}) do
        local plot=Map.GetPlotByIndex(plotID);
        best=math.min(best,Map.GetPlotDistance(plot:GetX(),plot:GetY(),target.x,target.y));
      end
      rear=math.max(rear,best); count=count+1;
    end
  end
  return count>1 and math.max(0,rear-2) or nil;
end
function A.Plan(selected,target,coordinated,cohesionFloor)
  local owner=Game.GetLocalPlayer();
  local plan={kind="attack",owner=owner,turn=Game.GetCurrentGameTurn(),target=target,orders={},waiting={},direct=0,approaching=0};
  if not Players[owner] or not Players[owner]:IsTurnActive() then plan.error="请在自己的回合下令"; return plan; end
  local valid,reason=A.CheckTarget(target,owner);
  if not valid then plan.error=reason; return plan; end
  local ids={}; for id in pairs(selected) do ids[#ids+1]=id; end; table.sort(ids);
  if #ids==0 then plan.error="请先框选单位"; return plan; end
  if #ids>64 then plan.error="每批最多 64 个单位"; return plan; end
  local approach={};
  plan.coordinated=coordinated;
  plan.cohesionFloor=cohesionFloor or (coordinated and A.CohesionFloor(selected,target,owner) or nil);
  for _,id in ipairs(ids) do
    local unit=Players[owner]:GetUnits():FindID(id);
    local op,args=A.Operation(unit,target);
    if op then
      plan.orders[#plan.orders+1]={id=id,priority=op==UnitOperationTypes.MOVE_TO and 2 or 1};
      plan.direct=plan.direct+1;
    else
      local candidates,reason=A.ApproachCandidates(unit,target,plan.cohesionFloor);
      if #candidates>0 then
        approach[#approach+1]={id=id,class=GameInfo.Units[unit:GetType()].FormationClass,candidates=candidates};
      else
        plan.waiting[#plan.waiting+1]={id=id,reason=reason or args};
        print("[GC][ATTACK_WAIT] unit="..id.." reason="..tostring(reason or args));
      end
    end
  end
  local assigned=GC_Rally.Allocate(approach);
  for _,entry in ipairs(approach) do
    local chosen=assigned[entry.id];
    if chosen then
      plan.orders[#plan.orders+1]={id=entry.id,priority=3,approach=chosen.plot,class=entry.class,scarcity=#entry.candidates};
      plan.approaching=plan.approaching+1;
    else plan.waiting[#plan.waiting+1]={id=entry.id,reason="本回合接敌位置不足"}; end
  end
  table.sort(plan.orders,function(a,b) if a.priority~=b.priority then return a.priority<b.priority; end; if a.priority==3 and a.scarcity~=b.scarcity then return a.scarcity<b.scarcity; end; return a.id<b.id; end);
  print("[GC][ATTACK_PLAN] target="..target.owner..":"..target.id.." direct="..plan.direct.." approach="..plan.approaching.." waiting="..#plan.waiting);
  return plan;
end
function A.Cancel(reason)
  lastStop=reason;
  local old=batch; batch=nil;
  if not old then return; end
  if old.pending and old.pending.op==UnitOperationTypes.MOVE_TO then
    local player=Players[old.plan.owner];
    local unit=player and player:GetUnits():FindID(old.pending.id);
    if unit and Game.GetLocalPlayer()==old.plan.owner then
      local ok,err=pcall(function()
        if UnitManager.CanStartCommand(unit,UnitCommandTypes.CANCEL) then ClearUnit(unit); end
      end);
      if not ok then print("[GC][ATTACK_CLEAR_ERROR] "..tostring(err)); end
    end
  end
  print("[GC][ATTACK_CANCEL] reason="..tostring(reason).." requested="..old.requested.." confirmed="..old.confirmed);
end
function A.Start(plan,report)
  A.Cancel("new_batch");
  if not plan or plan.error or #plan.orders==0 or plan.owner~=Game.GetLocalPlayer()
      or plan.turn~=Game.GetCurrentGameTurn() or not Players[plan.owner]:IsTurnActive() then return false; end
  if not A.CheckTarget(plan.target,plan.owner) then return false; end
  lastStop=nil;
  batch={plan=plan,report=report,index=1,requested=0,confirmed=0,skipped=0,advanced=0,staged=0,elapsed=0,reserved={}};
  for _,order in ipairs(plan.orders) do
    if order.approach then batch.reserved[order.class..":"..order.approach]=order.id; end
  end
  report("开始推进与攻击；能攻击先攻击，其余接敌后重查");
  return true;
end
function A.OnManualOrder(owner,id)
  if not batch or batch.plan.owner~=owner then return; end
  for _,order in ipairs(batch.plan.orders) do
    if order.id==id then A.Cancel("manual_order"); return; end
  end
end
function A.OnCleared(owner,id)
  if batch and batch.plan.owner==owner and batch.pending and batch.pending.id==id then batch.pending.cleared=true; end
end
function A.OnEnded(owner,id,op)
  if batch and batch.plan.owner==owner and batch.pending and batch.pending.id==id and batch.pending.op==op then batch.pending.ended=true; end
end
local function ReleaseReservation(b,id)
  for key,owner in pairs(b.reserved) do if owner==id then b.reserved[key]=nil; end; end
end
local function RequestAttack(b,unit,op,args)
  ReleaseReservation(b,unit:GetID());
  b.pending={id=unit:GetID(),op=op,kind="attack",attacks=unit:GetAttacksRemaining(),since=UI.GetElapsedTime()};
  b.requested=b.requested+1;
  UnitManager.RequestOperation(unit,op,args);
  print("[GC][ATTACK_REQUEST] unit="..unit:GetID().." target="..b.plan.target.owner..":"..b.plan.target.id.." operation="..tostring(op));
  b.report("攻击中：已请求 "..b.requested.."；已确认 "..b.confirmed.."；已接敌 "..b.advanced);
end
function A.Update(delta)
  local b=batch; if not b then return; end
  b.elapsed=b.elapsed+delta; if b.elapsed<0.1 then return; end; b.elapsed=0;
  if Game.GetLocalPlayer()~=b.plan.owner or Game.GetCurrentGameTurn()~=b.plan.turn or not Players[b.plan.owner]:IsTurnActive() then
    b.report("回合或玩家变化；攻击停止"); A.Cancel("turn_changed"); return;
  end
  if UI.IsGameCoreBusy() then
    if b.pending and UI.GetElapsedTime()-b.pending.since>20 then b.report("攻击结果超时；停止后续命令"); A.Cancel("timeout"); end
    return;
  end
  local target,reason=A.CheckTarget(b.plan.target,b.plan.owner);
  if not target then b.report(reason.."；停止后续攻击"); A.Cancel("target_changed: "..reason); return; end
  local units=Players[b.plan.owner]:GetUnits();
  if b.pending then
    local p=b.pending; local u=units:FindID(p.id);
    if p.kind=="approach" then
      if not u or u:IsDelayedDeath() then ReleaseReservation(b,p.id); b.pending=nil; b.skipped=b.skipped+1;
      else
        local arrived=u:GetX()==p.x and u:GetY()==p.y;
        if not arrived and not p.cleared and not p.clearRequested
            and (p.ended or u:GetMovesRemaining()<=0 or u:HasMovedIntoZOC()) then
          if UnitManager.CanStartCommand(u,UnitCommandTypes.CANCEL) then
            p.clearRequested=true; ClearUnit(u);
          end
        end
        if arrived or p.cleared or (p.ended and not p.clearRequested) then
          local moved=u:GetX()~=p.startX or u:GetY()~=p.startY;
          b.pending=nil; ReleaseReservation(b,p.id);
          if moved then b.advanced=b.advanced+1; end
          print("[GC][ATTACK_APPROACH_DONE] unit="..u:GetID().." moved="..tostring(moved).." x="..u:GetX().." y="..u:GetY());
          local op,args=A.Operation(u,b.plan.target);
          if op then RequestAttack(b,u,op,args); return;
          else
            if moved then b.staged=b.staged+1; else b.skipped=b.skipped+1; end
            print("[GC][ATTACK_AFTER_MOVE_WAIT] unit="..u:GetID().." reason="..args);
            b.report("已接敌；本回合无法攻击的单位停步待命");
          end
        elseif UI.GetElapsedTime()-p.since>20 then
          b.report("接敌移动结果未确认；停止批次"); A.Cancel("approach_timeout"); return;
        else return; end
      end
    elseif not u or u:IsDelayedDeath() then
      print("[GC][ATTACK_UNIT_GONE] unit="..p.id);
      ReleaseReservation(b,p.id); b.pending=nil; b.skipped=b.skipped+1;
    elseif u:GetAttacksRemaining()<b.pending.attacks then
      b.confirmed=b.confirmed+1;
      print("[GC][ATTACK_CONFIRMED] unit="..b.pending.id);
      b.pending=nil;
    elseif UI.GetElapsedTime()-b.pending.since>20 then
      b.report("攻击结果未确认；停止后续命令"); A.Cancel("timeout"); return;
    else return; end
  end
  local order=b.plan.orders[b.index];
  if not order and b.plan.coordinated and not b.reconsidered then
    b.reconsidered=true;
    local waiting={}; for _,item in ipairs(b.plan.waiting) do waiting[item.id]=true; end
    if next(waiting) then
      local retry=A.Plan(waiting,b.plan.target,true,b.plan.cohesionFloor);
      local scheduled={};
      for _,item in ipairs(retry.orders) do
        b.plan.orders[#b.plan.orders+1]=item; scheduled[item.id]=true;
        if item.approach then b.reserved[item.class..":"..item.approach]=item.id; end
      end
      local remaining={}; for _,item in ipairs(b.plan.waiting) do if not scheduled[item.id] then remaining[#remaining+1]=item; end; end
      b.plan.waiting=remaining;
      print("[GC][ATTACK_REPLAN] newly_available="..#retry.orders);
      order=b.plan.orders[b.index];
    end
  end
  if not order then
    b.report("结束：攻击 "..b.confirmed.."；接敌 "..b.advanced.."；接敌后待命 "..b.staged.."；未行动 "..(b.skipped+#b.plan.waiting));
    print("[GC][ATTACK_COMPLETE] requested="..b.requested.." confirmed="..b.confirmed.." approach="..b.advanced.." staged="..b.staged.." skipped="..b.skipped);
    batch=nil; return;
  end
  b.index=b.index+1;
  local unit=units:FindID(order.id);
  if b.plan.authorize and not b.plan.authorize(unit,b.plan.target) then A.Cancel("authorization_changed"); return; end
  local op,args=A.Operation(unit,b.plan.target);
  if op then RequestAttack(b,unit,op,args); return; end
  if b.plan.directOnly then b.skipped=b.skipped+1; return; end
  local candidates,reason=A.ApproachCandidates(unit,b.plan.target,b.plan.cohesionFloor);
  -- Honor the globally allocated landing slot before trying alternatives.
  for index,candidate in ipairs(candidates) do
    if candidate.plot==order.approach then table.remove(candidates,index); table.insert(candidates,1,candidate); break; end
  end
  local class=unit and GameInfo.Units[unit:GetType()].FormationClass;
  for _,candidate in ipairs(candidates) do
    local key=class..":"..candidate.plot;
    if not b.reserved[key] or b.reserved[key]==order.id then
      local plot=Map.GetPlotByIndex(candidate.plot); local valid,moveArgs=A.ValidateApproach(unit,plot);
      if valid then
        if order.approach then b.reserved[order.class..":"..order.approach]=nil; end
        b.reserved[key]=order.id;
        b.pending={id=order.id,op=UnitOperationTypes.MOVE_TO,kind="approach",x=plot:GetX(),y=plot:GetY(),
          startX=unit:GetX(),startY=unit:GetY(),since=UI.GetElapsedTime()};
        UnitManager.RequestOperation(unit,UnitOperationTypes.MOVE_TO,moveArgs);
        print("[GC][ATTACK_APPROACH_REQUEST] unit="..order.id.." plot="..candidate.plot.." modifiers=NONE");
        b.report("接敌移动中；到位后按剩余移动力重新检查攻击"); return;
      end
    end
  end
  ReleaseReservation(b,order.id);
  b.skipped=b.skipped+1; print("[GC][ATTACK_SKIP] unit="..order.id.." reason="..tostring(reason or args or "接敌格已占用"));
end
