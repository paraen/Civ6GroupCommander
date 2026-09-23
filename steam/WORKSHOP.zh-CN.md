# 上传到 Steam 创意工坊（文明 VI）

本文件说明如何把这个模组发布到《文明 VI》的 Steam 创意工坊，以及首次发布与后续更新的区别。

- 可直接复制的标题／描述／更新说明：见 [workshop-text.zh-CN.md](workshop-text.zh-CN.md)
- 上传的**内容**就是本仓库的 `mod/GC_GroupCommander`（含 `.modinfo` 的那一层），不需要额外打包。

## 0. 上传前检查

1. 游戏内先自测一遍（本版测试重点见 [../TEST-p2.7.zh-CN.md](../TEST-p2.7.zh-CN.md)）——上传后玩家会立刻看到这个版本。
2. `Documents\My Games\Sid Meier's Civilization VI\Mods\GC_GroupCommander\` 下的文件与仓库 `mod/GC_GroupCommander` 一致（用 `tools/` 里的哈希对比或手动覆盖一次）。
3. `.modinfo` 里的 `<Name>`／`<Description>` 是玩家在「附加内容」里看到的文字，改这两个字段不需要重新上传，但改了就要重新上传一次才能生效。
4. 准备一张**预览图**（封面）：建议 512×512 或类似的 1:1 方图，PNG/JPG，尽量小于 1 MB。Steam 对图片尺寸／体积有上限，超限会直接报错。本仓库没有美术资源，请用你自己的游戏截图。

## 1. 安装开发工具

1. Steam → **库** → 左上角筛选下拉选 **工具**（Tools）。
2. 找到 **Sid Meier's Civilization VI Development Tools**，右键 → **安装**。
   - App ID 是 `404350`（类型：工具，仅 Windows）；想省一步可以直接打开一键安装链接：`steam://install/404350`
   - 这是官方开发工具包，内含 **ModBuddy、FireTuner、Steam Workshop Uploader**。
   - 会提示安装 Microsoft Visual Studio Shell；按提示装完再启动 SDK。
   - 另有约 20 GB 的 **Development Assets**（美术资源包），**只做美术/3D 才需要，本模组不需要装**。
3. 安装完成后，桌面会有 SDK 快捷方式。

## 2. 用 Steam Workshop Uploader 上传

1. **先启动 Steam 并保持登录**（上传器必须通过 Steam 账号识别作者身份），再启动 SDK。
2. 双击桌面 SDK 快捷方式 → 启动面板里选 **Steam Workshop Uploader**。
3. 点 **Begin**（开始）。
4. 点 **Upload**（上传）。
5. 在弹出的文件／文件夹选择框里，选择要发布的模组目录：

   ```text
   Documents\My Games\Sid Meier's Civilization VI\Mods\GC_GroupCommander
   ```

   也就是**含 `GC_GroupCommander.modinfo` 的那一层**（不要选到 `UI` 或 `Scripts`，也不要选上一级 `Mods`）。
6. 填写上传信息（草稿见 [workshop-text.zh-CN.md](workshop-text.zh-CN.md)）：
   - **Title**：`文明六群控 Group Commander`
     - 尽量短。若上传报错，先删掉括号、版本号、全角符号再试（标题过长/特殊字符会导致 Steam 报错）。
   - **Description**：粘贴草稿里的描述（Steam 描述框支持 BBCode，纯文本也能直接发布）。
   - **Tags**：从工具给出的列表里勾选相近项（例如 `Gameplay`、`UI`），不要自造标签。
   - **Preview image**：选第 0 步准备的那张图。
7. 点 **Upload** 执行上传，等待进度完成。
8. 第一次上传会**创建一个新的创意工坊条目**，工具会显示该条目的 **Workshop Item ID / 链接**，请记录到 [workshop-text.zh-CN.md](workshop-text.zh-CN.md) 和本仓库 `README.md` 里。
9. 打开 Steam 客户端 → 社区 → 创意工坊 → **你的作品**，把该条目的可见性从 **隐藏／私有** 改为 **公开（Public）**。新条目默认不是公开的，这一步不做，别人搜不到。

## 3. 以后更新版本（不要新建条目）

1. 改完代码，先把新文件复制到 `Documents\...\Mods\GC_GroupCommander\`，进游戏确认能用。
2. 再次打开 **Steam Workshop Uploader**，**选择同一个模组目录**上传。
3. 工具识别到该模组已有条目时，会**更新原条目**而不是新建；如工具给出「新建 / 更新」的选择，选**更新已有条目**，并确认显示的就是第 2 步记录的那个 Item ID。
4. 在描述里追加一条「更新说明」（草稿文件里有模板），保存。

> 判断标准：更新完成后，创意工坊页面右上角的「更新时间」会变化，而 URL 里的 `?id=` 数字不变。

## 4. 常见问题

| 现象 | 处理 |
| --- | --- |
| Uploader 里看不到／选不到本模组 | 确认选择的是 `Mods\GC_GroupCommander`（含 `.modinfo` 的那层）；确认 `.modinfo` 文件名与模组文件夹名一致；必要时重启上传器与 Steam。 |
| 上传报 Steam 错误、超时 | 标题改短（去掉括号/版本号/全角字符）、预览图缩小到 1 MB 以内或换 512×512；关闭 VPN/代理后重试；确认 Steam 已登录且在线。 |
| 上传成功但玩家订阅后没效果 | 确认条目可见性已改为公开；确认玩家的规则集是**风云变幻（Expansion2）**；确认游戏内「附加内容」里「文明六群控」是启用状态。 |
| 上传后游戏里还是旧行为 | 上传的是新文件但玩家未更新：让玩家在 Steam 客户端等待下载完成；本地测试时注意 `Documents\...\Mods` 下的副本会**优先于**创意工坊版本生效，两者同时存在时以本地副本为准。 |

## 5. 备注

- 本模组**不使用 ModBuddy 工程**（仓库里没有 `.civ6proj`）。如果当前版本的 Uploader 只接受 ModBuddy 工程，就新建一个空 ModBuddy 工程、把 `mod/GC_GroupCommander` 里的文件按原路径加入工程再上传；文件内容不需要改动。
- 上传过程中不要移动／改名 `mod/GC_GroupCommander` 里的文件，`.modinfo` 里的 `<Files>` 列表必须与磁盘上的文件一一对应。
