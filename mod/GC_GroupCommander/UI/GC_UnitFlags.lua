-- Unit flags are buttons and can consume clicks before WorldInput sees them.
if GameConfiguration.GetValue("GAMEMODE_BARBARIAN_CLANS") then
  include("UnitFlagManager_BarbarianClansMode");
else
  include("UnitFlagManager");
end

local baseInteractivity = UnitFlag.SetInteractivity;
local baseClick = OnUnitFlagClick;
local baseShutdown = OnShutdown;
local enabled = false;
local shift = false;
local lastDouble = nil;

local function SetMode(value)
  enabled = value == true;
  shift = false;
  lastDouble = nil;
end

local function SetModifiers(value) shift = value == true; end
local function Announce() LuaEvents.GC_FlagsReady("20260923-p2.7"); end

local function Click(playerID, unitID, double, right)
  -- Civ VI emits eLDblClick followed by eLClick for the same release.
  -- Consume that trailing click so it cannot replace the whole-type selection.
  if enabled and not right then
    if double then
      lastDouble={player=playerID, unit=unitID, time=UI.GetElapsedTime()};
    elseif lastDouble then
      local trailing=lastDouble.player==playerID and lastDouble.unit==unitID
        and UI.GetElapsedTime()-lastDouble.time < 0.6;
      lastDouble=nil;
      if trailing then print("[GC][FLAG_DOUBLE_RELEASE] consumed"); return; end
    end
  else lastDouble=nil; end
  if not enabled then
    -- Native flags have no double-click callback; retain their single click.
    if not double then baseClick(playerID, unitID); end
    return;
  end
  if UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then
    LuaEvents.GC_ExitRequested();
    return;
  end
  if right or playerID ~= Game.GetLocalPlayer() then
    local player = Players[playerID];
    local unit = player and player:GetUnits():FindID(unitID);
    if unit then LuaEvents.GC_OrderPreview(Map.GetPlot(unit:GetX(), unit:GetY()):GetIndex()); end
  else
    LuaEvents.GC_FlagSelect(playerID, unitID, shift, double);
  end
end

local function SafeClick(playerID, unitID, double, right)
  local ok, err = pcall(Click, playerID, unitID, double, right);
  if not ok then
    enabled = false;
    print("[GC][FLAG_ERROR] "..tostring(err));
    LuaEvents.GC_InputError(tostring(err));
  end
end

function UnitFlag.SetInteractivity(self)
  baseInteractivity(self);
  for _, button in ipairs({self.m_Instance.NormalButton, self.m_Instance.HealthBarButton}) do
    button:RegisterCallback(Mouse.eLClick, function(playerID, unitID) SafeClick(playerID, unitID, false, false); end);
    button:RegisterCallback(Mouse.eLDblClick, function(playerID, unitID) SafeClick(playerID, unitID, true, false); end);
    button:RegisterCallback(Mouse.eRClick, function(playerID, unitID) SafeClick(playerID, unitID, false, true); end);
  end
end

local function Shutdown()
  LuaEvents.GC_SetMode.Remove(SetMode);
  LuaEvents.GC_Modifiers.Remove(SetModifiers);
  LuaEvents.GC_QueryFlags.Remove(Announce);
  print("[GC][FLAGS_SHUTDOWN]");
  baseShutdown();
end

LuaEvents.GC_SetMode.Add(SetMode);
LuaEvents.GC_Modifiers.Add(SetModifiers);
LuaEvents.GC_QueryFlags.Add(Announce);
ContextPtr:SetShutdown(Shutdown);
print("[GC][FLAGS_BOOT] build=20260923-p2.7");
LuaEvents.GC_ExitRequested(); -- Reconcile mode after a developer hot reload.
