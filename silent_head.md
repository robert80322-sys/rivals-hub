# silent_head.lua —— 静默自瞄（本仓库实现搬过来的单文件版）

## 一、来源

不是从 kicia 反推，是照本仓库里已经跑通的三处实现原样搬：

| 参考 | 内容 |
|---|---|
| `espaim.lua:750-835` | `hookfunction(UseItem.FireServer)` → 改包里 4 个字段，视角不动 |
| `rage.lua:520-625` | 包结构：`\0` 起点在目标旁边、`\1` = head.CFrame、`\2` = head、`\3` = head 局部偏移；打的是 `Head` |
| `cases_opensource_ragebot.lua:420-445` | 开源 Ragebot 原版（Srilangish），上面两处的源头 |

kicia（`oreo-kicia-v9.lua:54339`）那条「用相机位置当起点、`\1` 写 lookAt」的路子在游戏里打不中，
所以这一版把这两处换成了上面开源实现的做法。

## 二、包长这样

```lua
data["\1"] = {
  ["\0"] = util:EncodeCFrame(CFrame.lookAt(起点, head.Position)), -- 起点 = head.Position + 随机 ±2 格
  ["\1"] = util:EncodeCFrame(head.CFrame),                        -- 目标的 CFrame，不是 lookAt
  ["\2"] = head,                                                  -- 目标部件（Head）
  ["\3"] = util:EncodeCFrame(head.CFrame:ToObjectSpace(CFrame.new(命中点))),
}
```

起点在目标头旁边 = 服务端的墙挡/距离校验都能过，所以隔墙也能中（`visibleOnly=false` 默认）。

## 三、和上一版（照 kicia 写的）的差别

1. 起点：相机位置 → **目标头旁边 ±2 格**
2. `\1`：`lookAt` → **`head.CFrame`**
3. 拦截：上值代理优先 → **`hookfunction(UseItem.FireServer)` 优先**，失败才退 `__namecall`、上值代理
4. 队友：只比 `TeamID` → **对局 `TeamID` / `Team` 对象 / 空串不算 / `PartyId` / 手动名单**
   （上一版在 FFA 里会把整屋子人当队友，一个目标都选不出来）
5. 命中部件：`HitboxHead` → **`Head`**（缺了才退 `HitboxHead` / `HitboxHeadSmall`）

## 四、参数（`getgenv().OreoSilentHead.cfg`）

| 键 | 默认 | 说明 |
|---|---|---|
| `enabled` | true | 常开；`.setEnabled(false)` 临时关 |
| `chance` | 100 | 每一发都改 |
| `fovRadius` | 420 | 屏幕像素半径（准心为中心） |
| `maxDist` | 600 | 和目标的最大距离 |
| `visibleOnly` | false | 起点在目标旁边，隔墙也能过；想只打看得见的改 true |
| `teamCheck` | true | 队友过滤 |
| `lead` | 0.06 | 提前量系数（× 目标速度），0 = 不预判 |
| `originJitter` | 2 | 起点随机偏移（格） |
| `hitJitter` | 0.1 | 命中点抖动（格） |
| `hud` | true | 左上角状态条 |

队友手动标记：`getgenv().OreoSilentAlly(userId, true)`

## 五、状态条 / 排错

```
SA ON | hook hookfunction | shots 12 | rew 9 | Enemy1 Head
```

| 读数 | 含意 |
|---|---|
| `hook none` | 三种拦截全失败（脚本会 warn 出原因） |
| `shots 0` | 没拦到 `UseItem` 包 |
| `rew 0` 且 `no target` | 选不出目标（FOV / 距离 / 队友判定） |
| 两个都涨但打不中 | 服务端这一版不认包里的弹道，得回到 desync（把身体挪到目标旁边）那条路，见 `rage.lua` |

`.status()` / `.unload()` 随时可用。

## 六、验证

`mock/mock_v2_test.lua`（Lua 5.1 假装 Roblox）跑通：
拦截（上值路径）→ 选人（跳过队友）→ 改包（`\0` 落在头 3 格内、`\1` = 头坐标、`\3` 是局部小偏移、`\2` = 头部件）
→ 非射击包不动 → 关开关不改 → 没目标不改并计数 → `unload()` 还原。
