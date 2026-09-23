local A=GC_Attack;
local s;
local function Reset()
  A.Cancel("reset");
  s={time=0,units={},requests={},clears={},turn=1,war=true,visible=true,busy=false};
  Game={GetLocalPlayer=function() return 0; end,GetCurrentGameTurn=function() return s.turn; end};
  UI={GetElapsedTime=function() return s.time; end,IsGameCoreBusy=function() return s.busy; end};
  GameInfo={Units={
    [1]={Domain="DOMAIN_LAND",Combat=20,FormationClass="LAND"},[2]={Domain="DOMAIN_LAND",Combat=10,RangedCombat=25,FormationClass="LAND"},
    [3]={Domain="DOMAIN_LAND",Combat=0,FormationClass="CIVILIAN"},[4]={Domain="DOMAIN_AIR",Combat=80,RangedCombat=100,FormationClass="AIR"}}};
  Players={};
  for p=0,2 do local owner=p;
    Players[p]={IsTurnActive=function() return true; end,
      GetDiplomacy=function() return {IsAtWarWith=function(_,other) return s.war and other==1; end}; end,
      GetUnits=function() return {FindID=function(_,id) local u=s.units[id]; return u and u.owner==owner and u or nil; end}; end};
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
  function u:GetRange() return 2; end; function u:HasMovedIntoZOC() return self.zoc; end;
  function u:IsDelayedDeath() return self.dead; end;
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
local function Test(name,fn) Reset(); fn(); count=count+1; print("PASS attack "..name); end;
Test("friendly and neutral units never become enemy targets",function()
  Unit(1,0,1,5); assert(not A.Target(5)); Unit(2,2,1,5); assert(not A.Target(5));
end);
Test("mixed foreign stack is rejected",function()
  Unit(1,1,1,5); Unit(2,2,1,5); local target,reason=A.Target(5); assert(not target and reason);
end);
Test("garrison target cannot implicitly attack a city",function()
  Unit(1,1,1,5); s.city=true; local target,reason=A.Target(5); assert(not target and reason);
end);
Test("preview does not attack; civilians wait; ranged precedes melee",function()
  Unit(1,0,1,4); Unit(2,0,2,2); Unit(3,0,3,4);
  local p=Plan({[1]=true,[2]=true,[3]=true});
  assert(#p.orders==2 and p.orders[1].id==2 and #p.waiting==1 and #s.requests==0);
  Start(p); Tick(); assert(s.requests[1].id==2 and s.requests[1].op==2); Tick(); assert(#s.requests==1);
  s.units[2].attacks=0; Tick(); assert(#s.requests==2 and s.requests[2].op==1 and s.requests[2].args.mod==1);
  s.units[1].attacks=0; Tick(); Tick(); assert(#s.requests==2);
end);
Test("dead target never redirects to another enemy",function()
  Unit(1,0,2,2); Unit(2,0,2,3); local p=Plan({[1]=true,[2]=true}); Start(p); Tick();
  s.units[99].dead=true; Unit(100,1,1,5); Tick(); assert(#s.requests==1);
end);
Test("target moves during preview",function()
  Unit(1,0,2,2); local p=Plan({[1]=true}); s.units[99].x=6; assert(not A.Start(p,function() end));
end);
Test("fog and diplomacy stop queued requests",function()
  Unit(1,0,2,2); Start(Plan({[1]=true})); s.visible=false; Tick(); assert(#s.requests==0);
end);
Test("peace cancels after preview",function()
  Unit(1,0,2,2); Start(Plan({[1]=true})); s.war=false; Tick(); assert(#s.requests==0);
end);
Test("zero moves waits but distant melee gets an approach order",function()
  Unit(1,0,2,2).moves=0; Unit(2,0,1,2); local p=Plan({[1]=true,[2]=true}); assert(p.approaching==1 and #p.orders==1 and #p.waiting==1);
end);
Test("new war is never requested",function()
  Unit(1,0,2,2); s.newWar=true; local p=Plan({[1]=true}); assert(#p.orders==0);
end);
Test("cancel stops subsequent requests",function()
  Unit(1,0,1,4); Unit(2,0,1,6); Start(Plan({[1]=true,[2]=true})); Tick(); A.Cancel("escape"); Tick();
  assert(#s.requests==1 and #s.clears==1);
end);
Test("timeout does not retry",function()
  Unit(1,0,2,2); Start(Plan({[1]=true})); Tick(); Tick(21); Tick(); assert(#s.requests==1);
end);
Test("air uses explicit air attack",function()
  Unit(1,0,4,0); Start(Plan({[1]=true})); Tick(); assert(s.requests[1].op==3);
end);
Test("unit state rechecked immediately before request",function()
  Unit(1,0,2,2); Start(Plan({[1]=true})); s.units[1].reject=true; Tick(); Tick(); assert(#s.requests==0);
end);
Test("civilian mixed selection allows far melee to move then attack",function()
  Unit(1,0,1,3); Unit(2,0,3,2); local p=Plan({[1]=true,[2]=true});
  assert(p.direct==0 and p.approaching==1 and #p.waiting==1);
  Start(p); Tick(); assert(s.requests[1].id==1 and s.requests[1].args.mod==0 and s.requests[1].args.x==4);
  FinishMove(); assert(#s.requests==2 and s.requests[2].args.mod==1);
end);
Test("adjacent fighter attacks before distant fighter approaches",function()
  Unit(1,0,1,6); Unit(2,0,1,3); Start(Plan({[1]=true,[2]=true})); Tick();
  assert(s.requests[1].id==1 and s.requests[1].args.mod==1);
  s.units[1].attacks=0; Tick(); assert(s.requests[2].id==2 and s.requests[2].args.mod==0);
  FinishMove(); assert(s.requests[3].id==2 and s.requests[3].args.mod==1);
end);
Test("distant fighter advances even when attack needs another turn",function()
  Unit(1,0,1,0); Start(Plan({[1]=true})); Tick(); assert(s.requests[1].args.x==2);
  FinishMove(); Tick(); assert(#s.requests==1 and s.lastReport:find("接敌后待命 1",1,true));
end);
Test("ranged unit moves into range and attacks only after native recheck",function()
  s.enforceRange=true; Unit(1,0,2,2); Start(Plan({[1]=true})); Tick();
  assert(s.requests[1].op==1 and s.requests[1].args.x==3);
  FinishMove(); assert(s.requests[2].op==2);
end);
Test("siege or other move restrictions prevent invalid follow-up attack",function()
  s.enforceRange=true; Unit(1,0,2,2); Start(Plan({[1]=true})); Tick(); s.units[1].cannotShoot=true;
  FinishMove(); Tick(); assert(#s.requests==1);
end);
Test("approaching allies reserve different landing slots",function()
  Unit(1,0,1,1); Unit(2,0,1,2); local p=Plan({[1]=true,[2]=true});
  assert(p.approaching==2 and p.orders[1].approach~=p.orders[2].approach);
end);
Test("target killed before approach means no unnecessary movement",function()
  Unit(1,0,1,6); Unit(2,0,1,3); Start(Plan({[1]=true,[2]=true})); Tick();
  s.units[99].dead=true; Tick(); assert(#s.requests==1);
end);
Test("target movement during approach cancels remaining route",function()
  Unit(1,0,1,3); Start(Plan({[1]=true})); Tick(); s.units[99].x=7; Tick();
  assert(#s.requests==1 and #s.clears==1);
end);
Test("enemy territory approach is legal without declaring another war",function()
  Unit(1,0,1,3); s.territory=1; assert(Plan({[1]=true}).approaching==1);
end);
Test("neutral closed territory is not used for approach",function()
  Unit(1,0,1,3); s.territory=2; assert(#Plan({[1]=true}).orders==0);
end);
Test("approach cancel and next turn do not resume attack",function()
  Unit(1,0,1,3); Start(Plan({[1]=true})); Tick(); A.Cancel("escape"); s.turn=2; Tick();
  assert(#s.requests==1 and #s.clears==1);
end);
Test("partial stop waits for native route clearing before next unit",function()
  Unit(1,0,1,1); Unit(2,0,1,2); Start(Plan({[1]=true,[2]=true})); Tick();
  s.delayClear=true; s.units[1].moves=0; Tick(); assert(#s.requests==1);
  A.OnCleared(0,1); Tick(); assert(#s.requests==2 and s.requests[2].id==2);
end);
Test("loss of an approaching ally does not block surviving attackers",function()
  Unit(1,0,1,1); Unit(2,0,1,2); Start(Plan({[1]=true,[2]=true})); Tick();
  s.units[1]=nil; Tick(); assert(#s.requests==2 and s.requests[2].id==2);
end);
Test("manual input relinquishes approaching group",function()
  Unit(1,0,1,1); Unit(2,0,1,2); Start(Plan({[1]=true,[2]=true})); Tick();
  A.OnManualOrder(0,1); Tick(); assert(#s.requests==1 and #s.clears==1);
end);
print("ATTACK TESTS PASSED: "..count);
