-- Real flag adapter: Civ VI's double click is followed by a single release.
local selected,native,preview=0,0,0;
local now=0;
local function EventTable()
  return setmetatable({},{__index=function(t,k)
    local e=setmetatable({callbacks={}},{__call=function(self,...)
      for _,f in ipairs(self.callbacks) do f(...); end
    end});
    function e.Add(f) e.callbacks[#e.callbacks+1]=f; end
    function e.Remove() end
    rawset(t,k,e); return e;
  end});
end
LuaEvents=EventTable(); GameConfiguration={GetValue=function() return false; end}; include=function() end;
Game={GetLocalPlayer=function() return 0; end};
UI={GetElapsedTime=function() return now; end,GetInterfaceMode=function() return 1; end};
InterfaceModeTypes={SELECTION=1}; Mouse={eLClick=1,eLDblClick=2,eRClick=3};
OnUnitFlagClick=function() native=native+1; end; OnShutdown=function() end;
UnitFlag={SetInteractivity=function() end}; ContextPtr={SetShutdown=function() end};
assert(load(GC_TestFlagsSource))();
LuaEvents.GC_FlagSelect.Add(function() selected=selected+1; end);
local function Button() return {RegisterCallback=function(self,event,fn) self[event]=fn; end}; end;
local normal,health=Button(),Button(); UnitFlag.SetInteractivity({m_Instance={NormalButton=normal,HealthBarButton=health}});
LuaEvents.GC_SetMode(true);
normal[2](0,1); normal[1](0,1); assert(selected==1,"double-click release replaced selection");
now=1; normal[1](0,1); assert(selected==2);
health[2](0,1); health[1](0,1); assert(selected==3,"health bar double click differs");
LuaEvents.GC_SetMode(false); normal[1](0,1); assert(native==1 and selected==3);
print("FLAG DOUBLE-CLICK RELEASE AND NATIVE FALLBACK TESTS PASSED");
