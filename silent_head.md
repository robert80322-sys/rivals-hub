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
| `fovRadius` | `math.huge` | 屏幕像素半径（准心为中心），无限 = 屏幕上谁近锁谁 |
| `maxDist` | `math.huge` | 和目标的最大距离（格），无限 = 全图 |
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

## 七、v3：desync + 自己发（追 100%）

v2 只改包、不等位置同步，所以服务端按「它看到的你」算射线时经常不认 → 命中率上不去。
v3 照 `rage.lua` 的做法补两步：

1. **desync**：开火瞬间把 `HumanoidRootPart` 挪到目标旁边（3~5 格），服务端随后收到的
   复制位置就是「你贴着他」，起点/距离/墙挡校验都能过；`desyncHold` 后还原，视角不动。
2. **selfFire**：拦下游戏自己那发，`selfFireDelay`（默认 40ms，约 2 帧）后由我们用原始
   `FireServer` 重发同一个包 —— 位置更新先到、弹道后到，消掉那个 race。

| `desync` | `selfFire` | 行为 |
|---|---|---|
| true | true | 默认。贴身 + 等两帧再发 |
| true | false | 贴身但立即发（还有 race，但比 v2 强） |
| false | false | 等于 v2（纯改包） |

状态条：`shots / rew / ds / sf` 四个计数 —— `ds` 是挪了几次身体，`sf` 是自己发了几发。
若出现「一发都不中」：先 `cfg.desync=false; cfg.selfFire=false` 退回 v2 行为，
把状态条和 Console 发我；`desyncMaxDist`（默认 60）之外不会挪身体，属于预期。

## 八、范围怎么调

| 想要的感觉 | `fovRadius`（像素） | `maxDist`（格） |
|---|---|---|
| 贴脸才锁 | 120 | 80 |
| 默认（不限距离 / 不限角度） | `math.huge` | `math.huge` |
| 全屏乱锁 | 420 | 600 |
| 不限角度（只看距离） | `fovEnabled = false` | 自己定 |

改完立刻生效，不用重载：

```lua
local A = getgenv().OreoSilentHead
A.cfg.fovRadius = 140
A.cfg.maxDist = 120
```

注意现在真正卡住远距离命中的是 `desyncMaxDist`（默认 60）：超过 60 格不挂复制根，
那几发就退回「只改包」，服务端可能不认 → 打得中但会漏。
想连远距离也贴身：`A.cfg.desyncMaxDist = 300`（越大越容易被服务端拽回去，自己试）。

## 九、v4：不瞬移的「贴身」

上一版是把 `HumanoidRootPart` 真的挪到目标旁边，别人看得到瞬移。v4 换成 `rage.lua` 里的
**物理复制根**：只把 `PhysicsRepRootRef` 指到目标命中盒上，服务端算射线/距离时用这个根，
你自己的角色模型、相机、动作全都不动 —— 外面看不到任何位移。

| `positionSpoof` | 行为 | 可见性 |
|---|---|---|
| `reproot`（默认） | 只写 `PhysicsRepRootRef`，`repRootHold` 后摘掉 | 看不见 |
| `body` | 真的挪 `HumanoidRootPart`（旧版） | 会瞬移 |
| `none` | 只在包里写起点（v2） | 看不见，但命中率低 |

状态条 `rp` = 复制根写成功的次数。`rp` 一直是 0 说明执行器没有
`sethiddenproperty` 也没有 `setthreadidentity`，那会自动退回 `none` 行为（不会瞬移，但也不再贴身）。

```lua
local A = getgenv().OreoSilentHead
A.cfg.positionSpoof = "reproot"  -- 默认
A.cfg.repRootHold = 0.08         -- 复制根挂多久（秒）
```

## 十、v5：hybrid（一帧挪身体，自己看不见）

v4 只挂复制根，实测「经常打不中」——复制根要么没被服务端采用，要么比包晚到。
v5 回到 kicia ragebot 的做法，但把可见位移压到**一帧**：

1. 开火那一帧：`HumanoidRootPart` 挪到目标旁边（4~7 格），同时挂 `PhysicsRepRootRef`
2. **下一帧 RenderStepped（渲染之前）立刻还原** —— 你自己画面里看不到位移，服务端那一帧收到的位置是贴着目标的
3. 包立即发（`selfFire=false`），复制根 `repRootHold` 后摘掉

| `positionSpoof` | 行为 |
|---|---|
| `hybrid`（默认） | 复制根 + 一帧身体，自己看不见 |
| `reproot` | 只挂复制根（v4，命中率偏低） |
| `body` | 挪 50ms（会看到瞬移，v3） |
| `none` | 只改包（v2） |

`selfFire` 默认改成 `false`：hybrid 靠「身体那一帧」让服务端认位置，包必须立刻发出去；
想用 `reproot` 时可以把它设回 `true`（等 `selfFireDelay` 再发）。

其它默认：`desyncMaxDist=300`、`repRootHold=0.12`、`hitJitter=0.05`、`lead=0.04`。
