local A=GC_Attack; local T=GC_Auto; local P=GC_Pursuit; local M=GC_March;
local s;
local function Reset()
  T.SetEnabled(false); P.Cancel("reset"); M.Cancel("reset"); A.Cancel("reset");
  s={time=0,units={},requests={},clears={},turn=1,war=true,visible=true,busy=false};
  Game={GetLocalPlayer=function() return 0; end,GetCurrentGameTurn=function() return s.turn; end};
  UI={GetElapsedTime=function() return s.time; end,IsGameCoreBusy=function() return s.busy; end};
  GameInfo={Units={
    [1]={Domain="DOMAIN_LAND",Combat=20,FormationClass="FORMATION_CLASS_LAND_COMBAT"},[2]={Domain="DOMAIN_LAND",Combat=10,RangedCombat=25,FormationClass="FORMATION_CLASS_LAND_COMBAT"},
    [3]={Domain="DOMAIN_LAND",Combat=0,FormationClass="FORMATION_CLASS_CIVILIAN"},[4]={Domain="DOMAIN_AIR",Combat=80,RangedCombat=100,FormationClass="AIR"}}};
  Players={};
  for p=0,2 do local owner=p;
    Players[p]={IsTurnActive=function() return true; end,
      GetDiplomacy=function() return {IsAtWarWith=function(_,other) return s.war and other==1; end}; end,
      GetUnits=function() return {FindID=function(_,id) local u=s.units[id]; return u and u.owner==owner and u or nil; end, Members=function() local own={}; for id,u in pairs(s.units) do if u.owner==owner then own[id]=u; end; end; return pairs(own); end}; end};
  end
  PlayersVisibility={[0]={IsVisible=function() return s.visible; end,IsUnitVisible=function(_,u) return not u.invisible; end}};
  Map={GetPlotByIndex=function(id) return {GetIndex=function() return id; end,GetX=function() return id; end,GetY=function() return 0; end,
    IsCity=function() return s.city; end,IsWater=function() return false; end,IsImpassable=function() return s.blocked==id; end,
    GetOwner=function() return s.territory or -1; end}; end,
    GetPlotDistance=function(x,y,a,b) return math.abs(x-a); end};
  MapLayers={ANY=0};
  Units={GetUnitsInPlotLayerID=function(x,y)
    local r={}; for _,u in pairs(s.units) do if u.x==x and not u.dead then r[#r+1]=u; end; end; return r;
  end};
  UnitOperationTypes={MOVE_TO=1,RANGE_ATTACK=2,AIR_ATTACK=3,PARAM_X="x",PARAM_Y="y",PARAM_MODIFIERS="mod"};
  UnitOperationMoveModifiers={NONE=0,ATTACK=1}; UnitCommandTypes={CANCEL=1};
  CombatManager={IsAttackChangeWarState=function() return s.newWar and {2} or {}; end};
  UnitManager={CanStartOperation=function(u,op,unused,args)
      if u.reject then return false; end
      if op==UnitOperationTypes.RANGE_ATTACK and s.enforceRange then return math.abs(u.x-args.x)<=u:GetRange() and not u.cannotShoot; end
      return true;
    end,
    GetReachableMovement=function(u) local r={}; for x=math.max(0,u.x-u.moves),math.min(10,u.x+u.moves) do r[#r+1]=x; end; return r; end,
    GetMoveToPathEx=function(u,id)
      local p={plots={},turns={}}; local d=id>=u.x and 1 or -1;
      for x=u.x,id,d do p.plots[#p.plots+1]=x; p.turns[#p.turns+1]=math.max(1,math.ceil((math.abs(x-u.x)+2-u.moves)/2)); end
      return p;
    end,
    RequestOperation=function(u,op,args) s.requests[#s.requests+1]={id=u.id,op=op,args=args}; end,
    CanStartCommand=function() return true; end,RequestCommand=function(u)
      s.clears[#s.clears+1]=u.id; if not s.delayClear then A.OnCleared(0,u.id); end
    end};
end
local function Unit(id,owner,kind,x)
  local u={id=id,owner=owner,kind=kind,x=x,attacks=1,moves=2,formation=1};
  function u:GetID() return self.id; end; function u:GetOwner() return self.owner; end;
  function u:GetType() return self.kind; end; function u:GetX() return self.x; end; function u:GetY() return 0; end;
  function u:GetAttacksRemaining() return self.attacks; end; function u:GetMovesRemaining() return self.moves; end;
  function u:GetFormationUnitCount() return self.formation; end; function u:GetComponentID() return self.id; end;
  function u:GetRange() return self.range or (self.kind==2 and 2 or 1); end; function u:HasMovedIntoZOC() return self.zoc; end;
  function u:IsDelayedDeath() return self.dead; end;
  function u:GetFortifyTurns() return self.fortify or 0; end;
  s.units[id]=u; return u;
end
local function Tick(t) s.time=s.time+(t or .2); A.Update(t or .2); end;
local function Plan(ids)
  Unit(99,1,1,5); return A.Plan(ids,assert(A.Target(5)));
end
local function Start(p) assert(A.Start(p,function(msg) s.lastReport=msg; end)); end;
local function FinishMove()
  local r=s.requests[#s.requests]; local u=s.units[r.id];
  u.moves=math.max(0,u.moves-math.abs(u.x-r.args.x)); u.x=r.args.x; A.OnEnded(0,u.id,r.op); Tick();
end
local count=0;
local function Test(name,fn)
  Reset();
  local byIndex=Map.GetPlotByIndex;
  Map.GetPlotByIndex=function(id) if id<0 or id>10 then return nil; end; return byIndex(id); end;
  Map.GetPlot=function(x) return Map.GetPlotByIndex(x); end;
  Map.GetAdjacentPlot=function(x,y,d) if d==0 then return Map.GetPlotByIndex(x-1); elseif d==1 then return Map.GetPlotByIndex(x+1); end; end;
  ActivityTypes={ACTIVITY_AWAKE=0,ACTIVITY_SLEEP=1}; InterfaceModeTypes={SELECTION=1};
  UnitManager.GetActivityType=function(u) return u.activity or 0; end;
  UI.GetInterfaceMode=function() return 1; end;
  UI.GetHeadSelectedUnit=function() return s.head and s.units[s.head]; end;
  CombatTypes={MELEE=1,RANGED=2,BOMBARD=3};
  CombatResultParameters={ATTACKER="a",DEFENDER="d",COMBAT_STRENGTH="strength",STRENGTH_MODIFIER="bonus",DAMAGE_TO="damage",FINAL_DAMAGE_TO="final",MAX_HIT_POINTS="max"};
  CombatManager.SimulateAttackInto=function()
    if s.badForecast then return nil; end
    return {a={strength=30,bonus=0,damage=30,final=s.lethal and 100 or 30,max=100},
      d={strength=s.strong and 60 or 30,bonus=0,damage=s.strong and 10 or 30,final=30,max=100}};
  end;
  UnitOperationMoveModifiers.MOVE_IGNORE_UNEXPLORED_DESTINATION=2;
  M.SetPaused("test",false); T.Initialize(function(id) return s.selected==id; end,function(msg) s.lastReport=msg; end);
  fn(); count=count+1; print("PASS tactics "..name);
end;
local function AutoTick(delta)
  local dt=delta or .5; s.time=s.time+dt; T.Update(dt); A.Update(.2);
end
local function Enable() T.SetEnabled(true); AutoTick(2.5); end


Test("disabled automation never commands",function()
  Unit(1,0,1,4); Unit(99,1,1,5); AutoTick(5); assert(#s.requests==0);
end);
Test("near-even forecast attacks once per turn",function()
  Unit(1,0,1,4); Unit(99,1,1,5); Enable(); assert(#s.requests==1 and s.requests[1].args.mod==1);
  s.units[1].attacks=0; AutoTick(); s.units[1].attacks=1; AutoTick(); AutoTick(); assert(#s.requests==1);
end);
Test("clear disadvantage retreats instead of attacking",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.strong=true; Enable();
  assert(#s.requests==1 and s.requests[1].args.mod==0 and s.requests[1].args.x<4);
end);
Test("lethal predicted damage forbids an even-strength attack",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.lethal=true; Enable();
  assert(#s.requests==1 and s.requests[1].args.mod==0);
end);
Test("missing forecast never guesses",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.badForecast=true; Enable(); assert(#s.requests==0);
end);
Test("no safer legal retreat means hold",function()
  Unit(1,0,1,0); Unit(99,1,1,1); s.strong=true; Enable(); assert(#s.requests==0);
end);
Test("selected and sleeping units retain player control",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.selected=1; Enable(); assert(#s.requests==0);
  s.selected=nil; s.units[1].activity=1; AutoTick(); assert(#s.requests==0);
  s.units[1].activity=0; s.head=1; AutoTick(); assert(#s.requests==0);
end);
Test("native manual operation excludes unit for rest of turn",function()
  Unit(1,0,1,4); Unit(99,1,1,5); T.OnManualOrder(0,1); Enable(); assert(#s.requests==0);
end);
Test("native operation event before scan protects completed manual move",function()
  Unit(1,0,1,4); Unit(99,1,1,5); T.OnOperationAdded(0,1); Enable(); assert(#s.requests==0);
end);
Test("friendly peace and fog are never attacked",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.war=false; Enable(); assert(#s.requests==0);
  s.war=true; s.visible=false; AutoTick(); assert(#s.requests==0);
end);
Test("forecast is rechecked at actual attack request",function()
  Unit(1,0,1,4); Unit(99,1,1,5); T.SetEnabled(true); s.time=3; T.Update(3);
  s.strong=true; A.Update(.2); assert(#s.requests==0 and A.LastStop()=="authorization_changed");
end);
Test("automation never approaches a target that left range",function()
  Unit(1,0,1,4); Unit(99,1,1,5); T.SetEnabled(true); s.time=3; T.Update(3);
  s.units[99].x=7; A.Update(.2); assert(#s.requests==0);
end);
Test("manual takeover cancels pending retreat before replacement",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.strong=true; Enable(); T.OnManualOrder(0,1);
  assert(#s.clears==1); AutoTick(); assert(#s.requests==1);
end);
Test("cohesion limits fast unit to slow reachable frontier plus two tiles",function()
  local slow=Unit(1,0,1,0); local fast=Unit(2,0,1,0); slow.moves=1; fast.moves=4; Unit(99,1,1,8);
  local target=A.Target(8); local plan=A.Plan({[1]=true,[2]=true},target,true);
  assert(plan.cohesionFloor==5 and plan.approaching==2);
  for _,order in ipairs(plan.orders) do assert(order.approach<=3); end
end);
Test("allocated landing slot is used before a greedy alternative",function()
  Unit(1,0,1,0); Unit(2,0,1,1); Unit(99,1,1,5);
  local plan=A.Plan({[1]=true,[2]=true},A.Target(5),true); local first=plan.orders[1];
  Start(plan); Tick(); assert(s.requests[1].args.x==first.approach);
end);
Test("explicit pursuit retains enemy identity across turns",function()
  Unit(1,0,1,0); Unit(99,1,1,5);
  local plan=A.Plan({[1]=true},A.Target(5),true); assert(P.Start(plan,function(msg) s.lastReport=msg; end));
  Tick(); FinishMove(); assert(#s.requests==1); P.Update(1); assert(#s.requests==1);
  s.turn=2; s.units[1].moves=2; s.units[99].x=6; Tick(); P.Update(1); Tick();
  assert(#s.requests==2 and P.HasTask(1));
end);
Test("pursuit stops on loss of vision and never changes victim",function()
  Unit(1,0,1,0); Unit(99,1,1,5); assert(P.Start(A.Plan({[1]=true},A.Target(5),true),function() end));
  s.visible=false; P.Update(1); assert(not P.IsBusy() and #s.requests==0);
end);
Test("manual release and stop cannot restart pursuit",function()
  Unit(1,0,1,0); Unit(99,1,1,5); assert(P.Start(A.Plan({[1]=true},A.Target(5),true),function() end));
  P.Release(0,1); s.turn=2; Tick(); P.Update(1); assert(not P.IsBusy() and #s.requests==0);
end);
Test("automation yields to a continuing group task",function()
  Unit(1,0,1,4); Unit(99,1,1,5); assert(P.Start(A.Plan({[1]=true},A.Target(5),true),function() end));
  T.SetEnabled(true); T.Update(3); assert(#s.requests==0);
end);
Test("front unit vacates tile and initially blocked follower moves same turn",function()
  Unit(1,0,1,0).moves=1; Unit(2,0,1,1); Unit(99,1,1,5);
  local plan=A.Plan({[1]=true,[2]=true},A.Target(5),true);
  assert(#plan.orders==1 and #plan.waiting==1); Start(plan); Tick(); assert(s.requests[1].id==2);
  FinishMove(); assert(#s.requests==2 and s.requests[2].id==1 and s.requests[2].args.x==1);
end);
Test("retreat timeout disables automation and does not retry",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.strong=true; Enable(); assert(#s.requests==1);
  AutoTick(22); assert(not T.IsEnabled()); AutoTick(2); assert(#s.requests==1);
end);
Test("pause prevents new autonomous orders",function()
  Unit(1,0,1,4); Unit(99,1,1,5); M.SetPaused("test",true); Enable(); assert(#s.requests==0);
end);
Test("hidden retreat terrain is never inspected",function()
  Unit(1,0,1,4); Unit(99,1,1,5); s.strong=true;
  PlayersVisibility[0].IsVisible=function(_,x) return x>=4; end; Enable(); assert(#s.requests==0);
end);
Test("exhausted slow unit still limits how far the vanguard advances",function()
  Unit(1,0,1,0).moves=0; Unit(2,0,1,0).moves=4; Unit(99,1,1,8);
  local plan=A.Plan({[1]=true,[2]=true},A.Target(8),true);
  assert(plan.cohesionFloor==6 and #plan.orders==1 and plan.orders[1].approach<=2);
end);
Test("an exhausted combat group can accept an explicit next-turn attack mission",function()
  Unit(1,0,1,0).moves=0; Unit(99,1,1,5);
  local plan=A.Plan({[1]=true},A.Target(5),true); assert(#plan.orders==0 and P.CanStart(plan));
  assert(P.Start(plan,function() end)); assert(#s.requests==0);
  s.turn=2; s.units[1].moves=2; P.Update(1); Tick(); assert(#s.requests==1);
end);
Test("pursuit with leftover unusable movement waits without releasing task",function()
  local unit=Unit(1,0,1,0); unit.moves=1; Unit(99,1,1,5);
  UnitManager.GetReachableMovement=function() return {0}; end;
  UnitOperationTypes.SKIP_TURN=4; local skips=0;
  local request=UnitManager.RequestOperation;
  UnitManager.RequestOperation=function(u,op,args)
    if op==4 then skips=skips+1; T.OnOperationAdded(0,u.id); else request(u,op,args); end
  end;
  assert(P.Start(A.Plan({[1]=true},A.Target(5),true),function() end));
  P.Update(1); P.Update(1); assert(skips==1 and P.HasTask(1));
end);
T.SetEnabled(false); P.Cancel("tests_complete"); M.Cancel("tests_complete"); A.Cancel("tests_complete");
print("TACTICS TESTS PASSED: "..count);
