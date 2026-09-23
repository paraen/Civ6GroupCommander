-- First rally slice: visible land destinations reachable this turn.
-- Selection and occupancy classes are deliberately different concepts.
GC_Rally = {};
local batch=nil;
local classes = {FORMATION_CLASS_LAND_COMBAT=true, FORMATION_CLASS_CIVILIAN=true, FORMATION_CLASS_SUPPORT=true};

local function Info(unit) return GameInfo.Units[unit:GetType()]; end

function GC_Rally.UnitReason(unit)
  local info=Info(unit);
  if not info or info.Domain~="DOMAIN_LAND" or not classes[info.FormationClass] then return "暂不支持的移动类别"; end
  if info.IgnoreMoves or info.Spy or info.MakeTradeRoute then return "特殊移动单位"; end
  if unit:GetFormationUnitCount()>1 then return "护送队待适配，保持链接"; end
  if unit:GetMovesRemaining()<=0 or unit:HasMovedIntoZOC() then return "本回合无法继续移动"; end
  return nil;
end

function GC_Rally.Parameters(plot)
  return {[UnitOperationTypes.PARAM_X]=plot:GetX(), [UnitOperationTypes.PARAM_Y]=plot:GetY(),
    [UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.NONE};
end

local function PeacefulLand(plot, owner)
  if not plot or not PlayersVisibility[owner]:IsVisible(plot:GetX(),plot:GetY()) then return false; end
  if plot:IsWater() or plot:IsImpassable() then return false; end
  if plot:GetOwner()~=-1 and plot:GetOwner()~=owner then return false; end
  for _,other in ipairs(Units.GetUnitsInPlotLayerID(plot:GetX(),plot:GetY(),MapLayers.ANY)) do
    if other:GetOwner()~=owner then return false; end
  end
  return true;
end

local function DestinationFree(unit, plot)
  if not PeacefulLand(plot,unit:GetOwner()) then return false; end
  local class=Info(unit).FormationClass;
  for _,other in ipairs(Units.GetUnitsInPlotLayerID(plot:GetX(),plot:GetY(),MapLayers.ANY)) do
    local otherInfo=Info(other);
    if other:GetID()~=unit:GetID() and (not otherInfo or otherInfo.FormationClass==class) then return false; end
  end
  return true;
end

function GC_Rally.Validate(unit, plot, reachable)
  local reason=GC_Rally.UnitReason(unit);
  if reason then return false,reason; end
  if not DestinationFree(unit,plot) then return false,"落点被占用或不可进入"; end
  if unit:GetX()==plot:GetX() and unit:GetY()==plot:GetY() then return true; end
  if not reachable then
    reachable={};
    for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[id]=true; end
  end
  if not reachable[plot:GetIndex()] then return false,"本回合无法到达"; end
  if not UnitManager.CanStartOperation(unit,UnitOperationTypes.MOVE_TO,nil,GC_Rally.Parameters(plot)) then
    return false,"游戏拒绝该移动";
  end
  local path=UnitManager.GetMoveToPathEx(unit,plot:GetIndex());
  if not path or not path.plots or path.plots[#path.plots]~=plot:GetIndex() then return false,"无法确认完整路径"; end
  for _,id in ipairs(path.plots) do
    if not PeacefulLand(Map.GetPlotByIndex(id),unit:GetOwner()) then return false,"路径含迷雾、水域或其他玩家"; end
  end
  return true;
end

-- Bounded bipartite matching: one destination slot per occupancy class.
-- Reassignment avoids stranding a unit that has only one available slot.
function GC_Rally.Allocate(entries)
  local ordered={};
  for _,entry in ipairs(entries) do ordered[#ordered+1]=entry; end
  table.sort(ordered,function(a,b)
    if #a.candidates~=#b.candidates then return #a.candidates<#b.candidates; end
    return a.id<b.id;
  end);
  local slots,assigned={},{};
  local function Assign(entry,visited)
    for _,candidate in ipairs(entry.candidates) do
      local key=entry.class..":"..candidate.plot;
      if not visited[key] then
        visited[key]=true;
        if not slots[key] or Assign(slots[key],visited) then
          slots[key]=entry;
          assigned[entry.id]=candidate;
          return true;
        end
      end
    end
    return false;
  end
  for _,entry in ipairs(ordered) do Assign(entry,{}); end
  return assigned;
end

function GC_Rally.Plan(selected, targetID)
  local owner=Game.GetLocalPlayer();
  local target=targetID and targetID>=0 and Map.GetPlotByIndex(targetID);
  local plan={owner=owner,turn=Game.GetCurrentGameTurn(),target=targetID,orders={},waiting={},staying=0};
  if not Players[owner] or not Players[owner]:IsTurnActive() then plan.error="请在自己的回合下令"; return plan; end
  if not next(selected) then plan.error="请先框选单位"; return plan; end
  -- The clicked centre is not a reserved destination. Occupied centres may have
  -- free neighbours; every actual destination and its path are still validated.
  if not target or not PlayersVisibility[owner]:IsVisible(target:GetX(),target:GetY())
      or target:IsWater() or target:IsImpassable() then plan.error="请选择可见的陆地集结点"; return plan; end
  local units=Players[owner]:GetUnits();
  local entries,ids={},{};
  for id in pairs(selected) do ids[#ids+1]=id; end
  table.sort(ids);
  if #ids>64 then plan.error="当前集结测试版每批最多 64 个单位"; return plan; end
  for _,id in ipairs(ids) do
    local unit=units:FindID(id);
    local reason;
    if unit then reason=GC_Rally.UnitReason(unit); else reason="单位已不存在"; end
    if reason then plan.waiting[#plan.waiting+1]={id=id,reason=reason};
    else
      local entry={id=id,class=Info(unit).FormationClass,candidates={}};
      local reachable,plots={},{};
      for _,plotID in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[plotID]=true; end
      reachable[Map.GetPlot(unit:GetX(),unit:GetY()):GetIndex()]=true;
      for plotID in pairs(reachable) do
        local plot=Map.GetPlotByIndex(plotID);
        local distance=Map.GetPlotDistance(plot:GetX(),plot:GetY(),target:GetX(),target:GetY());
        if distance<=4 and DestinationFree(unit,plot) then
          plots[#plots+1]={plot=plotID,score=distance*100+Map.GetPlotDistance(unit:GetX(),unit:GetY(),plot:GetX(),plot:GetY())};
        end
      end
      table.sort(plots,function(a,b) if a.score~=b.score then return a.score<b.score; end return a.plot<b.plot; end);
      -- Limit expensive engine path queries per unit; later passes can widen this.
      for i=1,math.min(#plots,16) do
        if GC_Rally.Validate(unit,Map.GetPlotByIndex(plots[i].plot),reachable) then
          entry.candidates[#entry.candidates+1]=plots[i];
        end
      end
      entries[#entries+1]=entry;
    end
  end
  local assigned=GC_Rally.Allocate(entries);
  for _,entry in ipairs(entries) do
    local destination=assigned[entry.id];
    if not destination then plan.waiting[#plan.waiting+1]={id=entry.id,reason="附近没有本回合可用落点"};
    else
      local unit=units:FindID(entry.id);
      local plot=Map.GetPlotByIndex(destination.plot);
      if unit:GetX()==plot:GetX() and unit:GetY()==plot:GetY() then plan.staying=plan.staying+1;
      else plan.orders[#plan.orders+1]={id=entry.id,plot=destination.plot,x=unit:GetX(),y=unit:GetY(),class=entry.class}; end
    end
  end
  return plan;
end

function GC_Rally.SelfTest()
  local function Entry(id,class,...)
    local entry={id=id,class=class,candidates={}};
    for _,plot in ipairs({...}) do entry.candidates[#entry.candidates+1]={plot=plot}; end
    return entry;
  end
  local a=GC_Rally.Allocate({Entry(1,"combat",9,10),Entry(2,"combat",9)});
  assert(a[1].plot==10 and a[2].plot==9,"narrow destination must remain available");
  a=GC_Rally.Allocate({Entry(1,"combat",9),Entry(2,"civilian",9),Entry(3,"support",9)});
  assert(a[1] and a[2] and a[3],"different occupancy classes may share a hex");
  a=GC_Rally.Allocate({Entry(1,"civilian",9),Entry(2,"civilian",9),Entry(3,"combat")});
  assert(a[1] and not a[2] and not a[3],"same class overflow and unreachable units wait");
  print("[GC][RALLY_TEST] matching_cases=3 passed commandsIssued=0");
end

local function ClearPendingOrder(b)
  if not b.pending or b.clearRequested then return false; end
  local player=Players[b.plan.owner];
  local unit=player and player:GetUnits():FindID(b.pending.id);
  if not unit or Game.GetLocalPlayer()~=b.plan.owner then return false; end
  if UnitManager.CanStartCommand(unit,UnitCommandTypes.CANCEL) then
    b.clearRequested=true;
    UnitManager.RequestCommand(unit,UnitCommandTypes.CANCEL);
    print("[GC][RALLY_CLEAR_REQUEST] unit="..unit:GetID());
    return true;
  end
  return false;
end

function GC_Rally.OnOperationsCleared(owner,id)
  if batch and batch.pending and batch.plan.owner==owner and batch.pending.id==id then
    batch.operationCleared=true;
  end
end

function GC_Rally.OnOperationDeactivated(owner,id,operation)
  if batch and batch.pending and batch.plan.owner==owner and batch.pending.id==id
      and operation==UnitOperationTypes.MOVE_TO then batch.operationEnded=true; end
end

function GC_Rally.Cancel(reason)
  if batch then
    local old=batch;
    batch=nil;
    -- Stop unsent requests immediately; cancel the outstanding native route when possible.
    local ok,err=pcall(ClearPendingOrder,old);
    if not ok then print("[GC][RALLY_CLEAR_ERROR] "..tostring(err)); end
    print("[GC][RALLY_CANCEL] reason="..tostring(reason).." requested="..old.requested.." arrived="..old.arrived);
  end
end

function GC_Rally.Start(plan,report)
  GC_Rally.Cancel("new_batch");
  if not plan or plan.error or #plan.orders==0 then return false; end
  if Game.GetLocalPlayer()~=plan.owner or Game.GetCurrentGameTurn()~=plan.turn
      or not Players[plan.owner]:IsTurnActive() then return false; end
  batch={plan=plan,index=1,requested=0,arrived=0,stopped=0,skipped=0,report=report,elapsed=0};
  report("开始集结；Esc 可停止后续下令");
  return true;
end

function GC_Rally.Update(delta)
  if not batch then return; end
  batch.elapsed=batch.elapsed+delta;
  if batch.elapsed<0.1 then return; end
  batch.elapsed=0;
  local b=batch;
  if Game.GetLocalPlayer()~=b.plan.owner or Game.GetCurrentGameTurn()~=b.plan.turn
      or not Players[b.plan.owner]:IsTurnActive() then
    b.report("回合或玩家已变化；停止后续下令"); GC_Rally.Cancel("turn_changed"); return;
  end
  local units=Players[b.plan.owner]:GetUnits();
  if b.pending then
    local unit=units:FindID(b.pending.id);
    local plot=Map.GetPlotByIndex(b.pending.plot);
    if not unit then b.report("移动单位已消失；停止批次"); GC_Rally.Cancel("unit_gone"); return; end
    if unit:GetX()==plot:GetX() and unit:GetY()==plot:GetY() and not UI.IsGameCoreBusy() then
      b.arrived=b.arrived+1;
      print("[GC][RALLY_ARRIVED] unit="..unit:GetID().." plot="..plot:GetIndex());
      b.pending=nil;
    elseif not UI.IsGameCoreBusy() and (b.operationCleared or b.operationEnded
        or unit:GetMovesRemaining()<=0 or unit:HasMovedIntoZOC()) then
      -- Exhaustion is a normal stop, but a remaining native route must be cleared
      -- before advancing the batch, otherwise it could resume next turn.
      if not b.operationCleared and not b.clearRequested then ClearPendingOrder(b); end
      if b.operationCleared or (b.operationEnded and not b.clearRequested) then
        b.stopped=b.stopped+1;
        print("[GC][RALLY_STOPPED] unit="..unit:GetID().." moves="..unit:GetMovesRemaining().." x="..unit:GetX().." y="..unit:GetY());
        b.pending=nil;
        b.report("单位已停步；继续处理其余单位");
      elseif UI.GetElapsedTime()-b.pendingSince>15 then
        b.report("单位已停步，但路线清理未确认；停止后续下令"); GC_Rally.Cancel("clear_unconfirmed"); return;
      else return; end
    elseif UI.GetElapsedTime()-b.pendingSince>15 then
      b.report("移动结果未确认；已停止后续下令"); GC_Rally.Cancel("operation_timeout"); return;
    else return; end
  end
  if UI.IsGameCoreBusy() then return; end
  local order=b.plan.orders[b.index];
  if not order then
    b.report("结束：到达 "..b.arrived.."；停步 "..b.stopped.."；跳过 "..b.skipped.."；原地 "..b.plan.staying.."；待命 "..#b.plan.waiting);
    print("[GC][RALLY_COMPLETE] requested="..b.requested.." arrived="..b.arrived.." stopped="..b.stopped.." skipped="..b.skipped);
    batch=nil;
    return;
  end
  b.index=b.index+1;
  local unit=units:FindID(order.id);
  local plot=Map.GetPlotByIndex(order.plot);
  local valid,reason=false,"单位状态已变化";
  if unit and unit:GetX()==order.x and unit:GetY()==order.y and Info(unit).FormationClass==order.class then
    valid,reason=GC_Rally.Validate(unit,plot);
  end
  if not valid then
    b.skipped=b.skipped+1;
    print("[GC][RALLY_SKIP] unit="..order.id.." reason="..tostring(reason));
    return;
  end
  -- Revalidate before every single request; do not chain implicit attack/swap helpers.
  b.pending=order;
  b.operationEnded=false;
  b.operationCleared=false;
  b.clearRequested=false;
  b.pendingSince=UI.GetElapsedTime();
  b.requested=b.requested+1;
  UnitManager.RequestOperation(unit,UnitOperationTypes.MOVE_TO,GC_Rally.Parameters(plot));
  print("[GC][RALLY_REQUEST] unit="..order.id.." plot="..order.plot.." modifiers=NONE");
  b.report("集结中：已请求 "..b.requested.."；已到达 "..b.arrived);
end
