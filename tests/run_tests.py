from pathlib import Path
import sys
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / '.test-deps'))
from lupa import LuaRuntime

mod = root / 'mod' / 'GC_GroupCommander'
manifest = ET.parse(mod / 'GC_GroupCommander.modinfo').getroot()
ui = ET.parse(mod / 'UI' / 'GC_LoadProbe.xml')
control_ids = {item.attrib['ID'] for item in ui.iter() if 'ID' in item.attrib}
for item in manifest.findall('./Files/File'):
    assert (mod / item.text).is_file(), item.text
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval('function(source, name) local f,e=load(source,name); assert(f,e); return true end')
for path in sorted(mod.rglob('*.lua')):
    compile_lua(path.read_text(encoding='utf-8-sig'), path.name)
    print('Syntax OK:', path.name)
    if path.name in ('GC_LoadProbe.lua', 'GC_Selection.lua'):
        refs = set(re.findall(r'Controls\.([A-Za-z_][A-Za-z_0-9]*)', path.read_text(encoding='utf-8-sig')))
        assert refs <= control_ids, f'Missing UI controls: {refs - control_ids}'
lua.execute((mod / 'UI' / 'GC_Rally.lua').read_text(encoding='utf-8-sig'))
lua.execute((root / 'tests' / 'rally_cases.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_Filters.lua').read_text(encoding='utf-8-sig'))
lua.execute((root / 'tests' / 'filter_cases.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_Attack.lua').read_text(encoding='utf-8-sig'))
lua.execute((root / 'tests' / 'attack_cases.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_March.lua').read_text(encoding='utf-8-sig'))
lua.execute((root / 'tests' / 'march_cases.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_Pursuit.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_Auto.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod / 'UI' / 'GC_Selection.lua').read_text(encoding='utf-8-sig'))
lua.execute((root / 'tests' / 'selection_cases.lua').read_text(encoding='utf-8-sig'))
lua.globals().GC_TestFlagsSource = (mod / 'UI' / 'GC_UnitFlags.lua').read_text(encoding='utf-8-sig')
lua.execute((root / 'tests' / 'flag_cases.lua').read_text(encoding='utf-8-sig'))
lua.globals().GC_TestInputSource = (mod / 'UI' / 'GC_WorldInput.lua').read_text(encoding='utf-8-sig')
lua.execute((root / 'tests' / 'input_cases.lua').read_text(encoding='utf-8-sig'))
lua.globals().GC_TestSaveSource = (mod / 'Scripts' / 'GC_Save.lua').read_text(encoding='utf-8-sig')
lua.execute((root / 'tests' / 'save_cases.lua').read_text(encoding='utf-8-sig'))
tactics = LuaRuntime(unpack_returned_tuples=True)
for name in ('GC_Rally', 'GC_Attack', 'GC_March', 'GC_Pursuit', 'GC_Auto'):
    tactics.execute((mod / 'UI' / (name + '.lua')).read_text(encoding='utf-8-sig'))
tactics.execute((root / 'tests' / 'tactics_cases.lua').read_text(encoding='utf-8-sig'))
print('Manifest/XML and Lua tests passed. Game engine integration still requires live testing.')
