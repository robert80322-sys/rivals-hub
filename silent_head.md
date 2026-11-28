# OREO 静默自瞄 · 分析与单独移植

## 一、原版是怎么跑的

入口 `oreo_v9.lua`（1192 B）只做三件事：三个镜像轮询拉 `oreo-kicia-v9.lua`（2.11 MB）、
`loadstring`、`pcall` 执行。真正的逻辑全在 2.11 MB 那一份里（Kicia Rebuild，65k+ 行）。

静默自瞄在里面的链路是四段，全部能在这份源码里对上：

| 段 | 做什么 | 位置（kicia_v9.lua 行号） |
|---|---|---|
| 选人 | 每帧跑 provider：敌人 → 命中盒（HitboxHead / HitboxBody / Small 两套）→ 屏幕空间 FOV 度量 → 取离准心最近的 | 25490–25625、30217、54166–54260 |
| 条件 | 存活 / 敌我 / 可见（从原点向命中盒打射线，命中自己这一支才算可见）、FOV、护盾与格挡 | 29235–29276 |
| 触发 | `SilentAim.ActivationChance / 100 >= math.random()`，默认 100 | 54352 |
| 改包 | 拦截 `StartShooting`，把包里 4 个字段重写 | 54339–54390 |
| 发出去 | 游戏自己的 `ClientItem.Input` → `UseItem:FireServer` | 31021–31170 |

关键在于**没有用任何 namecall 钩子**：原版把 `ReplicatedStorage` 这个上值从
`ClientItem.Input` 里换成了代理表，于是游戏自己那句
`ReplicatedStorage.Remotes.Replication.Fighter.UseItem:FireServer(...)` 就落到它的
包装函数上（`dm._Load`，31021–31170）。这样连执行器的 `hookfunction` / `newcclosure`
都不需要，只用 `debug.getupvalues` + 表赋值。

### 射击包长什么样

`UseItem:FireServer(objectId, 枚举, 外层表)`，外层表 `["\1"]` 里才是弹道：

```lua
{
  ["\0"] = {x, y, z, rx, ry, rz},  -- 起点 CFrame
  ["\1"] = {x, y, z, rx, ry, rz},  -- 起点 CFrame(2)，近战是 c0 前移 0.1 格
  ["\2"] = BasePart,               -- 命中部件（服务端只认 Hitbox 部件）
  ["\3"] = {x, y, z, 0, 0, 0},     -- 命中点在部件局部空间的位置
}
```

原版改写就是：`CFrame.lookAt(起点, 目标点)` 写回 `"\0"`/`"\1"`，`"\2"` 写成选中命中盒，
`"\3"` 用「从起点朝部件打一条 Include 射线 → 命中点 → `part.CFrame:PointToObjectSpace`」。

## 二、移植版做了什么

成品：`silent_head.lua`（923 行，含注释；纯 Lua，`loadstring` 直接跑）。

- **只留静默自瞄**，不加载 UI / 其余 60 多个模块，也不需要那 2.11 MB。
- **常开**：加载即生效，无菜单、无按键。
- **100%**：`chance = 100`，不掷骰子；反应/切换延迟一律 0。
- **只打头**：命中盒固定 `HitboxHead`，狙击职业回退 `HitboxHeadSmall`；两者都没有就不改包
  （服务端不认视觉 `Head`，见原版 65889 行注释）。
- **完整移植**（不是阉割）：
  - 目标遍历 / 敌我判定（`TeamID` 属性优先，回退 `Player.Team`，原版 65712）
  - 屏幕空间 FOV 度量 + 「离准心最近」选择
  - 可见性射线（Exclude 本机与目标角色，命中世界几何即算被挡）
  - `Manipulate` 环采样（不可见时沿视线推进 + 9.9 格环采样找有视线的发射原点），默认关
  - 4 字段包改写 + 局部命中点射线（原版 `cO`）
  - CFrame 编解码：优先游戏自己的 `Utility:EncodeCFrame`，格式不符再走本地实现
  - 枚举名解析：`EnumLibrary._from_enum[枚举]`，拿不到就靠包结构判断
- **三种拦截，自动挑能用的**（原版只有一种）：
  1. Instance 元表 `__namecall`（带自检：钩子必须被调用且转发不能炸，否则自动还原）
  2. `hookfunction(remote.FireServer, ...)`
  3. 原版同款：`ClientItem.Input` 的 `ReplicatedStorage` 上值 → 代理表（代理是惰性的，
     `.Remotes` 之外的东西全部落回真实实例，方法自动绑 `self`，不会把游戏其它调用弄坏）

## 三、参数

```lua
local API = getgenv().OreoSilentHead
API.cfg.fovRadius      -- 400 像素；调小=只打准心附近
API.cfg.fovEnabled     -- true
API.cfg.visibleOnly    -- true：只打能看见的头（保证「开枪必中」）
API.cfg.teamCheck      -- true：不打队友
API.cfg.wallbangOrigin -- false：开=目标被薄墙挡住时把发射原点挪到 9.9 格内可见点
API.cfg.chance         -- 100
API.cfg.debug          -- true 会打印每次改写的目标/距离/可见性
API.setEnabled(false)  -- 临时关
API.status()           -- 拦截方式 + 计数
API.unload()           -- 还原所有改动
```

## 四、自检与排错

左上角有一行状态条（`CFG.hud`，默认开）：

```
SA ON | hook namecall/upvalue(n) | shots 12 | rew 9 | Enemy1 HitboxHead vis
```

- `hook NO HOOK` → 三种拦截都没装上，脚本等于没跑
- 开枪时 `shots` 不涨 → 没拦到游戏的 UseItem 包
- `shots` 涨、`rew` 不涨 → 拦到了但选不出目标（看后面是 `no target` 还是 `xxx x`，`x` 表示不可见）
- 两个都涨但打不中 → 服务端不认包里弹道，需要走视角那条路


加载成功会打印：

```
[OREO-SA] 已加载 · 拦截方式 = namecall / hookfunction / upvalue(n) · 常开 · 100% · 只打 HitboxHead
```

- 拦截方式 = `upvalue(...)`：走的是原版那条路，最稳。
- 三种都失败 → 会 warn「脚本不生效」。执行器缺 `debug.getupvalues`、且没有
  `getrawmetatable`/`hookfunction` 时才会这样。
- 开枪没反应：先 `API.cfg.debug = true`，看 `rewrite` 日志有没有出；没有日志=没拦住包，
  有日志但打不中=目标不可见/超出武器射程/被护盾挡。

## 五、边界（照实说）

- 「100% 命中」= 每次开火都把弹道改到**可见目标的头命中盒中心**。隔着墙、超射程、
  目标开盾这类服务端自己会拒绝的情况，改包也救不了；要穿薄墙得手动开 `wallbangOrigin`。
- 移动靶不用提前量：Rivals 的枪是 raycast 命中判定（`Info.IsRaycast`），弹道方向即判定。
- 服务端若把 `"\2"` 只当特效、用 `"\0"` 的朝向重算命中，本移植同样成立（两处都写成了指向头部）。
- 这份源码是「反编译重建版」，`HitboxHead`/`Utility`/`EnumLibrary` 路径都从它里面核对过；
  游戏更新换了模块路径时，脚本会打印拦截失败而不是静默失效。

## 六、离线验证

`mock/mock_test.lua` 用 Lua 5.1 假装 Roblox 环境（Instance / CFrame / Vector3 / Raycast /
元表 / `debug.getupvalues`），跑通了：

1. 加载 → 上值替换成功、选人（跳过队友）、改包（起点不变、`"\2"`=HitboxHead、`"\3"` 在部件内）
2. `Reload` 这类非射击动作不被改；关闭开关后不改；被墙挡住时不改；`wallbangOrigin` 把原点抬到有视线的位置；`HitboxHeadSmall` 回退；无头命中盒不改
3. `unload()` 把上值还原、开火照常且不再改写

```
lua5.1 mock/mock_test.lua     # ALL MOCK TESTS PASSED / PHASE 2 PASSED / PHASE 3 PASSED
```

## 七、部署

丢进你现在这个仓库就行（和 `oreo_v9.lua` 同级）：

```
https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/silent_head.lua
```

执行器里：

```lua
loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/silent_head.lua"))()
```

不想走网络也可以整段贴进执行器（单文件、无外部依赖，只有它自己去 require 游戏自己的
`Utility` / `EnumLibrary`，拿不到就用本地实现）。
