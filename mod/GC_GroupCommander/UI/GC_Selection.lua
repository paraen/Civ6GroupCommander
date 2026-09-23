-- Selection and explicit preview/execute rally UI.
local gcEnabled = false;
local gcInputReady = false;
local gcFlagsReady = false;
local gcSelected = {};
local gcLastSummary=nil;
local gcAnchors = {};
local gcSubscriptions = {};
local gcDrag = nil;
local gcFilter = "ALL";
local gcFilterPage = "ALL";
local gcFilterButtons = {};
local gcHoveredUnit = nil;
local gcRallyPlan = nil;
local gcRallyMarkers = {};
local gcFinalMarker=nil;

local function GC_ClearRally(reason,keepActive)
  gcRallyPlan=nil;
  if gcFinalMarker then gcFinalMarker.Anchor:SetHide(true); end
  for _,instance in pairs(gcRallyMarkers) do instance.Anchor:SetHide(true); end
  if not keepActive then
    if GC_Rally then GC_Rally.Cancel(reason); end
    if GC_Attack then GC_Attack.Cancel(reason); end
  end
  Controls.RallyExecute:SetText("开始持续行军");
  Controls.RallyStatus:SetText("右键指定最终目标，再点击执行");
  Controls.RallyStatus:SetToolTipString("");
end

local function GC_Status(text)
  Controls.SelectionStatus:SetText(text);
end

local function GC_Guard(callback)
  return function(...)
    local ok, err = pcall(callback, ...);
    if not ok then
      print("[GC][SELECTION_ERROR] " .. tostring(err));
      GC_Status("选取异常；请查看日志");
      gcDrag = nil;
      Controls.SelectionRect:SetHide(true);
      gcEnabled = false;
      Controls.FilterPanel:SetHide(true);
      Controls.ModeButton:SetText("群控：关闭");
      for _, instance in pairs(gcAnchors) do instance.Marker:SetHide(true); end
      LuaEvents.GC_SetMode(false);
      GC_ClearRally("selection_error");
      if GC_March then GC_March.Cancel("selection_error"); end
      if GC_Pursuit then GC_Pursuit.Cancel("selection_error"); end
      if GC_Auto then GC_Auto.SetEnabled(false); end
    end
  end;
end

local function GC_Subscribe(event, callback)
  local safe = GC_Guard(callback);
  event.Add(safe);
  gcSubscriptions[#gcSubscriptions + 1] = {event=event, callback=safe};
end

local function GC_Units()
  local playerID = Game.GetLocalPlayer();
  local player = playerID and Players[playerID];
  return player and player:GetUnits();
end

local function GC_Allowed(unit)
  local info = GameInfo.Units[unit:GetType()];
  return GC_Filters.Matches(gcFilter,info);
end

local function GC_UpdateSummary()
  local count = 0;
  local names = {};
  local units = GC_Units();
  for id in pairs(gcSelected) do
    local unit = units and units:FindID(id);
    if unit and GC_Allowed(unit) then
      count = count + 1;
      if #names < 4 then names[#names + 1] = Locale.Lookup(unit:GetName()); end
    else gcSelected[id] = nil; end
  end
  for id, instance in pairs(gcAnchors) do
    instance.Marker:SetHide(not gcEnabled or not gcSelected[id]);
  end
  local summary="已选 " .. count .. "：" .. table.concat(names, "、");
  if summary~=gcLastSummary then
    gcLastSummary=summary; Controls.SelectionCount:SetText(summary);
    Controls.SelectionCount:SetToolTipString(summary);
    print("[GC][SELECTION] count=" .. count);
  end
end

local function GC_FilterPath(id)
  local names={}; local node=GC_Filters.Nodes[id];
  while node do table.insert(names,1,node.label); node=GC_Filters.Nodes[node.parent]; end
  return table.concat(names," > ");
end
local function GC_ApplyFilter(id)
  GC_ClearRally("filter_changed",true);
  gcFilter=id;
  Controls.FilterButton:SetText("筛选："..GC_Filters.Nodes[id].label);
  Controls.FilterButton:SetToolTipString(GC_FilterPath(id));
  GC_UpdateSummary(); Controls.FilterPanel:SetHide(true);
  print("[GC][FILTER] category="..id);
end
local function GC_ShowFilters(page)
  gcFilterPage=page;
  local node=GC_Filters.Nodes[page];
  Controls.FilterPath:SetText(GC_FilterPath(page));
  Controls.FilterPath:SetToolTipString(GC_FilterPath(page));
  Controls.FilterBack:SetHide(not node.parent);
  Controls.FilterApply:SetText(page=="ALL" and "选用全部单位" or "选用此类全部单位");
  Controls.FilterApply:RegisterCallback(Mouse.eLClick,GC_Guard(function() GC_ApplyFilter(page); end));
  for _,instance in ipairs(gcFilterButtons) do instance.Button:SetHide(true); end
  for index,id in ipairs(node.children) do
    local choice=GC_Filters.Nodes[id]; local instance=gcFilterButtons[index];
    if not instance then
      instance={}; ContextPtr:BuildInstanceForControl("GC_FilterChoice",instance,Controls.FilterChoices);
      gcFilterButtons[index]=instance;
    end
    instance.Button:SetOffsetVal(((index-1)%2)*244,math.floor((index-1)/2)*38);
    instance.Button:SetText((gcFilter==id and "[ICON_Checkmark] " or "")..choice.label..(#choice.children>0 and "  >" or ""));
    instance.Button:SetToolTipString(GC_FilterPath(id).."[NEWLINE]"..(#choice.children>0 and "点击查看细分；进入目录不会改变当前筛选。" or "点击应用此筛选；不会自动选中全地图单位。"));
    instance.Button:SetHide(false);
    instance.Button:RegisterCallback(Mouse.eLClick,GC_Guard(function()
      if #choice.children>0 then GC_ShowFilters(id); else GC_ApplyFilter(id); end
    end));
  end
  Controls.FilterPanel:SetSizeVal(512,math.ceil(#node.children/2)*38+106);
  Controls.FilterPanel:SetHide(false);
end

local function GC_RefreshAnchors()
  local units = GC_Units();
  if not units then return; end
  local found = {};
  for _, unit in units:Members() do
    local id = unit:GetID();
    found[id] = true;
    local instance = gcAnchors[id];
    if not instance then
      instance = {};
      ContextPtr:BuildInstanceForControl("GC_UnitAnchor", instance, Controls.UnitAnchors);
      instance.Marker:SetText("◆");
      gcAnchors[id] = instance;
    end
    local x, y, z = UI.GridToWorld(unit:GetX(), unit:GetY());
    instance.Anchor:SetWorldPositionVal(x, y, z);
    instance.Anchor:SetHide(false);
  end
  for id, instance in pairs(gcAnchors) do
    if not found[id] then
      instance.Anchor:SetHide(true);
      gcSelected[id] = nil;
    end
  end
  GC_UpdateSummary();
end

local function GC_ShowMarchSteps(plan)
  for _,instance in pairs(gcRallyMarkers) do instance.Anchor:SetHide(true); end
  local labels={};
  for i,order in ipairs(plan.orders) do
    local plot=Map.GetPlotByIndex(order.plot);
    labels[order.plot]=labels[order.plot] or {}; table.insert(labels[order.plot],tostring(i));
    local instance=gcRallyMarkers[order.plot];
    if not instance then instance={}; ContextPtr:BuildInstanceForControl("GC_RallyAnchor",instance,Controls.RallyAnchors); gcRallyMarkers[order.plot]=instance; end
    local x,y,z=UI.GridToWorld(plot:GetX(),plot:GetY()); instance.Anchor:SetWorldPositionVal(x,y,z);
    instance.Marker:SetText("["..table.concat(labels[order.plot],",").."]"); instance.Anchor:SetHide(false);
  end
  local target=Map.GetPlotByIndex(plan.target);
  if target then
    if not gcFinalMarker then gcFinalMarker={}; ContextPtr:BuildInstanceForControl("GC_RallyAnchor",gcFinalMarker,Controls.RallyAnchors); end
    local x,y,z=UI.GridToWorld(target:GetX(),target:GetY()); gcFinalMarker.Anchor:SetWorldPositionVal(x,y,z);
    gcFinalMarker.Marker:SetText("[最终目标]"); gcFinalMarker.Marker:SetOffsetVal(0,-26); gcFinalMarker.Anchor:SetHide(false);
  end
end

local function GC_StopMarch(reason)
  GC_March.Cancel(reason);
  if gcFinalMarker then gcFinalMarker.Anchor:SetHide(true); end
  for _,instance in pairs(gcRallyMarkers) do instance.Anchor:SetHide(true); end
end

local function GC_Cancel(reason)
  gcDrag = nil;
  Controls.SelectionRect:SetHide(true);
  if reason and reason ~= "new_gesture" then
    print("[GC][GESTURE_CANCEL] " .. tostring(reason));
  end
end

local function GC_SetMode(value)
  if value and (not gcInputReady or not gcFlagsReady) then
    GC_Status("地图或旗帜输入未接通；请重载并检查日志");
    LuaEvents.GC_QueryInput();
    LuaEvents.GC_QueryFlags();
    return;
  end
  gcEnabled = value == true;
  Controls.FilterPanel:SetHide(true);
  GC_ClearRally("mode_change",true);
  GC_Cancel("mode_change");
  if gcEnabled then UI.SetInterfaceMode(InterfaceModeTypes.SELECTION); end
  Controls.ModeButton:SetText(gcEnabled and "群控：开启" or "群控：关闭");
  GC_Status(gcEnabled and "左键框选；右键仅预览；Esc 退出" or "普通模式：左键拖地图");
  LuaEvents.GC_SetMode(gcEnabled);
  GC_RefreshAnchors();
end

local function GC_MouseMoved(x, y)
  if not gcEnabled or not gcDrag then return; end
  local cameraX, cameraY = UI.GetMapLookAtWorldTarget();
  if math.abs(cameraX - gcDrag.cameraX) > 0.1 or math.abs(cameraY - gcDrag.cameraY) > 0.1 then
    GC_Cancel("camera_changed");
    GC_Status("镜头发生移动，本次框选已取消");
    return;
  end
  local width, height = math.abs(x-gcDrag.x), math.abs(y-gcDrag.y);
  Controls.SelectionRect:SetOffsetVal(math.min(x,gcDrag.x), math.min(y,gcDrag.y));
  Controls.SelectionRect:SetSizeVal(math.max(1,width), math.max(1,height));
  Controls.SelectionRect:SetHide(width < 6 and height < 6);
end

local function GC_DragBegin(x, y)
  if not gcEnabled then return; end
  Controls.FilterPanel:SetHide(true);
  GC_ClearRally("selection_changed",true);
  GC_RefreshAnchors();
  local cx, cy = UI.GetMapLookAtWorldTarget();
  gcDrag = {x=x, y=y, cameraX=cx, cameraY=cy, hovered=gcHoveredUnit};
end

local function GC_DragEnd(x1, y1, x2, y2, shift, double)
  if not gcEnabled or not gcDrag then return; end
  GC_MouseMoved(x2,y2);
  if not gcDrag then return; end
  local hovered = gcDrag.hovered;
  GC_Cancel();
  local units = GC_Units();
  if not units then return; end
  local candidates = {};
  local isClick = math.abs(x2-x1) < 6 and math.abs(y2-y1) < 6;
  local nearest, nearestDistance = nil, 48*48;
  for _, unit in units:Members() do
    if GC_Allowed(unit) then
      local instance = gcAnchors[unit:GetID()];
      local sx, sy = instance.ScreenPoint:GetScreenOffset();
      if isClick then
        local distance = (sx-x2)^2 + (sy-y2)^2;
        if distance < nearestDistance then nearest,nearestDistance=unit,distance; end
      elseif sx>=math.min(x1,x2) and sx<=math.max(x1,x2)
          and sy>=math.min(y1,y2) and sy<=math.max(y1,y2) then
        candidates[unit:GetID()] = true;
      end
    end
  end
  if isClick and hovered then
    local unit = units:FindID(hovered);
    if unit and GC_Allowed(unit) then nearest = unit; end
  end
  if isClick and nearest then
    if double then
      local sw,sh = UIManager:GetScreenSizeVal();
      for _, unit in units:Members() do
        if unit:GetType()==nearest:GetType() then
          local sx,sy=gcAnchors[unit:GetID()].ScreenPoint:GetScreenOffset();
          if sx>=0 and sy>=0 and sx<=sw and sy<=sh then candidates[unit:GetID()]=true; end
        end
      end
    else candidates[nearest:GetID()]=true; end
  end
  if not shift then gcSelected = {}; end
  for id in pairs(candidates) do
    if shift and not double and gcSelected[id] then gcSelected[id]=nil; else gcSelected[id]=true; end
  end
  GC_UpdateSummary();
  GC_Status("选取完成；右键预览集结位置");
  print("[GC][RECT] "..x1..","..y1.." -> "..x2..","..y2);
end

function GC_SelectionInitialize()
  include("GC_Filters");
  GC_Filters.Initialize();
  include("GC_Rally");
  include("GC_Attack");
  include("GC_March");
  include("GC_Pursuit");
  include("GC_Auto");
  GC_Auto.Initialize(function(id) return gcDrag~=nil or (gcEnabled and gcSelected[id]); end,function(message)
    Controls.RallyStatus:SetText(message); Controls.RallyStatus:SetToolTipString(message);
    Controls.AutoButton:SetText(GC_Auto.IsEnabled() and "自动交战：开" or "自动交战：关");
  end);
  Controls.AutoButton:SetText("自动交战：关");
  Controls.AutoButton:SetToolTipString("可选：闲置陆地战斗单位优势或近均势时攻击，劣势时尝试避让。已有任务、手动操作、驻守/睡眠单位优先保留。每单位每回合最多一次。默认关闭，读档后需重新开启。");
  Controls.AutoButton:RegisterCallback(Mouse.eLClick,GC_Guard(function() GC_Auto.SetEnabled(not GC_Auto.IsEnabled()); end));
  GC_Rally.SelfTest();
  Controls.RallyExecute:SetText("开始持续行军");
  Controls.MarchStatus:SetText("持续行军：尚未指定目标");
  Controls.MarchStop:RegisterCallback(Mouse.eLClick,GC_Guard(function() GC_Auto.SetEnabled(false); GC_Pursuit.Cancel("stop_button"); GC_StopMarch("stop_button"); GC_ClearRally("stop_button"); end));
  Controls.MarchStop:SetToolTipString("停止全部群控命令。关闭群控、切换筛选或清除选择不会停止已执行的行军与攻击。");
  GC_ClearRally("initialize");
  Controls.RallyExecute:RegisterCallback(Mouse.eLClick,GC_Guard(function()
    if not gcEnabled or not gcRallyPlan then Controls.RallyStatus:SetText("请先开启群控并右键预览落点"); return; end
    local plan=gcRallyPlan;
    if plan.kind=="attack" and not GC_Pursuit.CanStart(plan) then
      Controls.RallyStatus:SetText("没有可攻击或接敌的单位；鼠标移至此处查看待命原因"); return;
    end
    gcRallyPlan=nil;
    GC_Auto.Interrupt("explicit_order");
    for id in pairs(gcSelected) do GC_Auto.Protect(id); end
    if plan.kind=="attack" then GC_StopMarch("attack_requested");
    else GC_Pursuit.Cancel("march_requested"); GC_Attack.Cancel("march_requested"); end
    local runner=plan.kind=="attack" and GC_Pursuit or GC_March;
    if not runner.Start(plan,function(message)
      if plan.kind=="march" then Controls.MarchStatus:SetText(message); else Controls.RallyStatus:SetText(message); end
      GC_RefreshAnchors();
    end,GC_ShowMarchSteps) then
      Controls.RallyStatus:SetText("没有可执行的命令；请重新预览");
    end
  end));
  ContextPtr:SetUpdate(GC_Guard(function(delta) GC_Rally.Update(delta); GC_Attack.Update(delta); GC_March.Update(delta); GC_Pursuit.Update(delta); GC_Auto.Update(delta); end));
  Controls.ModeButton:SetText("群控：关闭");
  Controls.FilterButton:SetText("筛选：全部单位");
  Controls.ClearButton:SetText("清除选择");
  Controls.SelectionCount:SetText("已选 0");
  GC_Status("正在检查地图输入入口");
  Controls.ModeButton:RegisterCallback(Mouse.eLClick, GC_Guard(function() GC_SetMode(not gcEnabled); end));
  Controls.FilterButton:RegisterCallback(Mouse.eLClick, GC_Guard(function()
    if Controls.FilterPanel:IsHidden() then GC_ShowFilters("ALL"); else Controls.FilterPanel:SetHide(true); end
  end));
  Controls.FilterBack:RegisterCallback(Mouse.eLClick,GC_Guard(function()
    GC_ShowFilters(GC_Filters.Nodes[gcFilterPage].parent or "ALL");
  end));
  Controls.FilterClose:RegisterCallback(Mouse.eLClick,function() Controls.FilterPanel:SetHide(true); end);
  Controls.ClearButton:RegisterCallback(Mouse.eLClick, GC_Guard(function() GC_ClearRally("clear",true); gcSelected={}; GC_UpdateSummary(); end));
  GC_Subscribe(LuaEvents.GC_InputReady, function(build)
    gcInputReady=true;
    GC_Status("地图输入已接通；开启群控可框选");
    print("[GC][INPUT_CONNECTED] " .. tostring(build));
  end);
  GC_Subscribe(LuaEvents.GC_FlagsReady, function(build)
    gcFlagsReady=true;
    print("[GC][FLAGS_CONNECTED] "..tostring(build));
  end);
  GC_Subscribe(LuaEvents.GC_FlagSelect, function(playerID, unitID, shift, double)
    if not gcEnabled or playerID ~= Game.GetLocalPlayer() then return; end
    local units = GC_Units();
    local unit = units and units:FindID(unitID);
    if not unit or not GC_Allowed(unit) then return; end
    GC_RefreshAnchors();
    local sx,sy = gcAnchors[unitID].ScreenPoint:GetScreenOffset();
    GC_DragBegin(sx,sy);
    gcDrag.hovered=unitID;
    GC_DragEnd(sx,sy,sx,sy,shift,double);
    print("[GC][FLAG_SELECT] unit="..unitID.." double="..tostring(double).." shift="..tostring(shift));
  end);
  GC_Subscribe(LuaEvents.GC_DragBegin, GC_DragBegin);
  GC_Subscribe(LuaEvents.GC_DragMove, GC_MouseMoved);
  GC_Subscribe(LuaEvents.GC_DragEnd, GC_DragEnd);
  GC_Subscribe(LuaEvents.UnitFlagManager_PointerEntered, function(playerID, unitID)
    gcHoveredUnit = playerID == Game.GetLocalPlayer() and unitID or nil;
  end);
  GC_Subscribe(LuaEvents.UnitFlagManager_PointerExited, function(playerID, unitID)
    if playerID == Game.GetLocalPlayer() and gcHoveredUnit == unitID then gcHoveredUnit=nil; end
  end);
  GC_Subscribe(LuaEvents.GC_CancelGesture, GC_Cancel);
  GC_Subscribe(LuaEvents.GC_ExitRequested, function(reason)
    -- Escape exits selection only; stopping orders has its own button.
    GC_SetMode(false);
  end);
  GC_Subscribe(LuaEvents.GC_InputError, function() GC_Auto.SetEnabled(false); GC_Pursuit.Cancel("input_error"); GC_StopMarch("input_error"); GC_ClearRally("input_error"); GC_SetMode(false); GC_Status("输入异常；已恢复普通模式"); end);
  GC_Subscribe(LuaEvents.GC_OrderPreview, function(plot)
    if not gcEnabled then return; end
    GC_ClearRally("new_target",true);
    local target,blocked=GC_Attack.Target(plot);
    if blocked then Controls.RallyStatus:SetText(blocked); return; end
    if target then
      gcRallyPlan=GC_Attack.Plan(gcSelected,target,true);
      if gcRallyPlan.error then Controls.RallyStatus:SetText(gcRallyPlan.error); gcRallyPlan=nil; return; end
      Controls.RallyExecute:SetText("开始协同进攻");
      Controls.RallyStatus:SetText("立即攻击 "..gcRallyPlan.direct.."；接敌移动 "..gcRallyPlan.approaching.."；待命 "..#gcRallyPlan.waiting);
      local markers={};
      for _,order in ipairs(gcRallyPlan.orders) do if order.approach then markers[#markers+1]={plot=order.approach}; end; end
      GC_ShowMarchSteps({target=target.plot,orders=markers});
      if gcFinalMarker then gcFinalMarker.Marker:SetText("[攻击目标]"); end
      local reasons={};
      for _,item in ipairs(gcRallyPlan.waiting) do reasons[#reasons+1]=item.id.."："..item.reason; end
      Controls.RallyStatus:SetToolTipString(table.concat(reasons,"[NEWLINE]"));
      GC_Status("战斗单位协同推进并跨回合继续；平民待命");
      return;
    end
    gcRallyPlan=GC_March.Plan(gcSelected,plot);
    if gcRallyPlan.error then
      print("[GC][RALLY_REJECT] reason="..gcRallyPlan.error);
      Controls.RallyStatus:SetText(gcRallyPlan.error); gcRallyPlan=nil; return;
    end
    GC_ShowMarchSteps(gcRallyPlan);
    for _,item in ipairs(gcRallyPlan.waiting) do print("[GC][RALLY_WAIT] unit="..item.id.." reason="..item.reason); end
    local detail={};
    for _,item in ipairs(gcRallyPlan.waiting) do detail[#detail+1]=tostring(item.id).."："..item.reason; end
    Controls.RallyStatus:SetToolTipString(table.concat(detail,"[NEWLINE]"));
    Controls.RallyStatus:SetText("本回合可移动 "..#gcRallyPlan.orders.."；待命 "..#gcRallyPlan.waiting.."；下回合自动继续（未下令）");
    GC_Status("数字为本回合预计落点；最终目标可在迷雾中");
    print("[GC][RALLY_PLAN] orders="..#gcRallyPlan.orders.." staying="..gcRallyPlan.staying.." waiting="..#gcRallyPlan.waiting.." commandsIssued=0");
  end);
  GC_Subscribe(Events.LoadScreenClose, function() GC_March.Restore(function(message) Controls.MarchStatus:SetText(message); end,GC_ShowMarchSteps); GC_RefreshAnchors(); LuaEvents.GC_QueryInput(); LuaEvents.GC_QueryFlags(); end);
  GC_Subscribe(Events.LocalPlayerTurnEnd, function() GC_March.OnTurnEnd(); GC_ClearRally("turn_end"); GC_SetMode(false); end);
  GC_Subscribe(Events.LocalPlayerTurnBegin, GC_March.OnTurnBegin);
  GC_Subscribe(Events.UnitOperationAdded, GC_March.OnOperationAdded);
  GC_Subscribe(LuaEvents.GC_ManualOrder, function(owner,id)
    GC_Auto.OnManualOrder(owner,id); GC_Pursuit.Release(owner,id); GC_March.OnManualOrder(owner,id); GC_Attack.OnManualOrder(owner,id);
  end);
  GC_Subscribe(Events.UnitCommandStarted,function(owner,id,command)
    if not GC_Attack.ConsumeInternalCommand(owner,id,command) then GC_Auto.OnCommand(owner,id); GC_Pursuit.Release(owner,id); end
  end);
  GC_Subscribe(Events.UnitOperationAdded,GC_Auto.OnOperationAdded);
  GC_Subscribe(Events.UnitOperationsCleared,GC_Auto.OnCleared);
  GC_Subscribe(Events.UnitOperationDeactivated,GC_Auto.OnEnded);
  GC_Subscribe(Events.UnitCommandStarted, GC_March.OnCommandStarted);
  GC_Subscribe(Events.UnitOperationsCleared, GC_March.OnCleared);
  GC_Subscribe(Events.UnitOperationDeactivated, GC_March.OnEnded);
  GC_Subscribe(Events.UnitOperationsCleared, GC_Attack.OnCleared);
  GC_Subscribe(Events.UnitOperationDeactivated, GC_Attack.OnEnded);
  GC_Subscribe(Events.UnitOperationDeactivated, GC_Rally.OnOperationDeactivated);
  GC_Subscribe(Events.UnitOperationsCleared, GC_Rally.OnOperationsCleared);
  GC_Subscribe(Events.LocalPlayerChanged, function() GC_Auto.SetEnabled(false); GC_Pursuit.Cancel("player_changed"); GC_StopMarch("player_changed"); GC_ClearRally("player_changed"); gcHoveredUnit=nil; gcSelected={}; GC_SetMode(false); end);
  GC_Subscribe(Events.UnitRemovedFromMap, function(playerID, unitID)
    if playerID ~= Game.GetLocalPlayer() then return; end
    GC_March.Release(playerID,unitID,"单位已移除");
    gcSelected[unitID]=nil;
    -- Invalidate an unexecuted preview, but let the active attack scheduler
    -- retire the missing unit and continue processing surviving group members.
    gcRallyPlan=nil;
    GC_Rally.Cancel("unit_removed");
    if gcHoveredUnit == unitID then gcHoveredUnit=nil; end
    if gcAnchors[unitID] then gcAnchors[unitID].Anchor:SetHide(true); end
    GC_UpdateSummary();
  end);
  GC_Subscribe(LuaEvents.DiplomacyActionView_HideIngameUI, function() GC_March.SetPaused("diplomacy",true); GC_ClearRally("diplomacy"); GC_SetMode(false); end);
  GC_Subscribe(LuaEvents.DiplomacyActionView_ShowIngameUI, function() GC_March.SetPaused("diplomacy",false); end);
  GC_Subscribe(LuaEvents.FullscreenMap_Shown, function() GC_March.SetPaused("fullscreen",true); GC_ClearRally("fullscreen"); GC_SetMode(false); end);
  GC_Subscribe(LuaEvents.FullscreenMap_Closed, function() GC_March.SetPaused("fullscreen",false); end);
  GC_Subscribe(LuaEvents.EndGameMenu_Shown, function() GC_March.SetPaused("menu",true); GC_ClearRally("menu"); end);
  GC_Subscribe(LuaEvents.EndGameMenu_Closed, function() GC_March.SetPaused("menu",false); end);
  LuaEvents.GC_QueryInput();
  LuaEvents.GC_QueryFlags();
end

function GC_SelectionShutdown()
  if GC_Auto then GC_Auto.SetEnabled(false); end
  if GC_Pursuit then GC_Pursuit.Cancel("shutdown"); end
  if GC_March then GC_March.Shutdown(); end
  if GC_Rally then GC_Rally.Cancel("shutdown"); end
  if GC_Attack then GC_Attack.Cancel("shutdown"); end
  ContextPtr:ClearUpdate();
  for _, item in ipairs(gcSubscriptions) do item.event.Remove(item.callback); end
  gcSubscriptions = {};
end
