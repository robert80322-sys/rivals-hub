# Rivals Hub

Roblox **Rivals** 的客户端脚本，面向**手机执行器**（Delta / Codex / Fluxus / Hydrogen）。
单文件、无外部依赖、不需要 key。

## 三个入口，挑一个

| 入口 | 内容 | 适合 |
|---|---|---|
| `loader.lua` | 多镜像兜底 → 加载 `main.lua` | 日常（GitHub 直连抽风时自动换源） |
| `main.lua` | 手枪版本体，一个面板全搞定 | 只想轻量用 |
| `all.lua` | 先拉 Kicia 全套（含 ragebot）再拉本 hub | 想要完整功能 |

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
| 视角 | 第三人称、相机 FOV 覆盖、击中音效 |
| 移动 | 加速、超级跳 |
| 传送 | 贴人 TP（最近/随机、站背后/头顶、贴上就开火）、立即贴一次、记录点 / 回记录点、自动重生 |

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

## 已知限制

- `静默·官方接口` 依赖 `Modules.Utility` 的 `EncodeCameraRotation` 存在；游戏更新后如果改名，状态栏会显示「原生 未接」，此时退回 `静默·Hook`。
- 第三人称是把相机往后推，和游戏自带的第一人称动画会打架，打枪手感会飘，建议只在赶路/看人时开。
- 贴人 TP 每 0.15 秒 `PivotTo` 一次，服务端可能把你拉回，尤其是隔着半张地图跳的时候。
- Kicia 全套和本 hub **不要同时开自瞄**：它 hook 的是同一批远程和相机，会互相覆盖。
- `vendor/kicia.lua` 2.1 MB，手机执行器拉取要十几秒，第一次载入会卡一下，正常。

## 免责

Roblox 对客户端注入有封号风险，开小号测，主号别碰。
