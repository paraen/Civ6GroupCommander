-- Keep the visible diagnostic panel available even if feature initialization fails.
local BUILD = "20260923-p2.7";
print("[GC][BOOT] build=" .. BUILD .. " context=GC_LoadProbe");

local initialized = false;
local shuttingDown = false;
local clicks = 0;
local subscriptions = {};
local visibilityBlocks = {};

local function Log(stage, message)
  print("[GC][" .. stage .. "] build=" .. BUILD .. " " .. tostring(message));
end

local function ReportError(stage, message)
  Log("ERROR", stage .. ": " .. tostring(message));
  -- The root may itself have failed; the native logs remain the fallback.
  pcall(function()
    if Controls and Controls.ResultLabel then
      Controls.ResultLabel:SetText("自检异常：请查看 Lua.log 中的 [GC][ERROR]");
    end
  end);
end

local function Guard(stage, callback)
  local ok, message = pcall(callback);
  if not ok then ReportError(stage, message); end
  return ok;
end

local function GetPlayerStatus()
  if not Game or type(Game.GetLocalPlayer) ~= "function" then
    return "UI 已运行；等待游戏数据", nil;
  end
  local playerID = Game.GetLocalPlayer();
  if playerID == nil or playerID < 0 then
    return "UI 已运行；等待本地玩家", nil;
  end
  return "UI 已运行；本地玩家 " .. tostring(playerID), playerID;
end

local function RefreshStatus()
  local status = GetPlayerStatus();
  Controls.StateLabel:SetText(status);
end

local function ReconcileVisibility(reason)
  if shuttingDown then return; end
  local hidden = next(visibilityBlocks) ~= nil;
  ContextPtr:SetHide(hidden);
  Controls.GCPanel:SetHide(false);
  -- A request is not proof of on-screen visibility; real-game QA is required.
  Log("VISIBILITY_REQUEST", "hidden=" .. tostring(hidden) .. " reason=" .. reason);
end

local function OnReadyEvent()
  if shuttingDown then return; end
  Guard("ready", function()
    RefreshStatus();
    ReconcileVisibility("ready_event");
    Log("READY_EVENT", "received");
  end);
end

local function OnPlayerChanged()
  if shuttingDown then return; end
  Guard("player_changed", RefreshStatus);
end

local function OnSelfTest()
  if shuttingDown then return; end
  Guard("self_test", function()
    clicks = clicks + 1;
    Controls.ResultLabel:SetText("点击 " .. tostring(clicks) .. " 次；按钮回调正常");
    RefreshStatus();
    local _, playerID = GetPlayerStatus();
    local hasRequest = UnitManager ~= nil
      and type(UnitManager.RequestOperation) == "function";
    local hasCheck = UnitManager ~= nil
      and type(UnitManager.CanStartOperation) == "function";
    Log("SELF_TEST", "clicks=" .. tostring(clicks)
      .. " player=" .. tostring(playerID)
      .. " requestAPI=" .. tostring(hasRequest)
      .. " checkAPI=" .. tostring(hasCheck)
      .. " commandsIssued=0");
    if not hasRequest or not hasCheck then
      Controls.StateLabel:SetText("UI 可用；单位接口缺失，详见 Lua.log");
    end
  end);
end

local function Subscribe(event, callback)
  if event == nil then error("Required event is unavailable"); end
  event.Add(callback);
  subscriptions[#subscriptions + 1] = { event = event, callback = callback };
end

local function SubscribeVisibility(hideEvent, showEvent, key)
  Subscribe(hideEvent, function()
    if shuttingDown then return; end
    visibilityBlocks[key] = true;
    Guard("hide_" .. key, function() ReconcileVisibility("hide_" .. key); end);
  end);
  Subscribe(showEvent, function()
    if shuttingDown then return; end
    visibilityBlocks[key] = nil;
    Guard("show_" .. key, function() ReconcileVisibility("show_" .. key); end);
  end);
end

local function OnInit()
  if shuttingDown or initialized then return; end
  initialized = true;
  Guard("initialize", function()
    Controls.TitleLabel:SetText("单位群控");
    Controls.BuildLabel:SetText("构建：" .. BUILD);
    -- Assign literal diagnostic text explicitly; verify it on screen.
    Controls.ResultLabel:SetText("右键指定目标，行军可跨回合继续");
    Controls.StageLabel:SetText("行军／攻击测试");
    Controls.SelfTestButton:SetText("自检（只读）");
    Controls.SelfTestButton:RegisterCallback(Mouse.eLClick, OnSelfTest);
    Controls.DiagnosticsButton:RegisterCallback(Mouse.eLClick, function()
      local opening=Controls.DiagnosticsPanel:IsHidden();
      Controls.DiagnosticsPanel:SetHide(not opening);
      Controls.SelectionPanel:SetHide(opening);
      Controls.FilterPanel:SetHide(true);
    end);
    -- Make the diagnostic UI available before probing any gameplay API.
    ReconcileVisibility("init");
    Log("UI_READY", "callback_registered");
  end);
  Guard("player_status", RefreshStatus);
  Guard("subscribe_ready", function()
    Subscribe(Events.LoadScreenClose, OnReadyEvent);
    Subscribe(Events.LoadGameViewStateDone, OnReadyEvent);
    Subscribe(Events.LocalPlayerTurnBegin, OnPlayerChanged);
    Subscribe(Events.LocalPlayerChanged, OnPlayerChanged);
  end);
  Guard("subscribe_visibility", function()
    SubscribeVisibility(LuaEvents.DiplomacyActionView_HideIngameUI,
      LuaEvents.DiplomacyActionView_ShowIngameUI, "diplomacy");
    SubscribeVisibility(LuaEvents.FullscreenMap_Shown,
      LuaEvents.FullscreenMap_Closed, "fullscreen_map");
    SubscribeVisibility(LuaEvents.EndGameMenu_Shown,
      LuaEvents.EndGameMenu_Closed, "end_game");
  end);
  Guard("selection_initialize", function()
    include("GC_Selection");
    GC_SelectionInitialize();
  end);
end

local function OnShutdown()
  shuttingDown = true;
  if GC_SelectionShutdown then Guard("selection_shutdown", GC_SelectionShutdown); end
  for _, item in ipairs(subscriptions) do
    Guard("unsubscribe", function() item.event.Remove(item.callback); end);
  end
  subscriptions = {};
  Log("SHUTDOWN", "listeners_removed");
end

Guard("bootstrap", function()
  ContextPtr:SetInitHandler(OnInit);
  ContextPtr:SetShutdown(OnShutdown);
end);
