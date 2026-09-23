-- Engine doubles test scheduling and allocation; they do not prove Civ VI API behavior.
local state;
local function Reset()
  GC_Rally.Cancel("test_reset");
  state={time=0,turn=1,active=true,busy=false,units={},plots={},requests={},clears={},messages={}};
  Game={GetLocalPlayer=function() return 0 end,GetCurrentGameTurn=function() return state.turn end};
  UI={IsGameCoreBusy=function() return state.busy end,GetElapsedTime=function() return state.time end};
  GameInfo={Units={
    [1]={Domain="DOMAIN_LAND",FormationClass="FORMATION_CLASS_LAND_COMBAT"},
    [2]={Domain="DOMAIN_LAND",FormationClass="FORMATION_CLASS_CIVILIAN"},
    [3]={Domain="DOMAIN_LAND",FormationClass="FORMATION_CLASS_SUPPORT"}}};
  Players={[0]={IsTurnActive=function() return state.active end,GetUnits=function()
    return {FindID=function(_,id) return state.units[id] end} end}};
  PlayersVisibility={[0]={IsVisible=function(_,x) return not state.plots[x].hidden end}};
  Map={GetPlotByIndex=function(id) return state.plots[id] end,GetPlot=function(x,y) return state.plots[x] end,
    GetPlotDistance=function(x,y,x2,y2) return math.abs(x-x2) end};
  MapLayers={ANY=0};
  Units={GetUnitsInPlotLayerID=function(x,y)
    local result={}; for _,u in pairs(state.units) do if u.x==x then result[#result+1]=u end end; return result;
  end};
  UnitOperationTypes={PARAM_X="x",PARAM_Y="y",PARAM_MODIFIERS="modifiers",MOVE_TO=1};
  UnitOperationMoveModifiers={NONE=0}; UnitCommandTypes={CANCEL=2};
  UnitManager={GetReachableMovement=function(u) return u.reachable end,
    CanStartOperation=function(u,op,unused,args) return not u.rejected end,
    GetMoveToPathEx=function(u,id) return {plots=u.path or {u.x,id}} end,
    RequestOperation=function(u,op,args) state.requests[#state.requests+1]={id=u.id,plot=args.x,modifiers=args.modifiers}; end,
    CanStartCommand=function() return true end,
    RequestCommand=function(u,cmd)
      state.clears[#state.clears+1]=u.id;
      if not state.delayClear then GC_Rally.OnOperationsCleared(0,u.id); end
    end};
  for i=0,12 do
    local p={id=i,owner=-1};
    function p:GetIndex() return self.id end; function p:GetX() return self.id end; function p:GetY() return 0 end;
    function p:GetOwner() return self.owner end; function p:IsWater() return self.water end;
    function p:IsImpassable() return self.blocked end;
    state.plots[i]=p;
  end
end
local function Unit(id,kind,x,reachable,moves)
  local u={id=id,kind=kind,x=x,reachable=reachable,moves=moves or 2,formation=1,owner=0};
  function u:GetType() return self.kind end; function u:GetOwner() return self.owner end;
  function u:GetID() return self.id end; function u:GetX() return self.x end; function u:GetY() return 0 end;
  function u:GetMovesRemaining() return self.moves end; function u:GetFormationUnitCount() return self.formation end;
  function u:HasMovedIntoZOC() return self.zoc end;
  state.units[id]=u; return u;
end
local function Tick(seconds) state.time=state.time+(seconds or .2); GC_Rally.Update(seconds or .2); end
local function Start(plan) assert(GC_Rally.Start(plan,function(msg) state.messages[#state.messages+1]=msg end)); end
local passed=0;
local function Test(name,fn) Reset(); fn(); passed=passed+1; print("PASS "..name); end

Test("slot matching regressions",function() GC_Rally.SelfTest(); end);
Test("same class distinct destinations",function()
  Unit(1,1,0,{2,3}); Unit(2,1,1,{2,3});
  local p=GC_Rally.Plan({[1]=true,[2]=true},2);
  assert(#p.orders==2 and p.orders[1].plot~=p.orders[2].plot);
  assert(#state.requests==0,"preview must not issue commands");
end);
Test("civilian and combat share destination",function()
  Unit(1,1,0,{2}); Unit(2,2,1,{2});
  local p=GC_Rally.Plan({[1]=true,[2]=true},2);
  assert(#p.orders==2 and p.orders[1].plot==2 and p.orders[2].plot==2);
end);
Test("terrain reachability and zero moves handled independently",function()
  Unit(1,1,0,{5}); Unit(2,1,1,{2}); Unit(3,2,3,{5},0);
  local p=GC_Rally.Plan({[1]=true,[2]=true,[3]=true},5);
  assert(#p.orders==2 and #p.waiting==1 and p.waiting[1].id==3);
  assert(p.orders[1].plot==5 and p.orders[2].plot==2);
end);
Test("linked escorts preserved",function()
  local u=Unit(1,1,0,{2}); u.formation=2;
  local p=GC_Rally.Plan({[1]=true},2); assert(#p.orders==0 and #p.waiting==1);
end);
Test("foreign or hidden route refused",function()
  local u=Unit(1,1,0,{3}); u.path={0,2,3}; state.plots[2].hidden=true;
  assert(not GC_Rally.Validate(u,state.plots[3])); state.plots[2].hidden=false; state.plots[2].owner=1;
  assert(not GC_Rally.Validate(u,state.plots[3]));
end);
Test("serial queue and no duplicate requests",function()
  local u=Unit(1,1,0,{2,3}); local v=Unit(2,1,1,{2,3});
  local p=GC_Rally.Plan({[1]=true,[2]=true},2); Start(p); Tick(); Tick();
  assert(#state.requests==1); u.x=p.orders[1].plot; Tick(); assert(#state.requests==2);
  v.x=p.orders[2].plot; Tick(); Tick(); assert(#state.requests==2);
  assert(state.messages[#state.messages]:find("到达 2"));
  assert(state.requests[1].modifiers==0);
end);
Test("exhausted in transit clears route and continues",function()
  local u=Unit(1,1,0,{5}); Unit(2,1,1,{6});
  local p=GC_Rally.Plan({[1]=true,[2]=true},5); Start(p); Tick();
  u.x=3; u.moves=0; Tick();
  assert(#state.clears==1 and #state.requests==2);
end);
Test("clear acknowledgement required before next command",function()
  local u=Unit(1,1,0,{5}); Unit(2,1,1,{6}); state.delayClear=true;
  Start(GC_Rally.Plan({[1]=true,[2]=true},5)); Tick(); u.moves=0; Tick(); Tick();
  assert(#state.requests==1 and #state.clears==1);
  GC_Rally.OnOperationsCleared(0,1); Tick(); assert(#state.requests==2);
end);
Test("changed occupancy revalidated",function()
  Unit(1,1,0,{3}); local p=GC_Rally.Plan({[1]=true},3); Unit(2,1,3,{});
  Start(p); Tick(); Tick(); assert(#state.requests==0);
end);
Test("turn change stops unsent requests",function()
  Unit(1,1,0,{3}); Start(GC_Rally.Plan({[1]=true},3)); state.turn=2; Tick(); assert(#state.requests==0);
end);
Test("cancel clears pending route and prevents next request",function()
  Unit(1,1,0,{4}); Unit(2,1,1,{5}); Start(GC_Rally.Plan({[1]=true,[2]=true},4)); Tick();
  GC_Rally.Cancel("escape"); Tick(); assert(#state.requests==1 and #state.clears==1);
end);
Test("unknown outcome times out without resending",function()
  Unit(1,1,0,{4}); Start(GC_Rally.Plan({[1]=true},4)); Tick(); Tick(16); Tick();
  assert(#state.requests==1 and #state.clears==1);
end);
Test("invalid target and empty selection explain failure",function()
  assert(GC_Rally.Plan({},2).error); assert(GC_Rally.Plan({[1]=true},-1).error);
end);
Test("friendly occupied centre assigns free neighbours",function()
  Unit(1,1,0,{4,5}); Unit(2,1,4,{},0);
  local p=GC_Rally.Plan({[1]=true},4);
  assert(not p.error and #p.orders==1 and p.orders[1].plot==5);
end);
Test("occupied centre never becomes an illegal landing",function()
  Unit(1,1,0,{4,5}); local other=Unit(2,1,4,{},0); other.owner=1;
  local p=GC_Rally.Plan({[1]=true},4);
  assert(not p.error and #p.orders==1 and p.orders[1].plot==5);
  assert(not GC_Rally.Validate(state.units[1],state.plots[4]));
end);
Test("foreign unit on path still blocks movement",function()
  local u=Unit(1,1,0,{5}); u.path={0,4,5}; Unit(2,1,4,{},0).owner=1;
  local p=GC_Rally.Plan({[1]=true},4);
  assert(not p.error and #p.orders==0);
end);
print("RALLY TESTS PASSED: "..passed);
