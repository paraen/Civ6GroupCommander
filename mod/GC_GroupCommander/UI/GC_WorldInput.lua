-- Keep the installed Gathering Storm input implementation as the fallback.
include("WorldInput_Expansion2");

local baseInput = OnInputHandler;
local baseShutdown = OnShutdown;
local baseLostFocus = OnAppLostFocusHandler;
local enabled = false;
local gesture = nil;
local swallowEscapeUp = false;
local nativeDrag = nil;
local nativeSamples = 0;

-- Bounded diagnostics distinguish native input failure from a coalesced test drag.
local function NativeInput(input)
  local message = input:GetMessageType();
  if message==MouseEvents.RButtonUp or (message==MouseEvents.LButtonUp
      and UI.GetInterfaceMode()~=InterfaceModeTypes.SELECTION) then
    local unit=UI.GetHeadSelectedUnit();
    if unit then LuaEvents.GC_ManualOrder(unit:GetOwner(),unit:GetID()); end
  end
  if message == MouseEvents.LButtonDown and nativeSamples < 6 then
    local cx, cy = UI.GetMapLookAtWorldTarget();
    nativeDrag = {moves=0, cx=cx, cy=cy};
  elseif message == MouseEvents.MouseMove and nativeDrag then
    nativeDrag.moves = nativeDrag.moves + 1;
  end
  local result = baseInput(input);
  if message == MouseEvents.LButtonUp and nativeDrag then
    local cx, cy = UI.GetMapLookAtWorldTarget();
    print("[GC][NATIVE_DRAG] moves="..nativeDrag.moves.." cameraDelta="..tostring(cx-nativeDrag.cx)..","..tostring(cy-nativeDrag.cy));
    nativeDrag=nil;
    nativeSamples=nativeSamples+1;
  end
  return result;
end

local function ResetGesture(reason)
  gesture = nil;
  nativeDrag = nil;
  ClearAllCachedInputState();
  g_isMouseDownInWorld = false;
  g_isMouseDragging = false;
  EndDragMap(false);
  ProcessPan(0, 0);
  LuaEvents.GC_CancelGesture(reason);
end

local function SetMode(value)
  ResetGesture("mode_change");
  enabled = value == true;
  print("[GC][INPUT_MODE] enabled=" .. tostring(enabled));
end

local function Announce()
  LuaEvents.GC_InputReady("20260923-p2.7");
end

local function Handle(input)
  local message = input:GetMessageType();
  if message == KeyEvents.KeyDown or message == KeyEvents.KeyUp then
    LuaEvents.GC_Modifiers(input:IsShiftDown());
  end
  if message == KeyEvents.KeyUp and input:GetKey() == Keys.VK_ESCAPE and swallowEscapeUp then
    swallowEscapeUp = false;
    return true;
  end
  if message == MouseEvents.PointerLeave then
    ResetGesture("pointer_leave");
    return NativeInput(input);
  end
  if not enabled then return NativeInput(input); end
  if UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then
    ResetGesture("native_mode");
    LuaEvents.GC_ExitRequested();
    return NativeInput(input);
  end
  if (message == KeyEvents.KeyDown or message == KeyEvents.KeyUp)
      and input:GetKey() == Keys.VK_ESCAPE then
    ResetGesture("escape");
    swallowEscapeUp = message == KeyEvents.KeyDown;
    LuaEvents.GC_ExitRequested("escape");
    return true;
  end
  local x, y = UIManager:GetMousePos();
  if message == MouseEvents.LButtonDown or message == MouseEvents.LButtonDoubleClick then
    ResetGesture("new_gesture");
    gesture = {x=x, y=y, shift=input:IsShiftDown(), double=message == MouseEvents.LButtonDoubleClick};
    LuaEvents.GC_DragBegin(x, y);
    return true;
  elseif message == MouseEvents.MouseMove and gesture then
    if not input:IsLButtonDown() then
      ResetGesture("release_outside_world");
    else
      LuaEvents.GC_DragMove(x, y);
    end
    return true;
  elseif message == MouseEvents.LButtonUp then
    local completed = gesture;
    gesture = nil;
    if completed then
      LuaEvents.GC_DragEnd(completed.x, completed.y, x, y, completed.shift, completed.double);
    end
    return true;
  elseif message == MouseEvents.RButtonDown or message == MouseEvents.RButtonUp then
    -- Selection prototype deliberately prevents accidental native orders.
    if gesture then ResetGesture("right_cancel"); end
    if message == MouseEvents.RButtonUp then LuaEvents.GC_OrderPreview(UI.GetCursorPlotID()); end
    return true;
  elseif gesture then
    -- Do not scroll/rotate the camera halfway through a selection rectangle.
    return true;
  end
  return baseInput(input);
end

local function SafeInput(input)
  local ok, result = pcall(Handle, input);
  if ok then return result; end
  print("[GC][INPUT_ERROR] " .. tostring(result));
  ResetGesture("input_error");
  LuaEvents.GC_InputError(tostring(result));
  return true;
end

local function LostFocus()
  swallowEscapeUp = false;
  ResetGesture("focus_lost");
  if enabled then LuaEvents.GC_ExitRequested(); end
  baseLostFocus();
end

local function Shutdown()
  LuaEvents.GC_SetMode.Remove(SetMode);
  LuaEvents.GC_QueryInput.Remove(Announce);
  print("[GC][INPUT_SHUTDOWN]");
  baseShutdown();
end

LuaEvents.GC_SetMode.Add(SetMode);
LuaEvents.GC_QueryInput.Add(Announce);
ContextPtr:SetInputHandler(SafeInput, true);
ContextPtr:SetAppLostFocusHandler(LostFocus);
ContextPtr:SetShutdown(Shutdown);
print("[GC][INPUT_BOOT] build=20260923-p2.7");
LuaEvents.GC_ExitRequested(); -- A hot-reloaded input context starts disabled.
