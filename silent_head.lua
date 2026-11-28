--[[
  OREO · 静默自瞄（移植自本仓库里跑通的那一套）
  —— 不是从 kicia 反推，而是照 espaim.lua / rage.lua / cases_opensource_ragebot.lua
     里那条「改 UseItem 包」的实现原样搬过来，只留自瞄、常开、100%、只打头。

  参考（本仓库）：
    espaim.lua:750-835          静默 hook（hookfunction(UseItem.FireServer) + 改 4 个字段）
    rage.lua:520-625            包结构：\0 起点在目标旁边、\1 是 head.CFrame、\2 head、
                                \3 head 局部偏移；打的是 Head 不是 HitboxHead
    cases_opensource_ragebot.lua:420-445  同一份开源实现

  和上一版的区别（上一版照 kicia 写，实测无效果）：
    1. 起点不再用相机位置，改成目标头旁边 ~2 格 —— 服务端按墙挡/距离校验时也能过
    2. "\1" 不再是 lookAt，而是目标 head.CFrame（开源实现就是这么发的）
    3. 拦截优先用 hookfunction(UseItem.FireServer)，那是仓库里验证过能用的路子
    4. 队友判定改成 espaim 那套（对局 TeamID / Team 对象 / 空串不算 / PartyId），
       上一版只比 TeamID，FFA 里会把整屋子人当队友 → 一个目标都选不出来

  用法：
      loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/silent_head.lua"))()
  运行时：
      getgenv().OreoSilentHead.cfg / .setEnabled(false) / .status() / .unload()
]]

if getgenv().OreoSilentHead then
    warn("[OREO-SA] 已经加载过了，先 .unload() 再重载")
    return getgenv().OreoSilentHead
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
if not LP then
    repeat task.wait(0.1) until Players.LocalPlayer
    LP = Players.LocalPlayer
end

--==========================================================================
--  1. 参数
--==========================================================================
local CFG = {
    enabled = true,        -- 常开
    chance = 100,          -- 100 = 每一发都改
    part = "Head",         -- 开源实现打的是 Head；缺了才退 HitboxHead / HitboxHeadSmall
    fovEnabled = true,
    fovRadius = 220,       -- 屏幕像素半径（准心为中心），越大锁得越宽
    maxDist = 180,         -- 和目标的最大距离（格），超过就不锁
    visibleOnly = false,   -- 起点就在目标旁边，隔墙也能过；想只打看得见的就改 true
    teamCheck = true,
    lead = 0.06,           -- 提前量系数（×目标速度），0 = 不预判
    originJitter = 2,      -- 起点在目标头周围随机偏移（格），0 = 正好在头上
    hitJitter = 0.1,       -- 命中点的抖动（格），照开源实现
    desync = true,         -- 开火时把身体挪到目标旁边一瞬（rage.lua 那套），服务端就认起点
    desyncRadius = 5,      -- 挪过去的半径（格）
    desyncHold = 0.05,     -- 挪过去停多久再还原（秒）
    desyncMaxDist = 60,    -- 超过这个距离不挪（rage.lua 实测 60 内才有效）
    selfFire = true,       -- 拦下游戏那发，等位置同步后由我们重发（消掉 race，命中率高很多）
    selfFireDelay = 0.04,  -- 重发前等多久（秒）
    aimPart = "auto",      -- auto = 优先 HitboxHead，其次 Head；也可写 "Head"
    hud = true,
    debug = false,
}

local STATS = { shots = 0, rewrites = 0, noTarget = 0, desyncs = 0, selfFired = 0, hook = "none" }

local unpackFn = table.unpack or unpack

local function packArgs(...)
    return { n = select("#", ...), ... }
end

local function log(fmt, ...)
    if CFG.debug then
        print("[OREO-SA] " .. string.format(fmt, ...))
    end
end

--==========================================================================
--  2. 游戏原生接口
--==========================================================================
local RIVALS = { use = nil, util = nil, enums = nil, cam = nil }

pcall(function()
    local rem = ReplicatedStorage:WaitForChild("Remotes", 15)
    local rep = rem and rem:WaitForChild("Replication", 10)
    local fighter = rep and rep:WaitForChild("Fighter", 10)
    if fighter then
        RIVALS.use = fighter:WaitForChild("UseItem", 10)
        RIVALS.cam = fighter:FindFirstChild("UpdateCameraRotation")
    end
    local mods = ReplicatedStorage:WaitForChild("Modules", 10)
    if mods then
        local util = mods:FindFirstChild("Utility")
        if util then pcall(function() RIVALS.util = require(util) end) end
        local enums = mods:FindFirstChild("EnumLibrary")
        if enums then pcall(function() RIVALS.enums = require(enums) end) end
    end
end)

local useItem = RIVALS.use
local util = RIVALS.util

print(string.format("[OREO-SA] 接口: UseItem=%s util=%s enums=%s",
    tostring(useItem ~= nil), tostring(util ~= nil), tostring(RIVALS.enums ~= nil)))

if useItem == nil then
    warn("[OREO-SA] 找不到 ReplicatedStorage.Remotes.Replication.Fighter.UseItem，停")
    return
end

-- CFrame 编解码：优先游戏自己的 Utility
local function encodeCFrame(cf)
    if util and type(util.EncodeCFrame) == "function" then
        local ok, r = pcall(util.EncodeCFrame, util, cf)
        if ok and type(r) == "table" then
            return r
        end
    end
    local rx, ry, rz = cf:ToOrientation()
    return {
        ["\0"] = cf.X, ["\1"] = cf.Y, ["\2"] = cf.Z,
        ["\3"] = rx, ["\4"] = ry, ["\5"] = rz,
    }
end

local function toEnum(name)
    local v
    if RIVALS.enums then
        pcall(function() v = RIVALS.enums:ToEnum(name) end)
        if v == nil or v == "" then
            pcall(function()
                local tbl = RIVALS.enums._to_enum
                if type(tbl) == "table" then v = tbl[name] end
            end)
        end
    end
    return v
end

--==========================================================================
--  3. 队友 / 目标缓存（照 espaim）
--==========================================================================
local allyIds = {}
local duelTeam = {}

local spectateModule
local function duelScan()
    pcall(function()
        if spectateModule == nil then
            local ps = LP:FindFirstChild("PlayerScripts")
            for _, root in ipairs({ ps, ReplicatedStorage }) do
                if root then
                    local hit = root:FindFirstChild("SpectateController", true)
                    if hit and hit:IsA("ModuleScript") then
                        spectateModule = hit
                        break
                    end
                end
            end
        end
        if spectateModule == nil then
            return
        end
        local SC = require(spectateModule)
        local duel = SC and SC.CurrentDuelSubject
        local duelers = duel and duel.Duelers
        if not duelers then
            return
        end
        local map = {}
        for _, dueler in ipairs(duelers) do
            local plr = dueler.Player
            if plr then
                local tid
                pcall(function() tid = dueler:Get("TeamID") end)
                if tid ~= nil and tid ~= "" then
                    map[plr] = tid
                end
            end
        end
        if next(map) then
            duelTeam = map
        end
    end)
end

task.spawn(function()
    while task.wait(1) do
        duelScan()
    end
end)

local function isAlly(p)
    if p == LP then
        return true
    end
    if not CFG.teamCheck then
        return false
    end
    if allyIds[p.UserId] then
        return true
    end

    local mine = duelTeam[LP]
    if mine ~= nil and duelTeam[p] ~= nil then
        return mine == duelTeam[p]
    end

    if p.Team ~= nil and LP.Team ~= nil and (p.Team == LP.Team or p.Team.Name == LP.Team.Name) then
        return true
    end

    -- 空串不算：整屋子人 TeamID 都是 "" 的话，以前会把所有人都当队友
    local a, b = p:GetAttribute("TeamID"), LP:GetAttribute("TeamID")
    if type(a) == "string" and type(b) == "string" and a ~= "" and b ~= "" then
        return a == b
    end
    local ta, tb = p:GetAttribute("Team"), LP:GetAttribute("Team")
    if ta ~= nil and tb ~= nil and ta == tb then
        return true
    end
    local pa, pb = p:GetAttribute("PartyId"), LP:GetAttribute("PartyId")
    if type(pa) == "string" and type(pb) == "string" and pa ~= "" and pa == pb then
        return true
    end
    return false
end

getgenv().OreoSilentAlly = function(userId, on)
    if on == false then
        allyIds[tonumber(userId) or userId] = nil
    else
        allyIds[tonumber(userId) or userId] = true
    end
end

-- 角色缓存
local cache = {}
local function refreshCache(p)
    local ch = p.Character
    if not ch then
        cache[p] = nil
        return
    end
    local hitbox = ch:FindFirstChild("HitboxHead") or ch:FindFirstChild("HitboxHeadSmall")
    if hitbox ~= nil and not hitbox:IsA("BasePart") then
        hitbox = nil
    end
    local head = ch:FindFirstChild("Head")
    if head ~= nil and not head:IsA("BasePart") then
        head = nil
    end
    cache[p] = {
        char = ch,
        head = head or hitbox,   -- 兜底：没有视觉 Head 就用命中盒
        hitbox = hitbox,
        root = ch:FindFirstChild("HumanoidRootPart"),
        hum = ch:FindFirstChildOfClass("Humanoid"),
    }
end

local function watch(p)
    if p == LP then
        return
    end
    refreshCache(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.3)
        refreshCache(p)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    watch(p)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p)
    cache[p] = nil
end)

task.spawn(function()
    while task.wait(1) do
        for _, p in ipairs(Players:GetPlayers()) do
            local c = cache[p]
            if c == nil or c.char ~= p.Character or c.head == nil or c.head.Parent == nil then
                refreshCache(p)
            end
        end
    end
end)

-- 可见性（照 espaim canSee）
local rp = RaycastParams.new()
pcall(function()
    rp.FilterType = Enum.RaycastFilterType.Exclude
end)
rp.IgnoreWater = true

local function canSee(part, ch, cam)
    if part == nil or ch == nil or cam == nil then
        return false
    end
    local arr = { cam }
    if LP.Character then
        table.insert(arr, LP.Character)
    end
    rp.FilterDescendantsInstances = arr
    local origin = cam.CFrame.Position
    local hit = workspace:Raycast(origin, part.Position - origin, rp)
    return hit == nil or hit.Instance:IsDescendantOf(ch)
end

--==========================================================================
--  4. 目标预选（每帧一次，hook 里直接用）
--==========================================================================
local currentTarget = nil

local function pickTarget()
    local cam = workspace.CurrentCamera
    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if cam == nil or myRoot == nil then
        return nil
    end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local best, bestScore = nil, math.huge

    for p, c in pairs(cache) do
        local head, hum = c.head, c.hum
        if head ~= nil and head.Parent ~= nil and hum ~= nil and hum.Health > 0 and not isAlly(p) then
            if (head.Position - myRoot.Position).Magnitude <= CFG.maxDist then
                local sp, onScreen = cam:WorldToViewportPoint(head.Position)
                if onScreen and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if (not CFG.fovEnabled or d <= CFG.fovRadius) and d < bestScore then
                        if (not CFG.visibleOnly) or canSee(head, c.char, cam) then
                            best, bestScore = c, d
                        end
                    end
                end
            end
        end
    end

    if best == nil then
        return nil
    end
    return { head = best.head, char = best.char, root = best.root, hum = best.hum, player = nil }
end

RunService.RenderStepped:Connect(function()
    if CFG.enabled then
        currentTarget = pickTarget()
    else
        currentTarget = nil
    end
end)

--==========================================================================
--  5. 改包：照开源实现的字段语义
--==========================================================================
local function jitter(range)
    return (math.random() * 2 - 1) * range
end

--[[
  开火前把身体挪到目标旁边（rage.lua 的 desync）
  服务端是按你"复制过去的身体位置"算射线的：身体贴着目标，起点就合法，
  距离/墙挡校验都能过。发完 50ms 还原，客户端视角不动。
]]
local desyncSaved = nil
local desyncToken = 0

local function desyncTo(part, holdSeconds)
    if not CFG.desync then
        return nil
    end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root == nil then
        return nil
    end
    local standPos
    local ok, err = pcall(function()
        if desyncSaved == nil then
            desyncSaved = {
                root = root,
                cf = root.CFrame,
                vel = root.Velocity,
                rot = root.RotVelocity,
            }
        end
        local angle = math.random() * math.pi * 2
        local radius = math.random(30, math.max(31, CFG.desyncRadius * 10)) / 10
        standPos = part.Position + Vector3.new(math.cos(angle) * radius, math.random(0, 20) / 10, math.sin(angle) * radius)
        root.CFrame = CFrame.lookAt(standPos, part.Position)
    end)
    if not ok then
        log("desync 失败: %s", tostring(err))
        return nil
    end

    STATS.desyncs = STATS.desyncs + 1
    desyncToken = desyncToken + 1
    local mine = desyncToken
    task.delay(holdSeconds or CFG.desyncHold, function()
        if mine ~= desyncToken then
            return
        end
        local saved = desyncSaved
        desyncSaved = nil
        if saved == nil then
            return
        end
        pcall(function()
            if saved.root.Parent == nil then
                return
            end
            saved.root.CFrame = saved.cf
            saved.root.Velocity = saved.vel
            saved.root.RotVelocity = saved.rot
        end)
    end)

    return standPos
end

local function aimPartOf(target)
    if target == nil then
        return nil
    end
    if CFG.aimPart ~= "auto" and target.char then
        local p = target.char:FindFirstChild(CFG.aimPart)
        if p and p:IsA("BasePart") then
            return p
        end
    end
    return target.hitbox or target.head
end

local function rewriteShot(args, target, holdSeconds)
    if type(args) ~= "table" then
        return false
    end
    local shot = args["\1"]
    if type(shot) ~= "table" then
        return false
    end
    local head = aimPartOf(target)
    if head == nil or head.Parent == nil then
        return false
    end
    if CFG.chance < 100 and math.random() * 100 > CFG.chance then
        return false
    end

    local pos = head.Position
    local origin
    -- 60 格内先 desync（把身体挪过去，服务端才认这个起点），再退化成"包里写目标旁边"
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if myRoot ~= nil and (myRoot.Position - pos).Magnitude <= CFG.desyncMaxDist then
        origin = desyncTo(head, holdSeconds)
    end
    if origin == nil then
        local j = CFG.originJitter
        origin = pos + Vector3.new(jitter(j), math.random() * j, jitter(j))
    end
    local aimCF = CFrame.lookAt(origin, pos)

    -- 提前量：按目标当前速度预判，打移动靶更稳（开源 ragebot 版有这步）
    local lead = Vector3.zero
    if CFG.lead > 0 and target.root ~= nil then
        local okV, v = pcall(function()
            return target.root.AssemblyLinearVelocity
        end)
        if okV and typeof(v) == "Vector3" then
            lead = v * CFG.lead
            if lead.Magnitude > 25 then
                lead = lead.Unit * 25
            end
        end
    end

    local hj = CFG.hitJitter
    local aimedPos = pos + lead + Vector3.new(jitter(hj * 0.5), jitter(hj * 0.5), jitter(hj * 0.5))
    local ok, objSpace = pcall(function()
        return head.CFrame:ToObjectSpace(CFrame.new(aimedPos))
    end)
    if not ok then
        return false
    end

    shot["\0"] = encodeCFrame(aimCF)       -- 起点：贴着目标（desync 后的身体位置）
    shot["\1"] = encodeCFrame(head.CFrame)  -- 目标的 CFrame（不是 lookAt）
    shot["\2"] = head                       -- 目标部件
    shot["\3"] = encodeCFrame(objSpace)     -- 头局部空间里的命中点

    STATS.rewrites = STATS.rewrites + 1
    return true
end

--[[
  一次开火的总入口（三条拦截路径共用）
  selfFire 模式：拦下游戏自己那发 → 先 desync → 等 2 帧让位置同步到服务端 → 我们代替它发
  （rage.lua 里也是自己 FireServer，只是因为不能中途等，所以它带 race；这里等一帧就没 race 了）
]]
local function dispatch(objectId, action, data, deliver)
    if CFG.enabled and type(data) == "table" and currentTarget ~= nil then
        STATS.shots = STATS.shots + 1
        local hold = CFG.selfFire and (CFG.selfFireDelay + 0.06) or 0.05
        local ok, built = pcall(rewriteShot, data, currentTarget, hold)
        if ok and built and CFG.selfFire and type(task.delay) == "function" then
            -- 拦下游戏自己那发，等位置同步过去再由我们发；deliver 是原始函数，不会再进钩子
            STATS.selfFired = STATS.selfFired + 1
            local delay = CFG.selfFireDelay
            task.delay(delay, function()
                pcall(deliver)
            end)
            return
        end
        if ok and built then
            return deliver()
        end
    elseif CFG.enabled then
        STATS.noTarget = STATS.noTarget + 1
    end
    return deliver()
end

--==========================================================================
--  6. 拦截：hookfunction(UseItem.FireServer) → __namecall → 上值代理
--==========================================================================
local hookedOldFireServer, hookedTargetFn

local function installHookFunction()
    if type(hookfunction) ~= "function" then
        return false, "no hookfunction"
    end
    local ok, fn = pcall(function()
        return useItem.FireServer
    end)
    if not ok or type(fn) ~= "function" then
        return false, "no FireServer method"
    end

    local old
    local ok2 = pcall(function()
        old = hookfunction(fn, function(self, objectId, action, data, ...)
            local trailing = packArgs(...)
            local function forward()
                return old(self, objectId, action, data, unpackFn(trailing, 1, trailing.n))
            end
            if self ~= useItem then
                return forward()
            end
            return dispatch(objectId, action, data, forward)
        end)
    end)
    if ok2 and type(old) == "function" then
        hookedOldFireServer = old
        hookedTargetFn = fn
        return true, "hookfunction"
    end
    return false, "hookfunction failed"
end

local namecallOld, namecallHook
local function installNamecall()
    if type(getrawmetatable) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false, "no getrawmetatable"
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
        if okName and method == "FireServer" and self == useItem then
            local objectId, action, data = ...
            return dispatch(objectId, action, data, function()
                return namecallOld(self, objectId, action, data)
            end)
        end
        return namecallOld(self, ...)
    end
    local ok2 = pcall(function()
        if type(setreadonly) == "function" then setreadonly(mt, false) end
        mt.__namecall = namecallHook
        if type(setreadonly) == "function" then setreadonly(mt, true) end
    end)
    if not ok2 then
        return false, "assign failed"
    end
    local probeOk = pcall(function()
        local kids = workspace:GetChildren()
        assert(type(kids) == "table" and #kids > 0)
    end)
    if seen == 0 or not probeOk then
        pcall(function()
            if type(setreadonly) == "function" then setreadonly(mt, false) end
            mt.__namecall = namecallOld
            if type(setreadonly) == "function" then setreadonly(mt, true) end
        end)
        return false, "hook not working"
    end
    return true, "namecall"
end

-- 上值代理（kicia 那条路，留作最后兜底）
local REMOTE_PATH = { "Remotes", "Replication", "Fighter", "UseItem" }
local restoreList = {}

local function sameInstance(a, b)
    if a == b then return true end
    if type(compareinstances) == "function" then
        local ok, r = pcall(compareinstances, a, b)
        return ok and r == true
    end
    return false
end

local function pathDepth(inst)
    if typeof(inst) ~= "Instance" then
        return nil
    end
    local names = {}
    local node = inst
    for _ = 1, 8 do
        if node == nil then return nil end
        if sameInstance(node, ReplicatedStorage) then
            local depth = #names
            for i = 1, depth do
                if names[i] ~= REMOTE_PATH[depth - i + 1] then return nil end
            end
            return depth
        end
        names[#names + 1] = node.Name
        node = node.Parent
    end
    return nil
end

local function lazyProxy(real, overrides)
    return setmetatable(overrides or {}, {
        __index = function(_, key)
            if real == nil then return nil end
            local ok, value = pcall(function() return real[key] end)
            if not ok then return nil end
            if type(value) == "function" then
                return function(_, ...) return value(real, ...) end
            end
            return value
        end,
    })
end

local fireWrapper = function(_, objectId, action, data, ...)
    local args = packArgs(...)
    return dispatch(objectId, action, data, function()
        return useItem:FireServer(objectId, action, data, unpackFn(args, 1, args.n))
    end)
end

local function buildProxy(depth)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local replication = remotes and remotes:FindFirstChild("Replication")
    local fighter = replication and replication:FindFirstChild("Fighter")
    if fighter == nil then return nil end
    local fighterNode = lazyProxy(fighter, { UseItem = { FireServer = fireWrapper } })
    local replicationNode = lazyProxy(replication, { Fighter = fighterNode })
    local remotesNode = lazyProxy(remotes, { Replication = replicationNode })
    local rsNode = lazyProxy(ReplicatedStorage, { Remotes = remotesNode })
    return ({ rsNode, remotesNode, replicationNode, fighterNode })[depth + 1]
end

local function patchUpvalues(input)
    if type(input) ~= "function" or type(debug.getupvalues) ~= "function" then
        return 0
    end
    local ups = debug.getupvalues(input)
    if type(ups) ~= "table" then return 0 end
    local count = 0
    for _, up in pairs(ups) do
        if typeof(up) == "table" then
            for key, value in pairs(up) do
                if typeof(value) == "Instance" and pathDepth(value) then
                    local proxy = buildProxy(pathDepth(value))
                    if proxy ~= nil then
                        local original = value
                        local ok = pcall(function() up[key] = proxy end)
                        if ok then
                            restoreList[#restoreList + 1] = { t = up, k = key, old = original }
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return count
end

local function findInput()
    local proto
    pcall(function()
        local ps = LP:FindFirstChild("PlayerScripts")
        local mods = ps and ps:FindFirstChild("Modules")
        local reg = mods and mods:FindFirstChild("ClientReplicatedClasses")
        if reg then
            if reg:IsA("ModuleScript") then
                local ok, t = pcall(require, reg)
                if ok and type(t) == "table" then proto = t end
            end
            if proto == nil then
                local ci = reg:FindFirstChild("ClientItem", true)
                if ci and ci:IsA("ModuleScript") then
                    local ok, t = pcall(require, ci)
                    if ok then proto = t end
                end
            end
        end
    end)
    if type(proto) ~= "table" then return nil end
    -- 不能直接写 {proto, cf, proto.ClientItem, deep}：中间有 nil 的话 ipairs 会提前停
    local cf = proto.ClientFighter
    local deep = type(cf) == "table" and cf.ClientItem or nil
    local candidates = { proto }
    if type(cf) == "table" then candidates[#candidates + 1] = cf end
    if type(proto.ClientItem) == "table" then candidates[#candidates + 1] = proto.ClientItem end
    if type(deep) == "table" then candidates[#candidates + 1] = deep end
    for _, tbl in ipairs(candidates) do
        if type(rawget(tbl, "Input")) == "function" then
            return rawget(tbl, "Input")
        end
    end
    return nil
end

local installedBy
local reasons = {}
do
    local ok, why = installHookFunction()
    if ok then
        installedBy = why
    else
        reasons[#reasons + 1] = "hookfunction:" .. tostring(why)
        local ok2, why2 = installNamecall()
        if ok2 then
            installedBy = why2
        else
            reasons[#reasons + 1] = "namecall:" .. tostring(why2)
            local input = findInput()
            if input == nil then
                reasons[#reasons + 1] = "Input:nil"
            else
                local n = patchUpvalues(input)
                reasons[#reasons + 1] = "upvalue:" .. tostring(n)
                installedBy = n > 0 and ("upvalue(" .. n .. ")") or nil
            end
        end
    end
end

STATS.hook = installedBy or "none"

if installedBy == nil then
    warn("[OREO-SA] 三种拦截全失败（hookfunction / __namecall / 上值代理），脚本不生效 → "
        .. table.concat(reasons, " | "))
else
    print("[OREO-SA] 已加载 · 拦截 = " .. installedBy .. " · 常开 · 100% · 只打头（" .. CFG.part .. "）")
end

--==========================================================================
--  7. 状态条 + 运行时接口
--==========================================================================
local HUD
local function hudTick()
    if not CFG.hud then return end
    if HUD == nil or HUD.Parent == nil then
        local parent
        local ok, hui = pcall(function() return gethui() end)
        if ok and hui ~= nil then
            parent = hui
        else
            local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
            parent = ok2 and cg or nil
        end
        if parent == nil then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "OreoSilentHud"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 10
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 0.35
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.Size = UDim2.new(0, 380, 0, 18)
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
    local head = currentTarget and currentTarget.head
    local who = "no target"
    if head ~= nil then
        local nm = "?"
        for p, c in pairs(cache) do
            if c.head == head then nm = p.Name break end
        end
        who = nm .. " " .. head.Name
    end
    HUD.Text = string.format("SA %s | %s | shots %d | rew %d | ds %d | sf %d | %s",
        CFG.enabled and "ON" or "OFF", tostring(installedBy), STATS.shots, STATS.rewrites,
        STATS.desyncs, STATS.selfFired, who)
end

if CFG.hud then
    task.spawn(function()
        while CFG.hud do
            pcall(hudTick)
            task.wait(0.4)
        end
    end)
end

local API = {}
API.cfg = CFG
API.stats = STATS
API.installedBy = installedBy

function API.setEnabled(v)
    CFG.enabled = v and true or false
    return CFG.enabled
end

function API.status()
    return string.format("[OREO-SA] %s | %s | shots=%d rew=%d noTarget=%d desync=%d selfFire=%d | %s",
        tostring(installedBy), CFG.enabled and "ON" or "OFF",
        STATS.shots, STATS.rewrites, STATS.noTarget, STATS.desyncs, STATS.selfFired,
        currentTarget and currentTarget.head and currentTarget.head.Name or "no target")
end

function API.pick()
    local t = pickTarget()
    if t == nil then return nil end
    return { part = t.head.Name, position = t.head.Position }
end

function API.unload()
    CFG.enabled = false
    CFG.hud = false
    if hookedTargetFn ~= nil and type(hookfunction) == "function" and hookedOldFireServer ~= nil then
        pcall(hookfunction, hookedTargetFn, hookedOldFireServer)
    end
    if namecallHook ~= nil and type(getrawmetatable) == "function" then
        pcall(function()
            local mt = getrawmetatable(game)
            if type(setreadonly) == "function" then setreadonly(mt, false) end
            if mt.__namecall == namecallHook then mt.__namecall = namecallOld end
            if type(setreadonly) == "function" then setreadonly(mt, true) end
        end)
        namecallHook = nil
    end
    if desyncSaved ~= nil then
        local saved = desyncSaved
        desyncSaved = nil
        pcall(function()
            saved.root.CFrame = saved.cf
            saved.root.Velocity = saved.vel
            saved.root.RotVelocity = saved.rot
        end)
    end
    for _, e in ipairs(restoreList) do
        pcall(function() e.t[e.k] = e.old end)
    end
    if HUD ~= nil and HUD.Parent ~= nil then
        pcall(function() HUD.Parent:Destroy() end)
    end
    getgenv().OreoSilentHead = nil
    print("[OREO-SA] 已卸载")
end

getgenv().OreoSilentHead = API
return API
