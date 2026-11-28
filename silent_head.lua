--[[
  OREO · Silent Aim 独立移植版
  只保留「静默自瞄」：常开、100% 触发、只打头（HitboxHead）。

  移植自 oreo_v9.lua -> oreo-kicia-v9.lua 的 Combat > Silent Aim：
    · 目标提供器 / 命中盒解析      kicia_v9.lua:54166-54260 / 30217
    · 可见性射线 Check             kicia_v9.lua:29235-29276
    · 屏幕空间 FOV + 最近准心选择   kicia_v9.lua:25490-25625
    · UseItem 输入包拦截           kicia_v9.lua:31021-31170
    · 射击包改写 \0 \1 \2 \3       kicia_v9.lua:54339-54390
    · CFrame 编解码                kicia_v9.lua:27653-27685
    · Manipulate 环采样（可选）     kicia_v9.lua:54119

  用法：
      loadstring(game:HttpGet("https://<你的地址>/oreo_silent_head.lua"))()

  运行时接口：
      getgenv().OreoSilentHead.cfg            参数表
      getgenv().OreoSilentHead.setEnabled(b)  开关
      getgenv().OreoSilentHead.status()       状态
      getgenv().OreoSilentHead.unload()       卸载并还原
]]

if getgenv().OreoSilentHead then
    warn("[OREO-SA] 已经加载过了，先 unload() 再重载")
    return getgenv().OreoSilentHead
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

--==========================================================================
--  1. 参数（原版 SilentAim 的默认值，按「常开 + 100% + 只打头」调整）
--==========================================================================
local CFG = {
    enabled = true,          -- 常开
    chance = 100,            -- 原版 ActivationChance，固定 100
    headOnly = true,         -- 命中盒只取 HitboxHead / HitboxHeadSmall
    fovEnabled = true,       -- 是否用屏幕半径限制
    fovRadius = 400,         -- 原版 Fov.Radius = 150，这里放宽（像素）
    visibleOnly = true,      -- 原版 TargetConditions.Visible = true：只打得到的目标
    teamCheck = true,        -- TeamID 属性优先，回退 Player.Team
    actions = {},            -- 由下面填：StartShooting / StartAiming
    hitboxPoint = "Center",  -- 原版 HitboxPoint.Type：瞄准命中盒中心 part.Position
    wallbangOrigin = false,  -- 原版 Manipulate：目标不可见时找贴身可见原点（穿薄墙）
    hud = true,              -- 左上角一行状态：拦截方式 / 见到的包数 / 改写数 / 当前目标
    debug = false,
}
CFG.actions.StartShooting = true
CFG.actions.StartAiming = true -- 刀的重击 = StartAiming（原版 ragebot 也这么发）

local STATS = { shots = 0, rewrites = 0, noTarget = 0 }

local function log(fmt, ...)
    if CFG.debug then
        print("[OREO-SA] " .. string.format(fmt, ...))
    end
end

--==========================================================================
--  2. 基础工具
--==========================================================================
local compareinstances_ = (type(compareinstances) == "function") and compareinstances or nil

local function sameInstance(a, b)
    if a == b then
        return true
    end
    if compareinstances_ then
        local ok, r = pcall(compareinstances_, a, b)
        return ok and r == true
    end
    return false
end

--[[
  CFrame 编解码（对应原版 cN，kicia_v9.lua:27653）
  包里的 "\0".."\5" 就是 {X,Y,Z, rx,ry,rz}；优先用游戏自己的 Utility:EncodeCFrame，
  格式不对再退回本地实现。
]]
local encodeCFrame, decodeCFrame
do
    local Utility
    pcall(function()
        Utility = require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Utility", 5))
    end)

    local function localEncode(cf)
        local rx, ry, rz = cf:ToOrientation()
        return {
            ["\0"] = cf.X,
            ["\1"] = cf.Y,
            ["\2"] = cf.Z,
            ["\3"] = rx,
            ["\4"] = ry,
            ["\5"] = rz,
        }
    end

    local function isEncoded(t)
        if type(t) ~= "table" then
            return false
        end
        for i = 0, 5 do
            if type(t[string.char(i)]) ~= "number" then
                return false
            end
        end
        return true
    end

    encodeCFrame = function(cf)
        if Utility and type(Utility.EncodeCFrame) == "function" then
            local ok, r = pcall(Utility.EncodeCFrame, Utility, cf)
            if ok and isEncoded(r) then
                return r
            end
        end
        return localEncode(cf)
    end

    decodeCFrame = function(t)
        if not isEncoded(t) then
            return nil
        end
        return CFrame.new(t["\0"], t["\1"], t["\2"])
            * CFrame.fromOrientation(t["\3"], t["\4"], t["\5"])
    end

    log("Utility.EncodeCFrame = %s", Utility and type(Utility.EncodeCFrame) or "nil")
end

-- 动作枚举（原版 cK，kicia_v9.lua:27454）：_from_enum[数值] -> "StartShooting"
local enumFrom = nil
do
    local ok, lib = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("EnumLibrary", 5))
    end)
    if ok and type(lib) == "table" then
        local from = rawget(lib, "_from_enum")
        if type(from) == "table" then
            enumFrom = from
        elseif type(lib.FromEnum) == "function" then
            enumFrom = setmetatable({}, {
                __index = function(_, k)
                    local ok2, v = pcall(lib.FromEnum, lib, k)
                    if ok2 then
                        return v
                    end
                end,
            })
        end
    end
    log("EnumLibrary._from_enum = %s", enumFrom and "ok" or "nil")
end

local function actionName(action)
    if enumFrom == nil then
        return nil
    end
    local ok, name = pcall(function()
        return enumFrom[action]
    end)
    if ok and type(name) == "string" then
        return name
    end
    return nil
end

--==========================================================================
--  3. 目标提供器（对应原版 dc provider + ResolveHitboxes）
--==========================================================================
local function isAlive(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function isEnemy(player)
    if player == LocalPlayer then
        return false
    end
    if not CFG.teamCheck then
        return true
    end
    -- 游戏用 Player 属性 TeamID 记队伍（Player.Team 常是 nil），见 kicia_v9.lua:65712
    local mine = LocalPlayer:GetAttribute("TeamID")
    local theirs = player:GetAttribute("TeamID")
    if mine ~= nil and theirs ~= nil then
        return mine ~= theirs
    end
    local t1, t2 = LocalPlayer.Team, player.Team
    if t1 ~= nil and t2 ~= nil and t1 == t2 then
        return false
    end
    return true
end

-- 服务端只认 Hitbox 部件（kicia_v9.lua:65889），视觉的 Head 不算；所以不存在就放弃
local function headPart(character)
    if CFG.headOnly then
        local head = character:FindFirstChild("HitboxHead")
        if head and head:IsA("BasePart") then
            return head
        end
        local small = character:FindFirstChild("HitboxHeadSmall")
        if small and small:IsA("BasePart") then
            return small
        end
        return nil
    end
    return character:FindFirstChild("HitboxHead")
        or character:FindFirstChild("HitboxHeadSmall")
        or character:FindFirstChild("Head")
        or character:FindFirstChild("HumanoidRootPart")
end

--[[
  可见性（原版 index2.Check：从原点向部件射线，命中自己这一支才算看见）
  这里用 Exclude 过滤：本机角色 + 目标角色，命中任何其它几何体就视为被挡。
]]
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function()
    rayParams.RespectCanCollide = true
end)

local function isVisible(origin, part, character)
    if part == nil or part.Parent == nil then
        return false
    end
    local dir = part.Position - origin
    if dir.Magnitude < 1e-3 then
        return true
    end
    local filter = {}
    if character ~= nil then
        filter[#filter + 1] = character
    end
    if LocalPlayer.Character ~= nil then
        filter[#filter + 1] = LocalPlayer.Character
    end
    -- 手模 / 第一人称视图模型一般挂在 CurrentCamera 下面，不排掉的话每条射线
    -- 都会打在自己的枪上，visible 永远是 false，目标一个都选不出来
    local cam = workspace.CurrentCamera
    if cam ~= nil then
        filter[#filter + 1] = cam
    end
    rayParams.FilterDescendantsInstances = filter
    local hit = workspace:Raycast(origin, dir, rayParams)
    if hit == nil then
        return true
    end
    if hit.Instance == part then
        return true
    end
    if character ~= nil and character:IsAncestorOf(hit.Instance) then
        return true
    end
    -- 视图模型/自己身上漏出来的部件：当成没挡，继续往前看
    if cam ~= nil and type(cam.IsAncestorOf) == "function" and cam:IsAncestorOf(hit.Instance) then
        local delta = part.Position - hit.Position
        if delta.Magnitude < 0.5 then
            return true
        end
        local second = workspace:Raycast(hit.Position + delta.Unit * 0.25, delta, rayParams)
        return second == nil or second.Instance == part
            or (character ~= nil and character:IsAncestorOf(second.Instance))
    end
    return false
end

--[[
  Manipulate 的环采样（原版 gU，kicia_v9.lua:54119）
  目标被挡住时，在原点到目标之间 / 目标周围 9.9 格找一个「有视线」的原点，
  把包里的发射原点挪过去 —— 薄墙隔着的目标也能打中。
]]
local function findVisibleOrigin(origin, part, character)
    if isVisible(origin, part, character) then
        return origin
    end
    local delta = part.Position - origin
    local dist = delta.Magnitude
    if dist < 1e-3 then
        return nil
    end
    local unit = delta / dist
    local halfSize = part.Size.Magnitude / 2
    local travel = math.min(9.9, dist - halfSize)
    local moved = false
    if travel > 0 then
        local near = origin + unit * travel
        if isVisible(near, part, character) then
            return near
        end
        moved = true
    end
    local up = Vector3.yAxis
    local axis = math.abs(unit:Dot(up)) > 0.99 and Vector3.xAxis or up
    local right = unit:Cross(axis).Unit
    local up2 = right:Cross(unit).Unit
    local count = moved and 6 or 7
    for i = 0, count - 1 do
        local angle = math.tau * i / count
        local probe = origin + (right * math.cos(angle) + up2 * math.sin(angle)) * 9.9
        if isVisible(probe, part, character) then
            return probe
        end
    end
    return nil
end

-- 屏幕空间距离（原版 ck：透视投影下的夹角度量，这里用世界到屏幕的像素距离，等价于准心偏移）
local function pickTarget(origin)
    local cam = workspace.CurrentCamera
    if cam == nil then
        return nil
    end
    local viewport = cam.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local best, bestVisible, bestDist = nil, false, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local character = player.Character
            if character ~= nil and isAlive(character) then
                local part = headPart(character)
                if part ~= nil then
                    local screen, onScreen = cam:WorldToViewportPoint(part.Position)
                    if onScreen and screen.Z > 0 then
                        local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                        if (not CFG.fovEnabled) or dist <= CFG.fovRadius then
                            local visible = isVisible(origin, part, character)
                            if visible or not CFG.visibleOnly then
                                -- 可见的目标永远优先，其次才是离准心近
                                if (visible and not bestVisible)
                                    or (visible == bestVisible and dist < bestDist) then
                                    best = {
                                        part = part,
                                        point = part.Position,
                                        character = character,
                                        player = player,
                                        visible = visible,
                                    }
                                    bestVisible = visible
                                    bestDist = dist
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

--==========================================================================
--  4. 射击包改写（原版 _HandleInput，kicia_v9.lua:54339）
--     包结构：args["\1"] = { ["\0"]=起点CFrame, ["\1"]=起点CFrame(2),
--                            ["\2"]=命中部件, ["\3"]=部件局部命中点CFrame }
--==========================================================================
local function objectSpaceHitPoint(part, origin, worldPoint)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { part }
    local delta = worldPoint - origin
    local hit = delta.Magnitude > 1e-3 and workspace:Raycast(origin, delta, params) or nil
    local point = hit ~= nil and hit.Position or part:GetClosestPointOnSurface(origin)
    local localPoint = part.CFrame:PointToObjectSpace(point)
    if localPoint.Magnitude < 1e-4 then
        localPoint = Vector3.new(0.001, 0, 0)
    end
    return localPoint
end

local function safeLookAt(from, to)
    local delta = to - from
    if delta.Magnitude < 1e-2 then
        return CFrame.new(from)
    end
    return CFrame.lookAt(from, to)
end

local function rewriteShot(args)
    if type(args) ~= "table" then
        return false
    end
    local shot = args["\1"]
    if type(shot) ~= "table" then
        return false
    end

    local c0 = decodeCFrame(shot["\0"])
    if c0 == nil then
        return false
    end
    -- "\1" 不一定存在：有就一起改，没有就别硬塞一个字段进包里
    local c1 = decodeCFrame(shot["\1"])

    if CFG.chance < 100 and math.random() * 100 > CFG.chance then
        return false
    end

    local target = pickTarget(c0.Position)
    if target == nil then
        STATS.noTarget = STATS.noTarget + 1
        return false
    end

    local point = target.point
    local origin = c0.Position
    if (point - origin).Magnitude < 0.05 then
        return false
    end

    -- 原版 Manipulate：不可见目标把发射原点挪到贴身可见点
    if not target.visible and CFG.wallbangOrigin then
        local visibleOrigin = findVisibleOrigin(origin, target.part, target.character)
        if visibleOrigin ~= nil then
            origin = visibleOrigin
            c0 = CFrame.new(origin)
            if c1 ~= nil then
                c1 = CFrame.new(origin)
            end
        end
    end

    local aim0 = safeLookAt(c0.Position, point)
    local localPoint = objectSpaceHitPoint(target.part, aim0.Position, point)

    shot["\0"] = encodeCFrame(aim0)
    if c1 ~= nil then
        shot["\1"] = encodeCFrame(safeLookAt(c1.Position, point))
    end
    shot["\2"] = target.part
    shot["\3"] = encodeCFrame(CFrame.new(localPoint))

    STATS.rewrites = STATS.rewrites + 1
    log("rewrite -> %s | %s | dist=%.1f | visible=%s",
        target.player.Name, target.part.Name, (point - origin).Magnitude, tostring(target.visible))
    return true
end

-- 一次开火事件：只处理射击类动作；动作名解析不出来时靠包结构判断
local function handleUseItem(objectId, action, args)
    STATS.shots = STATS.shots + 1
    if not CFG.enabled then
        return
    end
    local name = actionName(action)
    if name ~= nil and not CFG.actions[name] then
        return
    end
    rewriteShot(args)
end

--==========================================================================
--  5. 装钩子（原版 dm._Load：找 ClientItem.Input，把它的 ReplicatedStorage
--     上值换成代理表 → UseItem.FireServer 被我们接管）
--==========================================================================
local useItemRemote
do
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 10)
            :WaitForChild("Replication", 5)
            :WaitForChild("Fighter", 5)
            :WaitForChild("UseItem", 5)
    end)
    useItemRemote = ok and remote or nil
end

if useItemRemote == nil then
    warn("[OREO-SA] 找不到 ReplicatedStorage.Remotes.Replication.Fighter.UseItem")
    return
end

local REMOTE_PATH = { "Remotes", "Replication", "Fighter", "UseItem" }

-- 这个实例在 RS -> UseItem 这条路径上的深度；0 = ReplicatedStorage 本身
local function pathDepth(inst)
    if typeof(inst) ~= "Instance" then
        return nil
    end
    local names = {}
    local node = inst
    for _ = 1, 8 do
        if node == nil then
            return nil
        end
        if sameInstance(node, ReplicatedStorage) then
            local depth = #names
            for i = 1, depth do
                if names[i] ~= REMOTE_PATH[depth - i + 1] then
                    return nil
                end
            end
            return depth
        end
        names[#names + 1] = node.Name
        node = node.Parent
    end
    return nil
end

-- 惰性代理：命中的 key 用我们的表，其余全部落到真实实例上（方法自动绑 self）
local function lazyProxy(real, overrides)
    return setmetatable(overrides or {}, {
        __index = function(_, key)
            if real == nil then
                return nil
            end
            local ok, value = pcall(function()
                return real[key]
            end)
            if not ok then
                return nil
            end
            if type(value) == "function" then
                return function(_, ...)
                    return value(real, ...)
                end
            end
            return value
        end,
    })
end

local fireWrapper = function(_, objectId, action, args, ...)
    pcall(handleUseItem, objectId, action, args)
    return useItemRemote:FireServer(objectId, action, args, ...)
end

-- depth 处开始搭代理链：RS / Remotes / Replication / Fighter
local function buildProxy(depth)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local replication = remotes and remotes:FindFirstChild("Replication")
    local fighter = replication and replication:FindFirstChild("Fighter")
    if fighter == nil then
        return nil
    end
    local useItemNode = { FireServer = fireWrapper }
    local fighterNode = lazyProxy(fighter, { UseItem = useItemNode })
    local replicationNode = lazyProxy(replication, { Fighter = fighterNode })
    local remotesNode = lazyProxy(remotes, { Replication = replicationNode })
    local rsNode = lazyProxy(ReplicatedStorage, { Remotes = remotesNode })

    if depth == 0 then
        return rsNode
    elseif depth == 1 then
        return remotesNode
    elseif depth == 2 then
        return replicationNode
    elseif depth == 3 then
        return fighterNode
    end
    return nil
end

local restoreList = {}

local function patchUpvalueTable(container, key)
    local original = container[key]
    local proxy = buildProxy(pathDepth(original))
    if proxy == nil then
        return false
    end
    local ok = pcall(function()
        container[key] = proxy
    end)
    if ok then
        restoreList[#restoreList + 1] = { container = container, key = key, original = original }
        return true
    end
    return false
end

-- 5.1 找到 ClientItem 原型 / Input 函数
local function findInputFunction()
    local proto
    pcall(function()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local mods = ps and ps:FindFirstChild("Modules")
        local registry = mods and mods:FindFirstChild("ClientReplicatedClasses")
        if registry == nil then
            return
        end
        if registry:IsA("ModuleScript") then
            local ok, reg = pcall(require, registry)
            if ok and type(reg) == "table" then
                proto = reg
            end
        end
        if proto == nil then
            local fighterClass = registry:FindFirstChild("ClientFighter", true)
            local itemClass = fighterClass and fighterClass:FindFirstChild("ClientItem", true)
            if itemClass and itemClass:IsA("ModuleScript") then
                local ok, m = pcall(require, itemClass)
                if ok then
                    proto = m
                end
            end
        end
    end)

    local function dig(t)
        if type(t) ~= "table" then
            return nil
        end
        if type(rawget(t, "Input")) == "function" then
            return rawget(t, "Input")
        end
        local mt = getmetatable(t)
        if type(mt) == "table" then
            local idx = rawget(mt, "__index")
            if type(idx) == "table" and type(rawget(idx, "Input")) == "function" then
                return rawget(idx, "Input")
            end
            if type(idx) == "function" then
                local ok, f = pcall(idx, t, "Input")
                if ok and type(f) == "function" then
                    return f
                end
            end
        end
        return nil
    end

    if proto ~= nil then
        local input = dig(proto)
        if input ~= nil then
            return input
        end
        -- 注册表里 ClientFighter.ClientItem 的常见形状
        local classTable = rawget(proto, "ClientFighter") or rawget(proto, "ClientItem")
        input = dig(classTable)
        if input ~= nil then
            return input
        end
        if type(classTable) == "table" then
            input = dig(rawget(classTable, "ClientItem"))
            if input ~= nil then
                return input
            end
        end
    end

    -- 兜底：扫 GC 找名字叫 Input 的函数
    if type(getgc) ~= "function" then
        return nil
    end
    local ok, gc = pcall(getgc, true)
    if not ok or type(gc) ~= "table" then
        return nil
    end
    local fallback
    for _, obj in ipairs(gc) do
        if type(obj) == "function" then
            local ok2, ups = pcall(debug.getupvalues, obj)
            if ok2 and type(ups) == "table" then
                local hit = false
                for _, up in pairs(ups) do
                    if typeof(up) == "Instance" and pathDepth(up) then
                        hit = true
                        break
                    elseif typeof(up) == "table" then
                        for _, v in pairs(up) do
                            if typeof(v) == "Instance" and pathDepth(v) then
                                hit = true
                                break
                            end
                        end
                    end
                    if hit then
                        break
                    end
                end
                if hit then
                    local nameOk, name = pcall(function()
                        return debug.info(obj, "n")
                    end)
                    if nameOk and name == "Input" then
                        return obj
                    end
                    fallback = fallback or obj
                end
            end
        end
    end
    return fallback
end

local function patchUpvalues(input)
    if type(input) ~= "function" or type(debug.getupvalues) ~= "function" then
        return 0
    end
    local ups = debug.getupvalues(input)
    if type(ups) ~= "table" then
        return 0
    end
    local count = 0
    for index, up in pairs(ups) do
        if typeof(up) == "Instance" then
            local proxy = buildProxy(pathDepth(up))
            if proxy ~= nil then
                local ok = pcall(function()
                    debug.setupvalue(input, index, proxy)
                end)
                if ok then
                    restoreList[#restoreList + 1] = { upvalueFunc = input, upvalueIndex = index, original = up }
                    count = count + 1
                end
            end
        elseif typeof(up) == "table" then
            for key, value in pairs(up) do
                if typeof(value) == "Instance" and pathDepth(value) then
                    if patchUpvalueTable(up, key) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

-- 5.2 直接挂 Instance 元表的 __namecall（最干净，能挂上就不用碰游戏内部）
local namecallOld, namecallHook
local function installNamecallHook()
    if type(getrawmetatable) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false, "no getrawmetatable/getnamecallmethod"
    end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or type(mt) ~= "table" or type(mt.__namecall) ~= "function" then
        return false, "no __namecall"
    end

    namecallOld = mt.__namecall
    local seen = 0
    namecallHook = function(self, ...)
        seen = seen + 1
        local okName, method = pcall(getnamecallmethod)
        if okName and method == "FireServer" and self == useItemRemote then
            local objectId, action, args = ...
            pcall(handleUseItem, objectId, action, args)
        end
        return namecallOld(self, ...)
    end

    local ok2 = pcall(function()
        if type(setreadonly) == "function" then
            setreadonly(mt, false)
        end
        mt.__namecall = namecallHook
        if type(setreadonly) == "function" then
            setreadonly(mt, true)
        end
    end)
    if not ok2 then
        return false, "assign failed"
    end

    -- 自检：钩子必须被调用，而且转发必须还能正常返回
    local probeOk = pcall(function()
        local children = workspace:GetChildren()
        assert(type(children) == "table" and #children > 0)
    end)

    if seen == 0 or not probeOk then
        pcall(function()
            if type(setreadonly) == "function" then
                setreadonly(mt, false)
            end
            mt.__namecall = namecallOld
            if type(setreadonly) == "function" then
                setreadonly(mt, true)
            end
        end)
        return false, seen == 0 and "hook not called" or "forward broken"
    end
    return true, "namecall"
end

local function removeNamecallHook()
    if namecallHook == nil then
        return
    end
    pcall(function()
        local mt = getrawmetatable(game)
        if type(setreadonly) == "function" then
            setreadonly(mt, false)
        end
        if mt.__namecall == namecallHook then
            mt.__namecall = namecallOld
        end
        if type(setreadonly) == "function" then
            setreadonly(mt, true)
        end
    end)
    namecallHook = nil
end

-- 5.3 hookfunction 方式：直接接管 remote 的 FireServer（没有 newcclosure 也能试）
local hookedFireServer, hookedOldFireServer
local function installHookfunction()
    if type(hookfunction) ~= "function" then
        return false, "no hookfunction"
    end
    local ok, fn = pcall(function()
        return useItemRemote.FireServer
    end)
    if not ok or type(fn) ~= "function" then
        return false, "no method"
    end
    local old
    local ok2 = pcall(function()
        old = hookfunction(fn, function(self, ...)
            if self == useItemRemote then
                local objectId, action, args = ...
                pcall(handleUseItem, objectId, action, args)
            end
            return old(self, ...)
        end)
    end)
    if ok2 and type(old) == "function" then
        hookedFireServer, hookedOldFireServer = fn, old
        return true, "hookfunction"
    end
    return false, "hookfunction failed"
end

-- 5.4 组合安装：namecall -> hookfunction -> 上值替换
local installedBy
do
    local ok, why = installNamecallHook()
    if ok then
        installedBy = why
    else
        log("namecall: %s", tostring(why))
        local ok2, why2 = installHookfunction()
        if ok2 then
            installedBy = why2
        else
            log("hookfunction: %s", tostring(why2))
            local input = findInputFunction()
            local count = input and patchUpvalues(input) or 0
            if count > 0 then
                installedBy = "upvalue(" .. tostring(count) .. ")"
            else
                installedBy = nil
            end
        end
    end
end

if installedBy == nil then
    warn("[OREO-SA] 三种拦截方式都失败：namecall / hookfunction / ClientItem.Input 上值替换")
    warn("[OREO-SA] 脚本不生效，把这段 warn 发给作者看执行器信息")
else
    print("[OREO-SA] 已加载 · 拦截方式 = " .. installedBy ..
        " · 常开 · 100% · 只打 HitboxHead")
end

--==========================================================================
--  6. 运行时接口
--==========================================================================
local startedAt = os.clock()

local API = {}
API.cfg = CFG
API.stats = STATS
API.installedBy = installedBy

function API.setEnabled(value)
    CFG.enabled = value and true or false
    return CFG.enabled
end

function API.status()
    return string.format(
        "[OREO-SA] %s | %s | shots=%d rewrites=%d noTarget=%d | fov=%d visibleOnly=%s | up=%.0fs",
        tostring(installedBy), CFG.enabled and "ON" or "OFF",
        STATS.shots, STATS.rewrites, STATS.noTarget,
        CFG.fovRadius, tostring(CFG.visibleOnly), os.clock() - startedAt
    )
end

function API.pick()
    local cam = workspace.CurrentCamera
    local origin = cam and cam.CFrame.Position or Vector3.zero
    local target = pickTarget(origin)
    if target == nil then
        return nil
    end
    return {
        player = target.player.Name,
        part = target.part.Name,
        visible = target.visible,
        position = target.point,
    }
end

--==========================================================================
--  6.1 左上角状态条（排查用：一眼看出「有没有拦到包」「有没有选中人」）
--==========================================================================
local HUD
local function hudTick()
    if not CFG.hud then
        return
    end
    if HUD == nil or HUD.Parent == nil then
        local parent
        local ok, hui = pcall(function()
            return gethui()
        end)
        if ok and hui ~= nil then
            parent = hui
        else
            local ok2, cg = pcall(function()
                return game:GetService("CoreGui")
            end)
            parent = ok2 and cg or nil
        end
        if parent == nil then
            return
        end
        local gui = Instance.new("ScreenGui")
        gui.Name = "OreoSilentHud"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 10
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 0.35
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.Size = UDim2.new(0, 360, 0, 18)
        label.Position = UDim2.new(0, 8, 0, 8)
        label.Font = Enum.Font.Code
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextColor3 = Color3.new(0.45, 1, 0.45)
        label.Text = "OREO-SA"
        label.Parent = gui
        gui.Parent = parent
        HUD = label
    end

    local target = pickTarget(workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero)
    local who = "no target"
    if target ~= nil then
        who = target.player.Name .. " " .. target.part.Name .. (target.visible and " vis" or " x")
    end
    HUD.Text = string.format("SA %s | hook %s | shots %d | rew %d | %s",
        CFG.enabled and "ON" or "OFF", tostring(installedBy),
        STATS.shots, STATS.rewrites, who)
end

if CFG.hud then
    task.spawn(function()
        while CFG.hud do
            pcall(hudTick)
            task.wait(0.4)
        end
    end)
end

function API.unload()
    removeNamecallHook()
    -- hookfunction 还原：把原函数写回同一个 C 闭包
    if type(hookfunction) == "function" and hookedFireServer ~= nil and hookedOldFireServer ~= nil then
        pcall(hookfunction, hookedFireServer, hookedOldFireServer)
        hookedFireServer, hookedOldFireServer = nil, nil
    end
    for _, entry in ipairs(restoreList) do
        if entry.upvalueFunc ~= nil then
            pcall(function()
                debug.setupvalue(entry.upvalueFunc, entry.upvalueIndex, entry.original)
            end)
        else
            pcall(function()
                entry.container[entry.key] = entry.original
            end)
        end
    end
    CFG.enabled = false
    CFG.hud = false
    if HUD ~= nil and HUD.Parent ~= nil then
        pcall(function()
            HUD.Parent:Destroy() -- 只删自己的 ScreenGui，绝不碰 CoreGui/gethui
        end)
    end
    getgenv().OreoSilentHead = nil
    print("[OREO-SA] 已卸载")
end

getgenv().OreoSilentHead = API

if CFG.debug then
    task.spawn(function()
        while CFG.enabled do
            task.wait(5)
            print(API.status())
        end
    end)
end

return API
