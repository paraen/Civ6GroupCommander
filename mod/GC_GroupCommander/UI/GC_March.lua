-- Save-backed, multi-turn land missions. The engine supplies paths/costs.
-- Never inspect live terrain, ownership or occupants outside current visibility.
GC_March={};
local M=GC_March;
local mission=nil;
local lastSnapshot=nil;
local restoreAttempted=false;
local persistWarning=false;
local paused={};
local clearing={};
local allowed={FORMATION_CLASS_LAND_COMBAT=true,FORMATION_CLASS_CIVILIAN=true,FORMATION_CLASS_SUPPORT=true};
local function Info(u) return GameInfo.Units[u:GetType()]; end
local function Position(u) return Map.GetPlot(u:GetX(),u:GetY()):GetIndex(); end
local function Distance(a,b) return Map.GetPlotDistance(a:GetX(),a:GetY(),b:GetX(),b:GetY()); end
local function Find(owner,id) return Players[owner] and Players[owner]:GetUnits():FindID(id); end
local function Supported(u)
  local i=u and Info(u);
  if not i or i.Domain~="DOMAIN_LAND" or not allowed[i.FormationClass] then return "仅支持陆地行军"; end
  if i.IgnoreMoves or i.Spy or i.MakeTradeRoute then return "特殊移动单位待适配"; end
  if u:GetFormationUnitCount()>1 then return "保持护送链接，暂不接管"; end
end
function M.HasTask(id) return mission and mission.tasks[id]~=nil or false; end
function M.IsBusy() return mission~=nil; end
function M.IsPaused() return next(paused)~=nil; end
local waitTurn=-1;
local waited={};
function M.WaitForNextTurn(unit,reason)
  if not unit or unit:GetOwner()~=Game.GetLocalPlayer() or unit:GetMovesRemaining()<=0 then return false; end
  local id=unit:GetID(); local owner=unit:GetOwner(); local turn=Game.GetCurrentGameTurn();
  if not M.HasTask(id) and not (GC_Pursuit and GC_Pursuit.HasTask(id)) then return false; end
  if not Players[owner]:IsTurnActive() or UI.IsGameCoreBusy() or M.IsPaused() then return false; end
  if waitTurn~=turn then waitTurn=turn; waited={}; end
  local key=owner..":"..id;
  if waited[key] then return false; end
  if not UnitManager.GetActivityType or not ActivityTypes or ActivityTypes.ACTIVITY_AWAKE==nil
      or UnitManager.GetActivityType(unit)~=ActivityTypes.ACTIVITY_AWAKE then return false; end
  local op=UnitOperationTypes.SKIP_TURN;
  if not op and GameInfo.UnitOperations then
    local row=GameInfo.UnitOperations["UNITOPERATION_SKIP_TURN"]; op=row and row.Hash;
  end
  if not op or not UnitManager.CanStartOperation(unit,op) then return false; end
  waited[key]=true;
  print("[GC][TASK_WAIT_TURN] unit="..id.." moves="..unit:GetMovesRemaining().." reason="..reason);
  UnitManager.RequestOperation(unit,op);
  return true;
end
function M.Parameters(plot)
  return {[UnitOperationTypes.PARAM_X]=plot:GetX(),[UnitOperationTypes.PARAM_Y]=plot:GetY(),
    [UnitOperationTypes.PARAM_MODIFIERS]=UnitOperationMoveModifiers.MOVE_IGNORE_UNEXPLORED_DESTINATION};
end
function M.KnownSafe(owner,plot,unit,destination)
  if not plot then return false; end
  local vis=PlayersVisibility[owner];
  if not vis:IsVisible(plot:GetX(),plot:GetY()) then return true; end
  if plot:IsWater() or plot:IsImpassable() then return false; end
  if plot:GetOwner()~=-1 and plot:GetOwner()~=owner then return false; end
  for _,other in ipairs(Units.GetUnitsInPlotLayerID(plot:GetX(),plot:GetY(),MapLayers.ANY)) do
    if vis:IsUnitVisible(other) then
      if other:GetOwner()~=owner then return false; end
      if destination and unit and other:GetID()~=unit:GetID() then
        local i=Info(other);
        if not i or i.FormationClass==Info(unit).FormationClass then return false; end
      end
    end
  end
  return true;
end
local function Around(plot)
  local list={plot}; local seen={[plot:GetIndex()]=true}; local first=1;
  for radius=1,4 do
    local last=#list;
    for index=first,last do
      for direction=0,5 do
        local p=Map.GetAdjacentPlot(list[index]:GetX(),list[index]:GetY(),direction);
        if p and not seen[p:GetIndex()] then seen[p:GetIndex()]=true; list[#list+1]=p; end
      end
    end
    first=last+1;
  end
  return list;
end
function M.ValidateStep(unit,plot,reachable)
  local reason=Supported(unit);
  if reason then return false,reason; end
  if unit:GetMovesRemaining()<=0 or unit:HasMovedIntoZOC() then return false,"本回合移动结束"; end
  if not M.KnownSafe(unit:GetOwner(),plot,unit,true) then return false,"落点被占用或出现阻碍"; end
  if not UnitManager.CanStartOperation(unit,UnitOperationTypes.MOVE_TO,nil,M.Parameters(plot)) then return false,"引擎拒绝移动"; end
  local path=UnitManager.GetMoveToPathEx(unit,plot:GetIndex());
  if not path or not path.plots or path.plots[#path.plots]~=plot:GetIndex() then return false,"没有完整的本回合路径"; end
  local turn=path.turns and path.turns[#path.plots];
  if turn then
    if turn>1 then return false,"中间落点本回合不可达"; end
  else
    if not reachable then reachable={}; for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[id]=true; end; end
    if not reachable[plot:GetIndex()] then return false,"无法确认本回合可达性"; end
  end
  for _,id in ipairs(path.plots) do
    if not M.KnownSafe(unit:GetOwner(),Map.GetPlotByIndex(id),unit,false) then return false,"途中出现可见阻碍"; end
  end
  return true;
end
local function Candidates(unit,goal)
  if unit:GetMovesRemaining()<=0 or unit:HasMovedIntoZOC() then return {},"移动力耗尽，下回合继续"; end
  local reachable={}; for _,id in ipairs(UnitManager.GetReachableMovement(unit) or {}) do reachable[id]=true; end
  local route=UnitManager.GetMoveToPathEx(unit,goal);
  local options,seen={},{};
  if route and route.plots then
    for index=#route.plots,1,-1 do
      local id=route.plots[index]; local turn=route.turns and route.turns[index];
      if id~=Position(unit) and (turn and turn<=1 or not turn and reachable[id]) and not seen[id] then
        options[#options+1]={plot=id,score=-index}; seen[id]=true;
      end
    end
  end
  -- If the native long path stops at the frontier, use native reachable paths
  -- toward the clicked coordinates. No hidden map content is inspected.
  local target=Map.GetPlotByIndex(goal); local here=Map.GetPlotByIndex(Position(unit));
  local fallback={};
  for id in pairs(reachable) do
    local p=Map.GetPlotByIndex(id);
    if not seen[id] and id~=Position(unit) and Distance(p,target)<Distance(here,target) then
      fallback[#fallback+1]={plot=id,score=Distance(p,target)};
    end
  end
  table.sort(fallback,function(a,b) if a.score~=b.score then return a.score<b.score; end; return a.plot<b.plot; end);
  for _,item in ipairs(fallback) do options[#options+1]=item; end
  local result={};
  for index=1,math.min(#options,20) do
    local item=options[index];
    if M.ValidateStep(unit,Map.GetPlotByIndex(item.plot),reachable) then result[#result+1]=item; end
  end
  return result,#result==0 and "路径暂时受阻，下回合重查" or nil;
end
function M.Steps(goals,owner)
  local entries,waiting={},{};
  for _,g in ipairs(goals) do
    local u=Find(owner,g.id);
    if u and not Supported(u) and Position(u)~=g.goal then
      local candidates,reason=Candidates(u,g.goal);
      if #candidates>0 then entries[#entries+1]={id=g.id,class=g.class,candidates=candidates};
      else waiting[#waiting+1]={id=g.id,reason=reason}; end
    end
  end
  local assigned=GC_Rally.Allocate(entries); local orders={};
  for _,e in ipairs(entries) do
    local a=assigned[e.id]; local u=Find(owner,e.id);
    if a then orders[#orders+1]={id=e.id,plot=a.plot,class=e.class,x=u:GetX(),y=u:GetY()};
    else waiting[#waiting+1]={id=e.id,reason="本回合停留格不足，下回合重查"}; end
  end
  return orders,waiting;
end
function M.Plan(selected,targetID)
  local owner=Game.GetLocalPlayer(); local target=targetID and targetID>=0 and Map.GetPlotByIndex(targetID);
  local p={kind="march",owner=owner,turn=Game.GetCurrentGameTurn(),target=targetID,goals={},orders={},waiting={},staying=0};
  if not Players[owner] or not Players[owner]:IsTurnActive() then p.error="请在自己的回合下令"; return p; end
  if not target then p.error="请选择地图上的目标格"; return p; end
  local ids={}; for id in pairs(selected) do ids[#ids+1]=id; end; table.sort(ids);
  if #ids==0 or #ids>64 then p.error="请框选 1 至 64 个单位"; return p; end
  local plots=Around(target); local entries={};
  for _,id in ipairs(ids) do
    local u=Find(owner,id); local reason=Supported(u);
    if reason then p.waiting[#p.waiting+1]={id=id,reason=reason};
    else
      local candidates={};
      for _,plot in ipairs(plots) do
        if M.KnownSafe(owner,plot,u,true) then
          candidates[#candidates+1]={plot=plot:GetIndex(),score=Distance(plot,target)*1000+Distance(Map.GetPlotByIndex(Position(u)),plot)};
        end
      end
      table.sort(candidates,function(a,b) if a.score~=b.score then return a.score<b.score; end; return a.plot<b.plot; end);
      entries[#entries+1]={id=id,class=Info(u).FormationClass,candidates=candidates};
    end
  end
  local assigned=GC_Rally.Allocate(entries);
  for _,e in ipairs(entries) do
    local a=assigned[e.id];
    if a then
      p.goals[#p.goals+1]={id=e.id,goal=a.plot,class=e.class};
      if Position(Find(owner,e.id))==a.plot then p.staying=p.staying+1; end
    else p.waiting[#p.waiting+1]={id=e.id,reason="最终目标附近没有可分配落点"}; end
  end
  local wait; p.orders,wait=M.Steps(p.goals,owner);
  for _,item in ipairs(wait) do p.waiting[#p.waiting+1]=item; end
  print("[GC][MARCH_PLAN] target="..targetID.." goals="..#p.goals.." steps="..#p.orders.." waiting="..#p.waiting);
  return p;
end
local function Count()
  local n=0; if mission then for _ in pairs(mission.tasks) do n=n+1; end; end; return n;
end
local function Report(message)
  if mission and mission.report then mission.report(message); end
end
local function ClearOrder(owner,id)
  local u=Find(owner,id);
  if u and owner==Game.GetLocalPlayer() and UnitManager.CanStartCommand(u,UnitCommandTypes.CANCEL) then
    clearing[id]=true;
    UnitManager.RequestCommand(u,UnitCommandTypes.CANCEL);
    print("[GC][MARCH_CLEAR] unit="..id); return true;
  end
  return false;
end
-- Only the gameplay script writes properties; UI requests use the native
-- EXECUTE_SCRIPT bridge used by the shipped Black Death scenario.
local function Snapshot()
  if not mission then return ""; end
  local b=mission;
  local rows={table.concat({2,b.owner,b.target,Game.GetCurrentGameTurn(),b.arrived,b.released,b.pending and b.pending.id or -1},",")};
  local ids={}; for id in pairs(b.tasks) do ids[#ids+1]=id; end; table.sort(ids);
  for _,id in ipairs(ids) do
    local g=b.tasks[id];
    rows[#rows+1]=table.concat({id,g.goal,g.expected,g.blocked,g.kind or -1,g.lastIssued or -1},",");
  end
  return table.concat(rows,";");
end
function M.Persist()
  local owner=mission and mission.owner or Game.GetLocalPlayer();
  if owner~=Game.GetLocalPlayer() or owner<0 then return; end
  local value=Snapshot(); if value==lastSnapshot then return; end
  if not UI.RequestPlayerOperation or not PlayerOperations or not PlayerOperations.EXECUTE_SCRIPT then
    if not persistWarning then print("[GC][MARCH_SAVE_UNAVAILABLE] native property bridge unavailable"); persistWarning=true; end
    return;
  end
  UI.RequestPlayerOperation(owner,PlayerOperations.EXECUTE_SCRIPT,{OnStart="GC_SaveMarchV2",action=value=="" and "clear" or "save",value=value=="" and "0" or value});
  lastSnapshot=value;
end
function M.Restore(report,preview)
  if restoreAttempted or mission then return false; end
  local owner=Game.GetLocalPlayer(); local player=Players[owner];
  if not player or not player.GetProperty then return false; end
  restoreAttempted=true;
  local value=player:GetProperty("GC_MarchV2");
  if type(value)~="string" or value=="" then return false; end
  if #value>12000 then print("[GC][MARCH_RESTORE_REJECT] oversized"); return false; end
  local rows={};
  for row in value:gmatch("[^;]+") do
    local fields={}; for v in row:gmatch("[^,]+") do
      local n=tonumber(v); if not n or n~=math.floor(n) then return false; end
      fields[#fields+1]=n;
    end; rows[#rows+1]=fields;
  end
  local h=rows[1]; local turn=Game.GetCurrentGameTurn();
  if not h or #h~=7 or h[1]~=2 or h[2]~=owner or h[3]<0 or h[4]<0 or h[4]>turn or h[5]<0 or h[6]<0 or #rows>65 or not Map.GetPlotByIndex(h[3]) then
    print("[GC][MARCH_RESTORE_REJECT] invalid header"); return false;
  end
  local b={owner=owner,target=h[3],tasks={},report=report,preview=preview,ready=player:IsTurnActive(),delay=.75,
    arrived=h[5],released=h[6],elapsed=0,orders={},index=1,lastBegin=turn};
  for index=2,#rows do
    local f=rows[index]; local unit=#f==6 and Find(owner,f[1]);
    -- Unconfirmed in-flight commands are deliberately not replayed after load.
    if unit and f[1]~=h[7] and not Supported(unit) and unit:GetType()==f[5]
        and Position(unit)==f[3] and f[2]>=0 and Map.GetPlotByIndex(f[2]) and not b.tasks[f[1]]
        and f[4]>=0 and f[4]<3 and f[6]<=turn then
      b.tasks[f[1]]={id=f[1],goal=f[2],expected=f[3],blocked=f[4],kind=f[5],lastIssued=f[6],class=Info(unit).FormationClass};
    else b.released=b.released+1; end
  end
  mission=b; lastSnapshot=value;
  report("已恢复行军；状态不符或存档时正在执行的单位已释放");
  print("[GC][MARCH_RESTORE] units="..Count().." released="..b.released);
  M.Persist(); return true;
end
function M.Shutdown()
  -- Keep the last acknowledged save-backed mission. Do not queue a cancel
  -- while the game is shutting down or overwrite the saved mission with nil.
  mission=nil; restoreAttempted=false; lastSnapshot=nil; waitTurn=-1; waited={};
end
function M.Cancel(reason)
  local old=mission; mission=nil;
  if old and old.owner==Game.GetLocalPlayer() then M.Persist(); end
  if not old then return; end
  if old.pending then
    local ok,err=pcall(ClearOrder,old.owner,old.pending.id);
    if not ok then print("[GC][MARCH_CLEAR_ERROR] "..tostring(err)); end
  end
  old.report(reason=="unconfirmed" and "行军结果无法确认，已停止；请检查单位状态" or "行军已停止；已发生的移动保留");
  print("[GC][MARCH_CANCEL] reason="..tostring(reason));
end
function M.Release(owner,id,reason)
  if not mission or mission.owner~=owner or not mission.tasks[id] then return; end
  mission.tasks[id]=nil; mission.released=mission.released+1;
  -- Manual orders own the unit now; do not cancel the replacement operation.
  if mission.pending and mission.pending.id==id then mission.pending=nil; end
  Report("单位 "..id.." 退出行军："..reason);
  print("[GC][MARCH_RELEASE] unit="..id.." reason="..reason); M.Persist();
end
function M.OnOperationAdded(owner,id,op)
  if not mission or mission.owner~=owner or not mission.tasks[id] then return; end
  -- This notification is not proof of a user command. Native movement can emit
  -- multiple operations and identifiers differ from the request enum in-game.
  print("[GC][MARCH_OPERATION_EVENT] unit="..id.." operation="..tostring(op));
end
function M.OnManualOrder(owner,id)
  M.Release(owner,id,"玩家手动下令");
end
function M.OnCommandStarted(owner,id,command)
  if command==UnitCommandTypes.CANCEL and clearing[id] then clearing[id]=nil; return; end
  M.Release(owner,id,"玩家接管单位");
end
function M.OnCleared(owner,id)
  if mission and mission.owner==owner and mission.pending and mission.pending.id==id then mission.pending.cleared=true; end
end
function M.OnEnded(owner,id,op)
  if mission and mission.owner==owner and mission.pending and mission.pending.id==id and op==UnitOperationTypes.MOVE_TO then mission.pending.ended=true; end
end
function M.SetPaused(key,value) paused[key]=value and true or nil; end
function M.OnTurnEnd()
  if not mission then return; end
  mission.ready=false;
  if mission.pending then mission.pending.clearRequested=true; ClearOrder(mission.owner,mission.pending.id); end
  Report("本回合结束；行军目标保留，下回合自动继续");
end
function M.OnTurnBegin()
  if mission and mission.lastBegin~=Game.GetCurrentGameTurn() then
    mission.lastBegin=Game.GetCurrentGameTurn(); mission.ready=true; mission.delay=0.75; mission.turn=nil;
  end
end
function M.Start(plan,report,preview)
  if not plan or plan.error or #plan.goals==0 or plan.owner~=Game.GetLocalPlayer()
      or plan.turn~=Game.GetCurrentGameTurn() or not Players[plan.owner]:IsTurnActive() then return false; end
  M.Cancel("new_mission");
  mission={owner=plan.owner,target=plan.target,tasks={},report=report,preview=preview,ready=true,delay=.2,
    arrived=0,released=0,elapsed=0,orders={},index=1,lastBegin=plan.turn};
  for _,g in ipairs(plan.goals) do
    local u=Find(plan.owner,g.id);
    if u and not Supported(u) then
      mission.tasks[g.id]={id=g.id,goal=g.goal,class=g.class,expected=Position(u),blocked=0,kind=u:GetType(),lastIssued=-1};
      ClearOrder(plan.owner,g.id);
    end
  end
  Report("行军目标已保存；以后回合自动继续，停止按钮可取消");
  print("[GC][MARCH_START] target="..plan.target.." units="..Count()); M.Persist();
  return true;
end
local function BuildTurn()
  local b=mission; local goals={}; local completed={};
  for id,g in pairs(b.tasks) do
    local u=Find(b.owner,id);
    if not u or Supported(u) or Info(u).FormationClass~=g.class then completed[#completed+1]={id=id,release=true};
    elseif Position(u)~=g.expected then completed[#completed+1]={id=id,release=true};
    elseif Position(u)==g.goal then completed[#completed+1]={id=id};
    elseif g.lastIssued~=Game.GetCurrentGameTurn() then goals[#goals+1]=g; end
  end
  for _,c in ipairs(completed) do
    if c.release then M.Release(b.owner,c.id,"位置或单位状态已改变");
    else b.tasks[c.id]=nil; b.arrived=b.arrived+1; print("[GC][MARCH_ARRIVED] unit="..c.id); end
  end
  table.sort(goals,function(a,c) return a.id<c.id; end);
  b.orders,b.waiting=M.Steps(goals,b.owner); b.index=1; b.turn=Game.GetCurrentGameTurn(); b.waitChecked={};
  for _,item in ipairs(b.waiting) do
    local g=b.tasks[item.id]; local u=g and Find(b.owner,item.id);
    if g and u and u:GetMovesRemaining()>0 and not u:HasMovedIntoZOC() then
      g.blocked=g.blocked+1;
      if g.blocked>=3 then M.Release(b.owner,item.id,"连续三回合路径受阻，请重新指定目标"); end
    end
    print("[GC][MARCH_WAIT] unit="..item.id.." reason="..item.reason);
  end
  if b.preview then b.preview({target=b.target,orders=b.orders}); end
  Report("行军中：剩余 "..Count().."；本回合可移动 "..#b.orders.."；到达 "..b.arrived);
  print("[GC][MARCH_TURN] turn="..b.turn.." remaining="..Count().." steps="..#b.orders);
end
local function UpdateMission(delta)
  local b=mission; if not b then return; end
  if Game.GetLocalPlayer()~=b.owner then M.Cancel("player_changed"); return; end
  if not b.ready or not Players[b.owner]:IsTurnActive() or next(paused) then return; end
  b.delay=math.max(0,b.delay-delta); if b.delay>0 then return; end
  b.elapsed=b.elapsed+delta; if b.elapsed<0.15 then return; end; b.elapsed=0;
  if b.pending then
    local p=b.pending; local u=Find(b.owner,p.id);
    if not u then M.Release(b.owner,p.id,"单位已消失"); return; end
    if not UI.IsGameCoreBusy() then
      if Position(u)==p.plot or p.cleared or (p.ended and not p.clearRequested) then
        local g=b.tasks[p.id];
        if g then
          local moved=Position(u)~=g.expected;
          g.expected=Position(u); if moved then g.blocked=0; else g.blocked=g.blocked+1; end
          if Position(u)==g.goal then b.tasks[p.id]=nil; b.arrived=b.arrived+1; print("[GC][MARCH_ARRIVED] unit="..p.id);
          elseif g.blocked>=3 then M.Release(b.owner,p.id,"多次下令未能前进，请重新指定目标"); end
        end
        print("[GC][MARCH_STEP_DONE] unit="..p.id.." plot="..Position(u)); b.pending=nil;
      elseif u:GetMovesRemaining()<=0 or u:HasMovedIntoZOC() then
        if not p.clearRequested then p.clearRequested=true; ClearOrder(b.owner,p.id); end
      end
    end
    if b.pending then
      if UI.GetElapsedTime()-p.since>20 then Report("行军结果无法确认，已停止"); M.Cancel("unconfirmed"); end
      return;
    end
  end
  if UI.IsGameCoreBusy() then return; end
  if b.turn~=Game.GetCurrentGameTurn() then BuildTurn(); end
  if Count()==0 then
    b.report("行军结束：到达 "..b.arrived.."；退出 "..b.released.."。单位可重新下令");
    print("[GC][MARCH_COMPLETE] arrived="..b.arrived.." released="..b.released); mission=nil; return;
  end
  local order=b.orders[b.index];
  if not order then
    b.waitChecked=b.waitChecked or {};
    local ids={}; for id in pairs(b.tasks) do ids[#ids+1]=id; end; table.sort(ids);
    for _,id in ipairs(ids) do
      if not b.waitChecked[id] then
        b.waitChecked[id]=true;
        local g=b.tasks[id]; local unit=Find(b.owner,id);
        if unit and not Supported(unit) and Position(unit)==g.expected and Position(unit)~=g.goal and unit:GetMovesRemaining()>0 then
          local candidates=Candidates(unit,g.goal);
          if #candidates==0 then M.WaitForNextTurn(unit,"march_no_legal_step"); end
        end
        return; -- At most one final path check/skip request per scheduler tick.
      end
    end
    return;
  end
  b.index=b.index+1;
  local g=b.tasks[order.id]; if not g then return; end
  local u=Find(b.owner,order.id);
  if not u or Position(u)~=g.expected then M.Release(b.owner,order.id,"单位已被接管"); return; end
  local valid,reason=M.ValidateStep(u,Map.GetPlotByIndex(order.plot));
  if not valid then print("[GC][MARCH_SKIP] unit="..order.id.." reason="..tostring(reason)); return; end
  b.pending={id=order.id,plot=order.plot,since=UI.GetElapsedTime(),expectAdded=true};
  g.lastIssued=Game.GetCurrentGameTurn(); M.Persist();
  UnitManager.RequestOperation(u,UnitOperationTypes.MOVE_TO,M.Parameters(Map.GetPlotByIndex(order.plot)));
  print("[GC][MARCH_REQUEST] unit="..order.id.." step="..order.plot.." final="..g.goal);
end

function M.Update(delta)
  local hadMission=mission~=nil;
  UpdateMission(delta);
  if hadMission and (not mission or (mission.delay==0 and mission.elapsed==0)) then M.Persist(); end
end
