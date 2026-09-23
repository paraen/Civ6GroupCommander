local F=GC_Filters;
local function Info(name,domain,promotion,combat,formation)
  return {UnitType="UNIT_"..name,Domain="DOMAIN_"..domain,PromotionClass="PROMOTION_CLASS_"..(promotion or ""),
    Combat=combat or 0,FormationClass="FORMATION_CLASS_"..(formation or "CIVILIAN")};
end
local cases={
  {Info("SCOUT","LAND","RECON",10,"LAND_COMBAT"),{"ALL","COMBAT","LAND","RECON"},{"MELEE","CIVILIAN"}},
  {Info("RANGER","LAND","RECON",45,"LAND_COMBAT"),{"RECON","LAND"},{"MELEE","RANGED"}},
  {Info("WARRIOR","LAND","MELEE",20,"LAND_COMBAT"),{"ALL","COMBAT","LAND","MELEE"},{"CIVILIAN","RANGED","SEA"}},
  {Info("ROMAN_LEGION","LAND","MELEE",40,"LAND_COMBAT"),{"MELEE"},{"BUILDER"}},
  {Info("HORSEMAN","LAND","LIGHT_CAVALRY",36,"LAND_COMBAT"),{"CAVALRY","LIGHT_CAVALRY"},{"HEAVY_CAVALRY","ANTI_CAVALRY"}},
  {Info("MEDIC","LAND","SUPPORT",0,"SUPPORT"),{"MEDIC","LAND","COMBAT","SUPPORT"},{"CIVILIAN","MELEE"}},
  {Info("SUPPLY_CONVOY","LAND","SUPPORT",0,"SUPPORT"),{"MEDIC"},{"BUILDER"}},
  {Info("OBSERVATION_BALLOON","LAND","SUPPORT",0,"SUPPORT"),{"OBSERVATION","LAND"},{"AIR"}},
  {Info("SUBMARINE","SEA","NAVAL_RAIDER",60,"NAVAL"),{"SEA","NAVAL_RAIDER","COMBAT"},{"LAND","CIVILIAN"}},
  {Info("JET_FIGHTER","AIR","AIR_FIGHTER",100,"AIR"),{"AIR","AIR_FIGHTER"},{"AIR_BOMBER","LAND"}},
  {Info("JET_BOMBER","AIR","AIR_BOMBER",80,"AIR"),{"AIR","AIR_BOMBER"},{"AIR_FIGHTER"}},
  {Info("BUILDER","LAND"),{"ALL","CIVILIAN","BUILDER"},{"COMBAT","SETTLER"}},
  {Info("SETTLER","LAND"),{"SETTLER","CIVILIAN"},{"BUILDER"}},
  {Info("GREAT_SCIENTIST","LAND"),{"GREAT","GREAT_SCIENTIST","CIVILIAN"},{"COMBAT","GREAT_ENGINEER"}},
  {Info("GREAT_ADMIRAL","SEA"),{"GREAT","GREAT_ADMIRAL","CIVILIAN"},{"COMBAT","SEA"}},
};
for _,c in ipairs(cases) do
  for _,id in ipairs(c[2]) do assert(F.Matches(id,c[1]),id.." must include "..c[1].UnitType); end
  for _,id in ipairs(c[3]) do assert(not F.Matches(id,c[1]),id.." must exclude "..c[1].UnitType); end
end
F.Replaces.UNIT_UNIQUE_BUILDER="UNIT_BUILDER";
assert(F.Matches("BUILDER",Info("UNIQUE_BUILDER","LAND")));
for id,node in pairs(F.Nodes) do
  assert(#node.children+1<=15,"menu overflow: "..id);
  for _,child in ipairs(node.children) do assert(F.Nodes[child]); end
end
assert(not F.Matches("ALL",nil));
print("FILTER TESTS PASSED: "..#cases.." classification cases plus replacement/menu checks");
