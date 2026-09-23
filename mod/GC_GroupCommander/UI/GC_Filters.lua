-- Selection categories use promotion classes, never movement occupancy classes alone.
GC_Filters = {Nodes={}, Replaces={}};
local F=GC_Filters;
local function Add(id,label,parent,match)
  local n={id=id,label=label,parent=parent,match=match,children={}};
  F.Nodes[id]=n;
  if parent then table.insert(F.Nodes[parent].children,id); end
end
local function Military(info)
  return (info.Combat or 0)>0 or (info.RangedCombat or 0)>0 or (info.Bombard or 0)>0
    or info.FormationClass=="FORMATION_CLASS_SUPPORT";
end
function F.IsType(info,types)
  local name=info.UnitType; local seen={};
  while name and not seen[name] do
    if types[name] then return true; end
    seen[name]=true; name=F.Replaces[name];
  end
  return false;
end
local function Types(...)
  local t={}; for _,name in ipairs({...}) do t["UNIT_"..name]=true; end
  return function(info) return F.IsType(info,t); end;
end
local function Promotion(name)
  return function(info) return info.PromotionClass=="PROMOTION_CLASS_"..name; end;
end
Add("ALL","全部单位",nil,function() return true; end);
Add("COMBAT","全部战斗单位","ALL",Military);
Add("LAND","陆军","COMBAT",function(i) return Military(i) and i.Domain=="DOMAIN_LAND"; end);
Add("MELEE","近战","LAND",Promotion("MELEE"));
Add("RANGED","远程攻击","LAND",Promotion("RANGED"));
Add("CAVALRY","骑兵","LAND",function(i) return i.PromotionClass=="PROMOTION_CLASS_LIGHT_CAVALRY" or i.PromotionClass=="PROMOTION_CLASS_HEAVY_CAVALRY"; end);
Add("LIGHT_CAVALRY","轻骑兵","CAVALRY",Promotion("LIGHT_CAVALRY"));
Add("HEAVY_CAVALRY","重骑兵","CAVALRY",Promotion("HEAVY_CAVALRY"));
Add("ANTI_CAVALRY","抗骑兵","LAND",Promotion("ANTI_CAVALRY"));
Add("SIEGE","攻城","LAND",Promotion("SIEGE"));
Add("RECON","侦察单位（侦察兵等）","LAND",Promotion("RECON"));
Add("MONK","武僧","LAND",Promotion("MONK"));
Add("SUPPORT","全部支援单位","LAND",function(i) return i.FormationClass=="FORMATION_CLASS_SUPPORT"; end);
Add("MEDIC","医疗兵／补给车队","SUPPORT",Types("MEDIC","SUPPLY_CONVOY"));
Add("ENGINEER","军事工程师","SUPPORT",Types("MILITARY_ENGINEER"));
Add("SIEGE_SUPPORT","攻城锤／攻城塔","SUPPORT",Types("BATTERING_RAM","SIEGE_TOWER"));
Add("OBSERVATION","观测气球／无人机","SUPPORT",Types("OBSERVATION_BALLOON","DRONE"));
Add("ANTI_AIR","防空单位","SUPPORT",function(i) return (i.AntiAirCombat or 0)>0; end);
Add("SEA","海军","COMBAT",function(i) return Military(i) and i.Domain=="DOMAIN_SEA"; end);
Add("NAVAL_MELEE","海军近战","SEA",Promotion("NAVAL_MELEE"));
Add("NAVAL_RANGED","海军远程","SEA",Promotion("NAVAL_RANGED"));
Add("NAVAL_RAIDER","海军袭击／潜艇","SEA",Promotion("NAVAL_RAIDER"));
Add("NAVAL_CARRIER","航空母舰","SEA",Promotion("NAVAL_CARRIER"));
Add("AIR","空军","COMBAT",function(i) return Military(i) and i.Domain=="DOMAIN_AIR"; end);
Add("AIR_FIGHTER","战斗机","AIR",Promotion("AIR_FIGHTER"));
Add("AIR_BOMBER","轰炸机","AIR",Promotion("AIR_BOMBER"));
Add("CIVILIAN","非战斗单位","ALL",function(i) return not Military(i); end);
Add("BUILDER","建造者","CIVILIAN",Types("BUILDER"));
Add("SETTLER","开拓者","CIVILIAN",Types("SETTLER"));
Add("TRADER","商人","CIVILIAN",function(i) return i.MakeTradeRoute==true; end);
Add("SPY","间谍","CIVILIAN",function(i) return i.Spy==true; end);
Add("RELIGIOUS","宗教单位","CIVILIAN",function(i) return (i.ReligiousStrength or 0)>0 or (i.SpreadCharges or 0)>0; end);
Add("MISSIONARY","传教士","RELIGIOUS",Types("MISSIONARY"));
Add("APOSTLE","使徒","RELIGIOUS",Types("APOSTLE"));
Add("INQUISITOR","审判官","RELIGIOUS",Types("INQUISITOR"));
Add("GURU","上师","RELIGIOUS",Types("GURU"));
Add("NATURALIST","自然学家","CIVILIAN",Types("NATURALIST"));
Add("ROCK_BAND","摇滚乐队","CIVILIAN",Types("ROCK_BAND"));
Add("ARCHAEOLOGIST","考古学家","CIVILIAN",Types("ARCHAEOLOGIST"));
local greatTypes={};
for _,name in ipairs({"GENERAL","ADMIRAL","ENGINEER","MERCHANT","PROPHET","SCIENTIST","WRITER","ARTIST","MUSICIAN"}) do greatTypes["UNIT_GREAT_"..name]=true; end
Add("GREAT","全部伟人","ALL",function(i) return F.IsType(i,greatTypes); end);
for _,item in ipairs({{"GENERAL","大将军"},{"ADMIRAL","海军统帅"},{"ENGINEER","大工程师"},
  {"MERCHANT","大商人"},{"PROPHET","大预言家"},{"SCIENTIST","大科学家"},
  {"WRITER","大作家"},{"ARTIST","大艺术家"},{"MUSICIAN","大音乐家"}}) do
  Add("GREAT_"..item[1],item[2],"GREAT",Types("GREAT_"..item[1]));
end
-- Direct shortcuts for the two frequently used civilian categories.
F.Nodes.ALL.children={"COMBAT","GREAT","BUILDER","SETTLER","CIVILIAN"};
function F.Initialize()
  F.Replaces={};
  if GameInfo.UnitReplaces then
    for row in GameInfo.UnitReplaces() do F.Replaces[row.CivUniqueUnitType]=row.ReplacesUnitType; end
  end
  if GameInfo.GreatPersonClasses then
    for row in GameInfo.GreatPersonClasses() do greatTypes[row.UnitType]=true; end
  end
end
function F.Matches(id,info)
  local node=F.Nodes[id];
  if not info or not node or not node.match(info) then return false; end
  return not node.parent or F.Matches(node.parent,info);
end
