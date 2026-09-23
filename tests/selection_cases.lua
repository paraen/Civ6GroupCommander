-- Exercise the real menu callbacks and initialization wiring without a game window.
local buttons={};
local function Control()
  return {hidden=true,text="",callbacks={},
    SetHide=function(self,v) self.hidden=v; end,IsHidden=function(self) return self.hidden; end,
    SetText=function(self,v) self.text=v; end,SetToolTipString=function() end,
    SetOffsetVal=function() end,SetSizeVal=function() end,
    SetWorldPositionVal=function(self,x,y) self.x=x; self.y=y; end,
    GetScreenOffset=function(self) return self.anchor.x,self.anchor.y; end,
    RegisterCallback=function(self,event,fn) self.callbacks[event]=fn; end};
end
Controls=setmetatable({},{__index=function(t,k) local c=Control(); rawset(t,k,c); return c; end});
local function EventTable()
  return setmetatable({},{__index=function(t,k)
    local e=setmetatable({callbacks={}},{__call=function(self,...)
      for _,f in ipairs(self.callbacks) do f(...); end
    end});
    function e.Add(fn) table.insert(e.callbacks,fn); end
    function e.Remove() end
    rawset(t,k,e); return e;
  end});
end
Events=EventTable(); LuaEvents=EventTable();
ContextPtr={BuildInstanceForControl=function(_,name,instance)
  if name=="GC_FilterChoice" then instance.Button=Control(); buttons[#buttons+1]=instance.Button;
  else
    instance.Anchor=Control(); instance.Marker=Control(); instance.ScreenPoint=Control(); instance.ScreenPoint.anchor=instance.Anchor;
  end
end,SetUpdate=function() end,ClearUpdate=function() end};
Mouse={eLClick=1}; include=function() end;
GameInfo={Units={}};
Players={[0]={GetUnits=function() return {FindID=function() end}; end}};
Game={GetLocalPlayer=function() return 0; end};
GC_SelectionInitialize();
local function Click(control) assert(control.callbacks[1]); control.callbacks[1](); end
Click(Controls.FilterButton); assert(not Controls.FilterPanel.hidden);
Click(buttons[1]); assert(Controls.FilterButton.text=="筛选：全部单位");
assert(Controls.FilterPath.text:find("全部战斗单位",1,true));
Click(buttons[1]); assert(Controls.FilterPath.text:find("陆军",1,true));
Click(buttons[6]); assert(Controls.FilterButton.text=="筛选：侦察单位（侦察兵等）" and Controls.FilterPanel.hidden);
Click(Controls.FilterButton); Click(buttons[2]);
assert(Controls.FilterPath.text:find("全部伟人",1,true));
Click(buttons[6]); assert(Controls.FilterButton.text=="筛选：大科学家");
Click(Controls.FilterButton); Click(buttons[3]); assert(Controls.FilterButton.text=="筛选：建造者");
Click(Controls.FilterButton); Click(buttons[1]); Click(Controls.FilterBack);
assert(Controls.FilterPath.text=="全部单位");
Click(Controls.FilterClose); assert(Controls.FilterPanel.hidden);
-- Real selection callbacks: two on-screen warriors, one off-screen warrior,
-- and an on-screen archer and settler. Same promotion class is not same type.
local units={};
local function Unit(id,kind,x,y)
  local u={}; function u:GetID() return id; end; function u:GetType() return kind; end;
  function u:GetX() return x; end; function u:GetY() return y; end; function u:GetName() return "unit"..id; end;
  units[id]=u;
end
Unit(1,1,100,100); Unit(2,1,200,100); Unit(3,1,1300,100); Unit(4,2,300,100); Unit(5,3,400,100);
GameInfo.Units={[1]={UnitType="UNIT_WARRIOR",Domain="DOMAIN_LAND",Combat=20,PromotionClass="PROMOTION_CLASS_MELEE"},
  [2]={UnitType="UNIT_ARCHER",Domain="DOMAIN_LAND",Combat=15,PromotionClass="PROMOTION_CLASS_RANGED"},
  [3]={UnitType="UNIT_SETTLER",Domain="DOMAIN_LAND"}};
Players[0].GetUnits=function() return {FindID=function(_,id) return units[id]; end,
  Members=function() return pairs(units); end}; end;
UI={GridToWorld=function(x,y) return x,y,0; end,GetMapLookAtWorldTarget=function() return 0,0; end,SetInterfaceMode=function() end};
UIManager={GetScreenSizeVal=function() return 1000,700; end};
Locale={Lookup=function(s) return s; end}; InterfaceModeTypes={SELECTION=1};
Click(Controls.FilterButton); Click(Controls.FilterApply);
LuaEvents.GC_InputReady("test"); LuaEvents.GC_FlagsReady("test"); Click(Controls.ModeButton);
LuaEvents.GC_FlagSelect(0,1,false,true);
assert(Controls.SelectionCount.text:find("已选 2",1,true),Controls.SelectionCount.text);
assert(not Controls.SelectionCount.text:find("unit3",1,true));
assert(not Controls.SelectionCount.text:find("unit4",1,true));
LuaEvents.GC_FlagSelect(0,4,true,false); assert(Controls.SelectionCount.text:find("已选 3",1,true));
LuaEvents.GC_FlagSelect(0,5,true,true); assert(Controls.SelectionCount.text:find("已选 4",1,true));
LuaEvents.GC_FlagSelect(0,1,true,false); assert(Controls.SelectionCount.text:find("已选 3",1,true));
-- The map double-click route uses the same selection rules.
LuaEvents.GC_DragBegin(100,100); LuaEvents.GC_DragEnd(100,100,100,100,false,true);
assert(Controls.SelectionCount.text:find("已选 2",1,true));
-- Turn end exits input mode, but must preserve the independently owned mission.
local originalEnd,originalCancel=GC_March.OnTurnEnd,GC_March.Cancel;
local ended,cancelled=0,0;
GC_March.OnTurnEnd=function() ended=ended+1; end;
GC_March.Cancel=function() cancelled=cancelled+1; end;
Events.LocalPlayerTurnEnd(); assert(ended==1 and cancelled==0);
GC_March.OnTurnEnd=originalEnd; GC_March.Cancel=originalCancel;
-- Leaving mode, browsing/applying filters and clearing selection leave orders running.
local attackCancel=GC_Attack.Cancel; local cancels=0;
GC_Attack.Cancel=function() cancels=cancels+1; end;
Click(Controls.ModeButton); Click(Controls.ModeButton);
Click(Controls.ClearButton); Click(Controls.FilterButton); Click(Controls.FilterApply);
LuaEvents.GC_ExitRequested("escape");
assert(cancels==0,"selection controls must not cancel attack orders");
Click(Controls.MarchStop); assert(cancels==1,"explicit stop must stop attacks");
GC_Attack.Cancel=attackCancel;
GC_SelectionShutdown();
print("SELECTION MENU, DOUBLE-CLICK AND TURN-END CALLBACK TESTS PASSED");
