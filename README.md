# 文明六群控 · Group Commander（Civilization VI Mod）

**把「一个单位一个单位点」变成「框选一批 → 右键预览 → 一键执行」。**

当前构建：**20260923-p2.7**（测试版）

| 文档 | 内容 |
| --- | --- |
| [README.zh-CN.md](README.zh-CN.md) | 当前版本行为说明 |
| [HANDOFF.zh-CN.md](HANDOFF.zh-CN.md) | 安装状态与开发交接记录 |
| [PLAN.zh-CN.md](PLAN.zh-CN.md) · [AUDIT.zh-CN.md](AUDIT.zh-CN.md) | 设计计划与实现前自检 |
| [TEST-*.zh-CN.md](TEST-p2.7.zh-CN.md) | 各版本实机测试步骤 |
| [steam/WORKSHOP.zh-CN.md](steam/WORKSHOP.zh-CN.md) | 创意工坊上传流程与本仓库文案草稿 |

## 功能

- **选取**：屏幕框选，或双击选中屏幕内同兵种；`Shift` 追加。也可点单位旗帜。
- **筛选**：军种（陆军／海军／空军／侦察）、医疗支援、非战斗单位、建造者、开拓者、九类伟人分层筛选。带 `>` 的父类只浏览，点「选用此类全部单位」才应用。
- **集结**：右键预览落点，再点执行按钮；目标格被友军占用时在附近寻找合法落点。
- **协同进攻**：右键已交战的可见城外敌军 →「开始协同进攻」。锁定同一敌军身份，跨回合继续；每回合重查可见位置与合法路径，目标死亡／失去视野／外交变化即停止。
- **持续行军**：指定远处空地后跨回合自动续走，允许对未探索／不可见的目标格下令（不自动开战）。
- **剩余移动力自动等待**：本回合队列执行完但仍有移动力、又无合法落点时，自动调用原生「跳过本回合」，任务保留，下回合继续。
- **可选闲置自动交战**（默认关闭，读档后需重新开启）：只处理己方闲置清醒的陆地战斗单位，用原生攻击预测决定攻击／避让／待命。
- **诊断**：面板可展开，显示构建号、状态与执行结果；日志统一前缀 `[GC]`。

## 安装

### 方式一：Steam 创意工坊（推荐给玩家）

订阅创意工坊页面即可。

> 创意工坊链接：**（页面发布后回填这里）**

### 方式二：手动安装（推荐给开发者 / 未发布时）

1. 下载本仓库（`Code` → `Download ZIP`）或 `git clone`。
2. 把 **`mod/GC_GroupCommander` 整个文件夹**复制到：

   ```text
   Documents\My Games\Sid Meier's Civilization VI\Mods\
   ```

   安装后路径必须是：

   ```text
   ...\Mods\GC_GroupCommander\GC_GroupCommander.modinfo
   ```

   （`.modinfo` 必须在 `Mods\<模组名>\` 这一层，不能再多套一层目录。）
3. 启动游戏 →「附加内容」→ 启用 **文明六群控** → 开始单人游戏。

## 兼容性

- 需要《文明 VI》+ **《风云变幻》Gathering Storm**（`.modinfo` 里的 `ActionCriteria` 要求 `Expansion2` 规则集）。
- 单人游戏。**联机未适配。**
- 通过 `ReplaceUIScript` 替换 `WorldInput` 与 `UnitFlagManager`；与同样替换这些上下文／脚本的 UI Mod 可能冲突。
- 未适配：海空完整接敌移动、城市攻击、链接护送、平民护送。
- 本机 `Documents\...\Mods\` 下若同时启用更早的 `Commander` 等旧版模组，属不同 Mod ID，不会互相覆盖，但同期启用可能互相干扰，建议只留一个。

## 使用

面板从上到下分三段：**01 选取单位 → 02 筛选类别 → 03 下达命令（右键预览后执行）**，诊断默认收起。

- 「单位群控」按钮开启／关闭群控模式，`Esc` 退出。
- 右键只做预览，必须点按钮才真正下令。
- 「停止全部命令」停止行军与协同进攻并关闭自动交战；关闭群控、`Esc`、清除选择、切换筛选**不会**停止已执行的任务。

## 已知限制（请按测试版对待）

- p2.6–p2.7 的自动交战、协同进攻新版火力分配、剩余移动力自动等待等行为**离线回归通过，但实机效果仍在验收中**。
- 普通持续行军才有存档支持；协同进攻不跨读档恢复。真实读档恢复／清空仍待完整实测。
- 海空完整接敌移动、城市攻击、链接护送、联机均未适配；普通行军限陆地。
- 离线模拟结果不能代替游戏内体验。

## 开发与测试

本仓库**不使用 ModBuddy 工程**：`mod/GC_GroupCommander` 就是可直接放进 `Mods` 目录的成品包，`.modinfo` 已经是成品声明。

```powershell
# 离线回归（需要真 Lua 运行时 lupa）
python -m pip install --target .test-deps lupa    # 已安装可跳过
python tests\run_tests.py
```

覆盖：集结／筛选／攻击／行军／追击／自动交战场景、输入与旗帜回调、存档桥，以及全部 Lua 语法 + `.modinfo`/XML 检查。

> 注意：`.test-deps/lupa` 内的扩展模块是 **CPython 3.12 (win_amd64)**。用其它 Python 版本（例如 3.14）运行会报 `ModuleNotFoundError: No module named 'lupa.lua55'`，此时请用 Python 3.12 运行，或针对本机 Python 版本重新执行上面的 pip 安装。

读取游戏日志中的本 Mod 记录：

```powershell
powershell -File tools\Read-TestReport.ps1
```

## 目录结构

```text
Civ6GroupCommander/
├─ mod/GC_GroupCommander/        ← 成品模组（装进 Mods 目录 / 上传创意工坊的就是这一层）
│  ├─ GC_GroupCommander.modinfo
│  ├─ Scripts/GC_Save.lua         (存档桥，Gameplay 上下文)
│  └─ UI/                         (GC_*.lua, GC_LoadProbe.xml)
├─ tests/                        ← 离线 Lua 场景与 run_tests.py
├─ tools/Read-TestReport.ps1     ← 游戏日志过滤
├─ steam/                        ← 创意工坊上传说明与文案草稿
├─ GC-*.zip                      ← 历史源码快照（每次大改动前的备份，可忽略）
└─ *.zh-CN.md                    ← 版本说明 / 交接 / 计划 / 审计 / 测试步骤
```

## 作者

- 作者：**Group Commander Project**（panzhen）
- 源码仓库：<https://github.com/paraen/Civ6GroupCommander>
- 问题反馈：GitHub Issues

## 许可

[MIT](LICENSE)。

游戏本体及其代码、素材版权归 Firaxis Games / 2K 所有。本项目仅通过官方模组接口（`.modinfo`、`ReplaceUIScript`、`ImportFiles`、`LuaEvents`、`Player:SetProperty`）工作，**不包含**游戏原始代码或素材。
