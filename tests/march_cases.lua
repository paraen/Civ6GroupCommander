-- Engine doubles verify cross-turn scheduling and strict fog-read boundaries.
local M=GC_March;
local s;
local function Reset()
  M.Cancel("test_reset"); M.Shutdown(); M.SetPaused("test",false);
  s={turn=1,active=true,time=0,units={},plots={},requests={},messages={},busy=false,reads=0};
  Game={GetLocalPlayer=function() return s.owner or 0; end,GetCurrentGameTurn=function() return s.turn; end};
  UI={GetElapsedTime=function() return s.time; end,IsGameCoreBusy=function() return s.busy; end};
  GameInfo={Units={[1]={Domain="DOMAIN_LAND",FormationClass="FORMATION_CLASS_LAND_COMBAT"},
    [2]={Domain="DOMAIN_LAND",FormationClass="FORMATION_CLASS_CIVILIAN"},
    [3]={Domain="DOMAIN_SEA",FormationClass="FORMATION_CLASS_NAVAL"}}};
  Players={[0]={IsTurnActive=function() return s.active; end,GetUnits=function() return {FindID=function(_,id) return s.units[id]; end}; end}};
  PlayersVisibility={[0]={IsVisible=function(_,x) return not s.plots[x].hidden; end,IsUnitVisible=function(_,u) return not u.invisible; end}};
  Map={GetPlotByIndex=function(id) return s.plots[id]; end,GetPlot=function(x) return s.plots[x]; end,
    GetPlotDistance=function(x,y,a,b) return math.abs(x-a); end,
    GetAdjacentPlot=function(x,y,d) if d==0 then return s.plots[x-1]; elseif d==1 then return s.plots[x+1]; end; end};
  MapLayers={ANY=0};
  for i=0,24 do
    local p={id=i,owner=-1};
    function p:GetIndex() return self.id; end; function p:GetX() return self.id; end; function p:GetY() return 0; end;
    function p:GetOwner() assert(not self.hidden,"hidden owner read"); return self.owner; end;
    function p:IsWater() assert(not self.hidden,"hidden terrain read"); return self.water; end;
    function p:IsImpassable() assert(not self.hidden,"hidden terrain read"); return self.blocked; end;
    s.plots[i]=p;
  end
  Units={GetUnitsInPlotLayerID=function(x)
    assert(not s.plots[x].hidden,"hidden occupants read"); s.reads=s.reads+1;
    local r={}; for _,u in pairs(s.units) do if u.x==x then r[#r+1]=u; end; end; return r;
  end};
  UnitOperationTypes={MOVE_TO=1,PARAM_X="x",PARAM_Y="y",PARAM_MODIFIERS="mod"};
  UnitOperationMoveModifiers={NONE=0,ATTACK=1,MOVE_IGNORE_UNEXPLORED_DESTINATION=2}; UnitCommandTypes={CANCEL=3};
  UnitManager={GetReachableMovement=function(u)
    local span=math.floor(u.moves/(u.cost or 1));
    local ids={}; for x=math.max(0,u.x-span),math.min(24,u.x+span) do ids[#ids+1]=x; end; return ids;
  end,GetMoveToPathEx=function(u,id)
    if u.noPath then return {plots={},turns={}}; end
    local path={plots={},turns={}}; local direction=id>=u.x and 1 or -1;
    for x=u.x,id,direction do
      path.plots[#path.plots+1]=x;
      path.turns[#path.turns+1]=math.max(1,math.ceil((math.abs(x-u.x)*(u.cost or 1)+2-u.moves)/2));
    end
    return path;
  end,CanStartOperation=function(u) return not u.reject and u.moves>0; end,
  CanStartCommand=function(u) return u.hasOrder; end,
  RequestCommand=function(u,cmd)
    u.hasOrder=false; M.OnCommandStarted(0,u.id,cmd);
    if not s.delayClear then M.OnCleared(0,u.id); end
  end,RequestOperation=function(u,op,args)
    u.hasOrder=true; s.requests[#s.requests+1]={id=u.id,plot=args.x,mod=args.mod}; M.OnOperationAdded(0,u.id,op);
  end};
end
local function Unit(id,x,kind,moves)
  local u={id=id,x=x,kind=kind or 1,moves=moves or 2,owner=0,formation=1};
  function u:GetType() return self.kind; end; function u:GetID() return self.id; end;
  function u:GetOwner() return self.owner; end; function u:GetX() return self.x; end; function u:GetY() return 0; end;
  function u:GetMovesRemaining() return self.moves; end; function u:HasMovedIntoZOC() return self.zoc; end;
  function u:GetFormationUnitCount() return self.formation; end;
  s.units[id]=u; return u;
end
local function Tick(t) s.time=s.time+(t or .3); M.Update(t or .3); end;
local function Start(plan) assert(M.Start(plan,function(msg) s.messages[#s.messages+1]=msg; end)); end;
local function Complete()
  local r=s.requests[#s.requests]; local u=s.units[r.id];
  u.moves=math.max(0,u.moves-math.abs(r.plot-u.x)); u.x=r.plot; u.hasOrder=false;
  M.OnEnded(0,u.id,UnitOperationTypes.MOVE_TO); Tick();
end
local function NextTurn()
  M.OnTurnEnd(); s.active=false; Tick(3); s.turn=s.turn+1;
  for _,u in pairs(s.units) do u.moves=2; u.zoc=false; end
  s.active=true; M.OnTurnBegin(); Tick(1);
end
local count=0;
local function Test(name,fn) Reset(); fn(); count=count+1; print("PASS march "..name); end;
Test("far target remains final while intermediate steps continue automatically",function()
  Unit(1,0); local p=M.Plan({[1]=true},6);
  assert(p.goals[1].goal==6 and p.orders[1].plot==2 and #s.requests==0);
  Start(p); Tick(); assert(s.requests[1].plot==2); Complete();
  NextTurn(); assert(s.requests[2].plot==4); Complete(); NextTurn(); assert(s.requests[3].plot==6); Complete();
  assert(s.messages[#s.messages]:find("到达 1",1,true)); NextTurn(); assert(#s.requests==3);
end);
Test("unexplored final target does not read hidden terrain or occupants",function()
  Unit(1,0); for x=1,24 do s.plots[x].hidden=true; end
  local p=M.Plan({[1]=true},10); assert(not p.error and p.goals[1].goal==10 and #p.orders==1);
  Start(p); Tick(); assert(s.requests[1].mod==2 and s.requests[1].plot==2);
end);
Test("same-class final and intermediate slots remain distinct",function()
  Unit(1,0); Unit(2,1); local p=M.Plan({[1]=true,[2]=true},10);
  assert(#p.goals==2 and p.goals[1].goal~=p.goals[2].goal);
  assert(#p.orders==2 and p.orders[1].plot~=p.orders[2].plot);
end);
Test("civilian and combat may share the final slot",function()
  Unit(1,0); Unit(2,1,2); local p=M.Plan({[1]=true,[2]=true},8);
  assert(p.goals[1].goal==8 and p.goals[2].goal==8);
end);
Test("zero movement accepts mission and resumes next turn",function()
  Unit(1,0,1,0); local p=M.Plan({[1]=true},8); assert(#p.goals==1 and #p.orders==0);
  Start(p); Tick(); assert(#s.requests==0); NextTurn(); assert(#s.requests==1);
end);
Test("stop prevents next-turn resumption",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); M.Cancel("stop"); NextTurn(); assert(#s.requests==1);
end);
Test("mode suspension retains mission without issuing orders",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); M.SetPaused("test",true); Tick(); assert(#s.requests==0);
  M.SetPaused("test",false); Tick(); assert(#s.requests==1);
end);
Test("newly visible enemy blocks path without auto attack",function()
  Unit(1,0); for x=1,24 do s.plots[x].hidden=true; end
  local p=M.Plan({[1]=true},8); s.plots[1].hidden=false; Unit(99,1).owner=1;
  Start(p); Tick(); assert(#s.requests==0);
end);
Test("invisible enemy content is not used to plan",function()
  Unit(1,0); local e=Unit(99,2); e.owner=1; e.invisible=true;
  local p=M.Plan({[1]=true},8); assert(#p.orders==1 and p.orders[1].plot==2);
end);
Test("manual replacement order relinquishes ownership",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); M.OnManualOrder(0,1); M.OnOperationAdded(0,1,UnitOperationTypes.MOVE_TO);
  NextTurn(); assert(#s.requests==1 and s.units[1].hasOrder);
end);
Test("manual fortify or cancel stops future automatic orders",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); Complete(); M.OnCommandStarted(0,1,999);
  NextTurn(); assert(#s.requests==1);
end);
Test("turn end clears in-flight route then retains final destination",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); s.units[1].x=1;
  NextTurn(); assert(#s.requests==2 and s.requests[2].plot==3);
end);
Test("engine rejection does not loop within one turn",function()
  Unit(1,0).reject=true; Start(M.Plan({[1]=true},8)); for i=1,10 do Tick(); end; assert(#s.requests==0);
end);
Test("timeout halts uncertain operation without retry",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); Tick(21); NextTurn(); assert(#s.requests==1);
end);
Test("unit removed while pending does not deadlock other units",function()
  Unit(1,0); Unit(2,1,2); Start(M.Plan({[1]=true,[2]=true},8)); Tick(); s.units[1]=nil; M.Release(0,1,"removed");
  Tick(); assert(#s.requests==2 and s.requests[2].id==2);
end);
Test("existing native route replaced when new mission begins",function()
  Unit(1,0).hasOrder=true; Start(M.Plan({[1]=true},8)); assert(not s.units[1].hasOrder); Tick(); assert(#s.requests==1);
end);
Test("foreign territory not used as a visible step",function()
  Unit(1,0); s.plots[1].owner=1; Start(M.Plan({[1]=true},8)); Tick(); assert(#s.requests==0);
end);
Test("unsupported units do not acquire a land mission",function()
  Unit(1,0,3); local p=M.Plan({[1]=true},8); assert(#p.goals==0 and #p.waiting==1);
end);
Test("changed player does not receive another player's requests",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); s.owner=1; Tick(); assert(#s.requests==0);
end);
Test("duplicate turn begin never schedules the same turn twice",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); Complete(); M.OnTurnBegin(); Tick(1); assert(#s.requests==1);
  NextTurn(); assert(#s.requests==2); Complete(); M.OnTurnBegin(); Tick(1); assert(#s.requests==2);
end);
Test("blocked mission eventually returns control",function()
  Unit(1,0).noPath=true; Start(M.Plan({[1]=true},8)); Tick(); NextTurn(); NextTurn();
  assert(s.messages[#s.messages]:find("退出 1",1,true));
end);
Test("native costs determine individual intermediate stops",function()
  Unit(1,0).cost=2; Unit(2,0,2); local p=M.Plan({[1]=true,[2]=true},10);
  assert(p.orders[1].plot==1 and p.orders[2].plot==2);
end);
Test("operation ending without progress eventually relinquishes unit",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick();
  for i=1,3 do
    s.units[1].hasOrder=false; M.OnEnded(0,1,UnitOperationTypes.MOVE_TO); Tick();
    if i<3 then NextTurn(); end
  end
  assert(s.messages[#s.messages]:find("退出 1",1,true));
end);
Test("native operation notifications cannot cancel our own movement",function()
  Unit(1,0); Start(M.Plan({[1]=true},8)); Tick();
  M.OnOperationAdded(0,1,1477390184); M.OnOperationAdded(0,1,UnitOperationTypes.MOVE_TO);
  Complete(); NextTurn(); assert(#s.requests==2);
end);
local function Storage()
  local saved;
  PlayerOperations={EXECUTE_SCRIPT=99};
  UI.RequestPlayerOperation=function(owner,op,args)
    assert(owner==0 and op==99 and args.OnStart=="GC_SaveMarchV2"); saved=args.action=="clear" and "" or args.value;
  end;
  Players[0].GetProperty=function(_,key) assert(key=="GC_MarchV2"); return saved; end;
  return function(value) if value then saved=value; end; return saved; end;
end
local function Restore()
  return M.Restore(function(msg) s.messages[#s.messages+1]=msg; end);
end
Test("save reload retains target and does not duplicate a completed same-turn step",function()
  local saved=Storage(); Unit(1,0); Start(M.Plan({[1]=true},8)); Tick(); Complete();
  local value=saved(); assert(value and value~=""); M.Shutdown(); assert(saved()==value);
  assert(Restore()); Tick(1); assert(#s.requests==1);
  NextTurn(); assert(#s.requests==2 and s.requests[2].plot==4);
end);
Test("stopped mission stays stopped after reload",function()
  local saved=Storage(); Unit(1,0); Start(M.Plan({[1]=true},8)); M.Cancel("stop_button");
  assert(saved()==""); M.Shutdown(); assert(not Restore()); Tick(1); assert(#s.requests==0);
end);
Test("in-flight saved command is not replayed",function()
  Storage(); Unit(1,0); Start(M.Plan({[1]=true},8)); Tick();
  M.Shutdown(); assert(Restore()); Tick(1); NextTurn(); assert(#s.requests==1);
end);
Test("changed identity or position is not reclaimed on load",function()
  Storage(); local u=Unit(1,0); Start(M.Plan({[1]=true},8));
  M.Shutdown(); u.x=1; assert(Restore()); Tick(1); assert(#s.requests==0);
end);
Test("wrong-player and malformed saves cannot issue commands",function()
  local saved=Storage(); Unit(1,0); saved("2,1,8,1,0,0,-1;1,8,0,0,1,-1");
  assert(not Restore()); M.Shutdown(); saved("not a mission"); assert(not Restore()); Tick(1); assert(#s.requests==0);
end);
Test("save made before first step resumes on load",function()
  Storage(); Unit(1,0); Start(M.Plan({[1]=true},8)); M.Shutdown();
  assert(Restore()); Tick(1); assert(#s.requests==1 and s.requests[1].plot==2);
end);
local function SkipSupport()
  s.skips={}; UnitOperationTypes.SKIP_TURN=4; ActivityTypes={ACTIVITY_AWAKE=0};
  UnitManager.GetActivityType=function() return 0; end;
  local move=UnitManager.RequestOperation;
  UnitManager.RequestOperation=function(unit,op,args)
    if op==4 then s.skips[#s.skips+1]=unit.id; M.OnOperationAdded(0,unit.id,op); M.OnEnded(0,unit.id,op);
    else move(unit,op,args); end
  end;
end
Test("terrain leaves one unusable movement point: skip only this turn and resume",function()
  SkipSupport(); local unit=Unit(1,0,1,3); unit.cost=2;
  Start(M.Plan({[1]=true},8)); Tick(); assert(s.requests[1].plot==1);
  unit.moves=2; Complete(); Tick(); Tick();
  assert(unit.moves==1 and #s.skips==1 and M.HasTask(1));
  NextTurn(); assert(#s.requests==2 and s.requests[2].plot==2);
end);
Test("arrived unit is returned to player rather than auto skipped",function()
  SkipSupport(); Unit(1,0); Start(M.Plan({[1]=true},1)); Tick(); Complete(); Tick();
  assert(#s.skips==0 and not M.HasTask(1));
end);
Test("manually released unit is never auto skipped",function()
  SkipSupport(); local unit=Unit(1,0); unit.noPath=true;
  Start(M.Plan({[1]=true},8)); M.OnManualOrder(0,1); Tick(); Tick(); assert(#s.skips==0);
end);
Test("remaining legal progress is not hidden with skip turn",function()
  SkipSupport(); Unit(1,0); Start(M.Plan({[1]=true},8)); Tick();
  Complete(); s.units[1].moves=1; Tick(); assert(#s.skips==0);
end);
Test("skip rejected by engine does not discard ongoing mission",function()
  SkipSupport(); local unit=Unit(1,0); unit.noPath=true;
  local check=UnitManager.CanStartOperation;
  UnitManager.CanStartOperation=function(u,op,...) if op==4 then return false; end; return check(u,op,...); end;
  Start(M.Plan({[1]=true},8)); Tick(); Tick(); assert(#s.skips==0 and M.HasTask(1));
end);
M.Cancel("tests_complete");
print("MARCH TESTS PASSED: "..count);
