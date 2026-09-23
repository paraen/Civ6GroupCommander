-- Save-backed state only; this bridge never issues unit commands.
local function SaveMarch(owner,params)
  if type(owner)~="number" or not Players[owner] or type(params)~="table" then return; end
  local value=params.action=="clear" and "" or params.value;
  if type(value)~="string" or #value>12000 or value:find("[^%d,;%-]") then print("[GC][MARCH_SAVE_REJECT] invalid payload"); return; end
  if value~="" then
    local version,storedOwner=value:match("^(%d+),(%d+),");
    if version~="2" or tonumber(storedOwner)~=owner then return; end
  end
  Players[owner]:SetProperty("GC_MarchV2",value);
  print("[GC][MARCH_SAVED] owner="..owner.." empty="..tostring(value==""));
end
GameEvents.GC_SaveMarchV2.Add(SaveMarch);
print("[GC][SAVE_BRIDGE_READY] version=2");
