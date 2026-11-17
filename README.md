# Rivals Hub

Roblox **Rivals** 的客户端脚本，面向**手机执行器**（Delta / Codex / Fluxus / Hydrogen）。
单文件、无外部依赖、不需要 key。

## 一行加载

把 `loader.lua` 里的 `YOUR_NAME` 改成你的 GitHub 用户名并推送后：

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/你的名字/rivals-hub/main/loader.lua"))()
```

不想走镜像就直连正文：

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/你的名字/rivals-hub/main/main.lua"))()
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

## 改参数

面板里的开关会自动存进执行器的 `RivalsCFG_v4.json`，下次执行自动读回。
想改默认值，直接搜 `local CFG = {` 那一段。

## 已知限制

- `静默·官方接口` 依赖 `Modules.Utility` 的 `EncodeCameraRotation` 存在；游戏更新后如果改名，状态栏会显示「原生 未接」，此时退回 `静默·Hook`。
- 第三人称是把相机往后推，和游戏自带的第一人称动画会打架，打枪手感会飘，建议只在赶路/看人时开。
- 贴人 TP 每 0.15 秒 `PivotTo` 一次，服务端可能把你拉回，尤其是隔着半张地图跳的时候。

## 免责

Roblox 对客户端注入有封号风险，开小号测，主号别碰。
