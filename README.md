# Rivals Hub

Roblox **Rivals** 的客户端脚本，面向**手机执行器**（Delta / Codex / Fluxus / Hydrogen）。
单文件、无外部依赖、不需要 key。

## 三个入口，挑一个

| 入口 | 内容 | 适合 |
|---|---|---|
| `loader.lua` | 多镜像兜底 → 加载 `main.lua` | 日常（GitHub 直连抽风时自动换源） |
| `main.lua` | 手枪版本体，一个面板全搞定 | 只想轻量用 |
| `all.lua` | 先拉 Kicia 全套（含 ragebot）再拉本 hub | 想要完整功能 |
| `rage.lua` | **独立三键版**：TP / AIM / RAGE，无面板 | 只要这三件事 |

```lua
-- 日常
loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/loader.lua"))()
-- 全套
loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/all.lua"))()
```

进游戏后左上角出现圆形 **R**，点开是面板；右侧有红色 **AIM** 和青色 **TP** 两个触屏键。

## 功能

| 分组 | 功能 |
|---|---|
| 识别 | ESP 透视（框/名字/血量/距离）、队友过滤、只锁可见目标 |
| 瞄准 | 自瞄（平滑/FOV 可调）、自动开火 Trigger、**命中盒瞄准** |
| 静默 | `静默·官方接口`：给 `Remotes.Replication.Fighter.UpdateCameraRotation` 发编码视角，服务端按它判定，本地画面不动 |
| | `静默·Hook`：hook `workspace.Raycast` 的备选方案 |
| 视角 | 第三人称、相机 FOV 覆盖、击中音效、**陀螺仪**（姿态微调视角，灵敏度/双向可调） |
| 按键 | AIM / TP / BHOP 三个触屏键，位置和大小全在面板里调（不用拖） |
| 移动 | 连跳 BHOP（按住键，或开「自动连跳」免按） |
| 外观 | **Skinchanger**：独立面板列出游戏皮肤，点一下本地换手持武器外观 |
| 移动 | 加速、超级跳 |
| 传送 | 贴人 TP（最近/随机、站背后/头顶、贴上就开火）、立即贴一次、记录点 / 回记录点、自动重生 |

## rage.lua · 三个键

独立文件，不依赖 main.lua，也没有面板 —— 就屏幕右侧三个键，按住生效：

| 键 | 行为 |
|---|---|
| **SILENT**（紫，左侧） | 静默：视角一点不动，只把朝向用 `UpdateCameraRotation` 发给服务端，它按这个判定你的枪口方向 |
| **SPREAD**（蓝，左侧） | 无扩散：每 0.2 秒把当前武器 `Info` 里的 `Spread / HipSpread / AimSpread / MinSpread / MaxSpread` 清零 |
| **TEAM**（绿） | **队友识别开关**：亮着 = TP/AIM/RAGE 三个键都排掉队友、不 TP 到队友身上；按一下变 `ALL` = 谁都打 |
| **TP**（青） | **按住**：每 0.12 秒 `PivotTo` 到最近敌人身边 **1 米**，松手即停。超过 `tpMaxDist`（默认 120 studs，约一个竞技场跨度）不传，状态栏会写「目标超出 TP 距离」 |
| **AIM**（红） | **点一下开、再点关**：暴力锁头，**360° 无死角**（不做 FOV 过滤），射线判断遮挡，头被墙挡住自动改打身体 |
| **RAGE**（橙） | **点一下开、再点关**。穿墙照 Kicia 的 HitscanStrategy 做：**包里的起点不用自己站的位置，改用 `standPos`（目标位置 + 远离方向 × reach + 腰高）**，配合 `sethiddenproperty(root,"PhysicsRepRootRef",目标命中盒)` 让服务端认可这个位置。身体走 `setthreadidentity(8)` 直接写 CFrame，不走 `PivotTo`，所以不会被墙挡；关掉时恢复复制根并回原位 |

左边有个 **⚙** 按钮，点开是「按键位置」面板：四个键各自的 **右边距 / 垂直 / 大小**，`+/-` 调完立刻生效，
自动存到执行器的 `RivalsRageCfg.json`，下次加载自动读回。不用拖，手机上拖动会跟游戏手势打架。

RAGE 的包结构是照 Kicia 反编译出来的原始布局抄的：

```lua
shot = {
  [utf8.char(0)] = EncodeCFrame(startCF),
  [utf8.char(1)] = EncodeCFrame(endCF),
  [utf8.char(2)] = part,          -- 目标 HitboxHead/HitboxBody
  [utf8.char(3)] = EncodeCFrame(CFrame.Angles(0, math.pi/2, 0)),
}
```

左下角有个状态条，显示三键状态 + 原生接口是否接上 + 每次 RAGE 的结果（发包失败会写原因）。
卸载：执行器里 `getgenv().RageLiteUnload()`。

## Kicia 全套（ragebot 在这）

`vendor/kicia.lua` 是 Kicia Rebuild / LxYHook v3 的完整重编译版（2.1 MB，7.3 万行），
包含 ragebot（KH / UE / Careful 三种风格）、物品修改器（后坐力、扩散、射速、蓄力）、
自动排队 / 投票 / 装备、Hacker 检测、玩家信息伪造等全套功能。

两种用它的方式：

1. **一键**：面板最底下 `⚡ 载入 Kicia 全套`，点一下就从本仓库拉下来跑，再点 `⏏ 卸载` 收掉。
   hub 会自动关掉自己的自瞄 / 静默 / 贴人 —— 两套一起开会抢相机。
2. **走 `all.lua`**：开机就是两套都装好。

它是第三方重编译版本，更新靠上游；本仓库只是存放 + 一键加载，没改过它。

## 从 Kicia / LxYHook 里扒出来的东西

这些是 Rivals 真实使用的接口，不是猜的：

```
ReplicatedStorage.Remotes.Replication.Fighter.UpdateCameraRotation   -- 视角同步（静默瞄准走这里）
ReplicatedStorage.Remotes.Replication.Fighter.UseItem                -- 使用武器 / 换弹
ReplicatedStorage.Remotes.Replication.Fighter.UpdateState
ReplicatedStorage.Remotes.Duels.RespawnNow                           -- 立即重生
ReplicatedStorage.Modules.Utility        : EncodeCameraRotation      -- 视角编码器（游戏自带）
ReplicatedStorage.Modules.EnumLibrary    : ToEnum
```

判定盒是角色下的 `HitboxHead` / `HitboxBody`（还有 `*Small` 版本），**不是** `Head` / `HumanoidRootPart`。
本脚本的透视框、自瞄、静默全部走命中盒，所以框和实际判定对齐。

## 皮肤修改器（Skinchanger）

面板「外观 → 🎨 打开皮肤列表」，弹出一个带搜索框的独立窗口，列出 `ReplicatedStorage.Modules.CosmeticLibrary`
里所有带图标的皮肤。点一项就本地重建手持 viewmodel（照 Kicia 的 `ApplyLive` 做法：复制 `_serial`、
写 `Data.Skin/Name`、用 `ClientViewModel.new` 建新的、替换 `item.ViewModel`），只改自己画面。

- 需要 **先进一局**（大厅里读不到 fighter 的 items）
- 失败会直接在面板底部写原因（缺模块 / 没手持武器 / viewmodel 结构变了）
- 「↩ 换回原皮肤」回到第一次换之前的那个

## 手机适配情况

两套都是触屏可用的，但来路不同：

| | 本 hub (`main.lua`) | Kicia 全套 (`vendor/kicia.lua`) |
|---|---|---|
| 菜单怎么开 | 左上角圆球 **R** | 屏幕右侧悬浮菜单按钮 |
| 面板 | 单列滚动，高度按屏幕 62% 自适应（300–460px） | 自带三种布局，检测到触屏自动切手机版 |
| 控件尺寸 | 行高 33px、按钮 30×26、TP/AIM 圆键 76/94px | 手机布局 Row 40、Button 36（源码里的 `IsCompact` 表） |
| 需要键盘 | 不需要 | 不需要（键位绑定是可选项，不绑也能用） |
| 拖动 | 标题栏拖动、圆球可拖 | 窗口标题拖动 |

第一次进游戏如果看不到某个菜单，先确认是不是被另一个的 UI 盖住 —— 两个都挂在 `CoreGui` 且层高，我的 `DisplayOrder` 是 2147483647。

## 改参数

面板里的开关会自动存进执行器的 `RivalsCFG_v4.json`，下次执行自动读回。
想改默认值，直接搜 `local CFG = {` 那一段。

## 多指 / 鼠标指针问题

Roblox 手机端本身支持多指（左手摇杆 + 右手转视角）。如果屏幕上突然冒出一个**鼠标指针**并跟着手指乱飘，是执行器用 `mouse1press` / `VirtualInputManager:SendMouseButtonEvent` 模拟开火时，把客户端切进了鼠标输入模式。

本脚本 v7.4 起默认**不在触屏设备上发任何鼠标事件**（`CFG.mouseSim = false`），代价是「自动开火 / 贴人开火」在手机上不会真的扣扳机，只做瞄准。想用就在面板里打开 `鼠标模拟开火`，指针会回来。

如果关掉之后还有指针，那是执行器自带的虚拟鼠标 —— 去 Delta/Codex 的设置里找 mouse / cursor 相关开关关掉。

## 已知限制

- `静默·官方接口` 依赖 `Modules.Utility` 的 `EncodeCameraRotation` 存在；游戏更新后如果改名，状态栏会显示「原生 未接」，此时退回 `静默·Hook`。
- 第三人称是把相机往后推，和游戏自带的第一人称动画会打架，打枪手感会飘，建议只在赶路/看人时开。
- 贴人 TP 每 0.15 秒 `PivotTo` 一次，服务端可能把你拉回，尤其是隔着半张地图跳的时候。
- Kicia 全套和本 hub **不要同时开自瞄**：它 hook 的是同一批远程和相机，会互相覆盖。
- `vendor/kicia.lua` 2.1 MB，手机执行器拉取要十几秒，第一次载入会卡一下，正常。

## 免责

Roblox 对客户端注入有封号风险，开小号测，主号别碰。
