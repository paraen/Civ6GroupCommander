-- Explicit group attack orders persist across turns, never switch enemy identity.
GC_Pursuit={}; local P=GC_Pursuit; local mission=nil; local delay=0;
function P.HasTask(id) return mission and mission.selected[id] or false; end
function P.IsBusy() return mission~=nil; end
function P.Cancel(reason)
  if not mission then return; end
  local old=mission; mission=nil; GC_Attack.Cancel(reason);
  old.report("协同进攻停止："..tostring(reason));
  print("[GC][PURSUIT_CANCEL] reason="..tostring(reason));
end
function P.Release(owner,id)
  if mission and mission.owner==owner and mission.selected[id] then
    mission.selected[id]=nil; GC_Attack.OnManualOrder(owner,id);
    print("[GC][PURSUIT_RELEASE] unit="..id);
  end
end
local function CurrentTarget(b)
  if b.owner~=Game.GetLocalPlayer() then return nil; end
  local player=Players[b.target.owner]; local units=player and player:GetUnits();
  local enemy=units and units:FindID(b.target.id); local vis=PlayersVisibility[b.owner];
  if not enemy or enemy:IsDelayedDeath() or not vis or not vis:IsUnitVisible(enemy)
      or not vis:IsVisible(enemy:GetX(),enemy:GetY()) then return nil; end
  local plot=Map.GetPlot(enemy:GetX(),enemy:GetY()); local target=plot and GC_Attack.Target(plot:GetIndex());
  if target and target.id==b.target.id and target.owner==b.target.owner then return target; end
end
local function Positions(b)
  local rows={}; local units=Players[b.owner]:GetUnits();
  for id in pairs(b.selected) do
    local unit=units:FindID(id);
    if not unit then b.selected[id]=nil;
    else rows[#rows+1]=id..":"..unit:GetX()..":"..unit:GetY(); end
  end
  table.sort(rows); return table.concat(rows,";");
end
function P.CanStart(plan)
  if not plan or plan.error or plan.owner~=Game.GetLocalPlayer() or plan.turn~=Game.GetCurrentGameTurn() then return false; end
  if not Players[plan.owner]:IsTurnActive() or not GC_Attack.CheckTarget(plan.target,plan.owner) then return false; end
  if #plan.orders>0 then return true; end
  for _,item in ipairs(plan.waiting) do
    local unit=Players[plan.owner]:GetUnits():FindID(item.id); local info=unit and GameInfo.Units[unit:GetType()];
    if info and info.Domain=="DOMAIN_LAND" and ((info.Combat or 0)>0 or (info.RangedCombat or 0)>0)
        and not unit:IsDelayedDeath() and unit:GetFormationUnitCount()==1 then return true; end
  end
  return false;
end
function P.Start(plan,report,preview)
  if not P.CanStart(plan) then return false; end
  P.Cancel("new_target");
  local selected={}; for _,order in ipairs(plan.orders) do selected[order.id]=true; end
  -- Waiting combatants with no movement this turn still belong to the order.
  for _,item in ipairs(plan.waiting) do
    local unit=Players[plan.owner]:GetUnits():FindID(item.id); local info=unit and GameInfo.Units[unit:GetType()];
    if info and info.Domain=="DOMAIN_LAND" and ((info.Combat or 0)>0 or (info.RangedCombat or 0)>0) and unit:GetFormationUnitCount()==1 then selected[item.id]=true; end
  end
  mission={owner=plan.owner,target=plan.target,selected=selected,report=report,preview=preview,lastTurn=plan.turn,blocked=0};
  mission.positions=Positions(mission); mission.cohesionFloor=plan.cohesionFloor; mission.waitChecked={}; delay=0;
  mission.hadDirect=plan.direct>0;
  if #plan.orders>0 then
    if not GC_Attack.Start(plan,report) then mission=nil; return false; end
  else report("协同进攻已安排：本回合待命，下回合自动重查"); end
  print("[GC][PURSUIT_START] target="..plan.target.owner..":"..plan.target.id); return true;
end
function P.Update(delta)
  local b=mission; if not b then return; end
  if b.owner~=Game.GetLocalPlayer() then P.Cancel("玩家变化"); return; end
  if GC_March.IsPaused() or not Players[b.owner]:IsTurnActive() or UI.IsGameCoreBusy() then delay=0; return; end
  delay=delay+delta; if delay<.75 then return; end; delay=0;
  local target=CurrentTarget(b);
  if not target then P.Cancel("目标死亡、不可见或不再合法"); return; end
  if GC_Attack.IsBusy() then return; end
  local reason=GC_Attack.LastStop();
  if reason=="timeout" or reason=="approach_timeout" or reason=="authorization_changed" then P.Cancel("动作未确认，请重新下令"); return; end
  local turn=Game.GetCurrentGameTurn();
  if b.lastTurn==turn then
    b.waitChecked=b.waitChecked or {};
    local ids={}; for id in pairs(b.selected) do ids[#ids+1]=id; end; table.sort(ids);
    for _,id in ipairs(ids) do
      if not b.waitChecked[id] then
        b.waitChecked[id]=true;
        local unit=Players[b.owner]:GetUnits():FindID(id);
        if unit and unit:GetMovesRemaining()>0 and not GC_Attack.Operation(unit,target) then
          local candidates=GC_Attack.ApproachCandidates(unit,target,b.cohesionFloor);
          if #candidates==0 then GC_March.WaitForNextTurn(unit,"pursuit_no_legal_step"); end
        end
        return;
      end
    end
    return;
  end
  local positions=Positions(b);
  if not next(b.selected) then P.Cancel("没有剩余单位"); return; end
  if positions==b.positions and not b.hadDirect then b.blocked=b.blocked+1; else b.blocked=0; end
  if b.blocked>=3 then P.Cancel("连续三回合未推进，请重新指定目标"); return; end
  b.positions=positions; b.target=target; b.lastTurn=turn;
  local plan=GC_Attack.Plan(b.selected,target,true); b.hadDirect=plan.direct and plan.direct>0; b.cohesionFloor=plan.cohesionFloor; b.waitChecked={};
  if plan.error then P.Cancel(plan.error); return; end
  print("[GC][PURSUIT_TURN] turn="..turn.." direct="..plan.direct.." approach="..plan.approaching);
  if b.preview then
    local orders={}; for _,order in ipairs(plan.orders) do if order.approach then orders[#orders+1]={plot=order.approach}; end; end
    b.preview({target=target.plot,orders=orders});
  end
  if #plan.orders>0 then GC_Attack.Start(plan,b.report);
  else b.report("协同进攻待命：本回合暂无合法行动，下回合重查"); end
end
