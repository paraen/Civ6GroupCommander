-- Verify the actual native-input wrapper marks user orders, not previews.
local manual,native,preview=0,0,0;
local inputHandler;
local function EventTable()
  return setmetatable({},{__index=function(t,k)
    local e=setmetatable({callbacks={}},{__call=function(self,...) for _,fn in ipairs(self.callbacks) do fn(...); end; end});
    function e.Add(fn) e.callbacks[#e.callbacks+1]=fn; end; function e.Remove() end;
    rawset(t,k,e); return e;
  end});
end
LuaEvents=EventTable(); include=function() end;
OnInputHandler=function() native=native+1; return false; end;
OnShutdown=function() end; OnAppLostFocusHandler=function() end;
ContextPtr={SetInputHandler=function(_,fn) inputHandler=fn; end,SetAppLostFocusHandler=function() end,SetShutdown=function() end};
MouseEvents={LButtonDown=1,MouseMove=2,LButtonUp=3,RButtonDown=4,RButtonUp=5,LButtonDoubleClick=6,PointerLeave=7};
KeyEvents={KeyDown=20,KeyUp=21}; Keys={VK_ESCAPE=27};
InterfaceModeTypes={SELECTION=1}; local mode=1;
UI={GetInterfaceMode=function() return mode; end,GetHeadSelectedUnit=function()
  return {GetOwner=function() return 0; end,GetID=function() return 10; end};
end,GetCursorPlotID=function() return 3; end};
UIManager={GetMousePos=function() return 100,100; end};
ClearAllCachedInputState=function() end; EndDragMap=function() end; ProcessPan=function() end;
assert(load(GC_TestInputSource))();
LuaEvents.GC_ManualOrder.Add(function(owner,id) assert(owner==0 and id==10); manual=manual+1; end);
LuaEvents.GC_OrderPreview.Add(function() preview=preview+1; end);
local function Input(message) return {GetMessageType=function() return message; end}; end;
inputHandler(Input(MouseEvents.RButtonUp)); assert(manual==1 and native==1);
inputHandler(Input(MouseEvents.LButtonUp)); assert(manual==1,"ordinary selection is not an order");
mode=2; inputHandler(Input(MouseEvents.LButtonUp)); assert(manual==2);
mode=1; LuaEvents.GC_SetMode(true); inputHandler(Input(MouseEvents.RButtonUp));
assert(manual==2 and preview==1,"group preview must not relinquish march ownership");
print("NATIVE MANUAL INPUT AND GROUP PREVIEW TESTS PASSED");
