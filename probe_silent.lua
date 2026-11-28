--[[
  probe_silent.lua —— 静默自瞄「没效果」诊断用
  只读：不改任何包，只打印事实。跑完把 Delta Console 的内容发回来。

  用法：
    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/probe_silent.lua"))()
  进一局，拿枪，对着人开 2~3 枪，然后看 Console。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local function p(...)
    local parts = { "[P]" }
    for i = 1, select("#", ...) do
        parts[i + 1] = tostring((select(i, ...)))
    end
    print(table.concat(parts, " "))
end

local function fullName(v)
    if typeof(v) == "Instance" then
        local ok, n = pcall(function() return v:GetFullName() end)
        return ok and n or v.Name
    end
    return typeof(v)
end

--============================================================
-- 1. 执行器能力
--============================================================
p("executor =", (type(identifyexecutor) == "function" and identifyexecutor()) or "unknown")
p("apis: getrawmetatable =", type(getrawmetatable),
    "| setreadonly =", type(setreadonly),
    "| getnamecallmethod =", type(getnamecallmethod),
    "| hookfunction =", type(hookfunction),
    "| newcclosure =", type(newcclosure),
    "| debug.getupvalues =", type(debug.getupvalues),
    "| debug.setupvalue =", type(debug.setupvalue),
    "| getgc =", type(getgc))

-- 主脚本还在不在
local main = getgenv().OreoSilentHead
if main then
    p("main script:", main.status and main.status() or "loaded")
else
    p("main script: not loaded (或已被 unload)")
end

--============================================================
-- 2. 远程对象 / 枚举
--============================================================
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local replication = remotes and remotes:FindFirstChild("Replication")
local fighter = replication and replication:FindFirstChild("Fighter")
local useItem = fighter and fighter:FindFirstChild("UseItem")
local updateRotation = fighter and fighter:FindFirstChild("UpdateCameraRotation")
local updateState = fighter and fighter:FindFirstChild("UpdateState")
p("remotes: UseItem =", useItem ~= nil,
    "| UpdateCameraRotation =", updateRotation ~= nil,
    "| UpdateState =", updateState ~= nil)

local enumFrom, enumTo
pcall(function()
    local lib = require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("EnumLibrary", 5))
    enumFrom, enumTo = lib._from_enum, lib._to_enum
end)
p("enum: _from_enum =", enumFrom ~= nil, "| _to_enum =", enumTo ~= nil,
    "| StartShooting =", enumTo and enumTo.StartShooting or "nil")

--============================================================
-- 3. ClientItem.Input 与它的上值
--============================================================
local registry = LP.PlayerScripts:FindFirstChild("Modules")
    and LP.PlayerScripts.Modules:FindFirstChild("ClientReplicatedClasses")
p("ClientReplicatedClasses =", tostring(registry))

local proto
pcall(function()
    if registry and registry:IsA("ModuleScript") then
        proto = require(registry)
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
    end
    return nil
end

local input
if proto ~= nil then
    input = dig(proto) or dig(rawget(proto, "ClientFighter"))
        or dig(rawget(rawget(proto, "ClientFighter") or {}, "ClientItem"))
end
p("ClientItem.Input =", tostring(input))

if type(input) == "function" and type(debug.getupvalues) == "function" then
    local ok, ups = pcall(debug.getupvalues, input)
    if ok and type(ups) == "table" then
        p("Input 上值数量 =", #ups)
        for i, up in pairs(ups) do
            if typeof(up) == "Instance" then
                p("   up[" .. i .. "] Instance:", fullName(up),
                    up == ReplicatedStorage and "<<< 就是 ReplicatedStorage" or "")
            elseif typeof(up) == "table" then
                local hits = 0
                for _, v in pairs(up) do
                    if typeof(v) == "Instance" and v == ReplicatedStorage then
                        hits = hits + 1
                    end
                end
                p("   up[" .. i .. "] table: keys=" .. #up .. " 含RS=" .. hits)
            else
                p("   up[" .. i .. "]", typeof(up))
            end
        end
    else
        p("Input 上值读取失败:", tostring(ups))
    end
end

--============================================================
-- 4. 只读监听：谁在发 FireServer、包里长什么样
--============================================================
local shots = 0
local rotationPackets = 0

local function dumpShot(source, objectId, action, args)
    local name = enumFrom and enumFrom[action] or "?"
    shots = shots + 1
    if shots > 8 then
        return
    end
    p("SHOT#" .. shots, source, "obj=" .. tostring(objectId), "action=" .. tostring(name))
    if type(args) ~= "table" then
        p("   args =", typeof(args))
        return
    end
    local outer = {}
    for k in pairs(args) do
        outer[#outer + 1] = string.format("%q=%s", tostring(k), typeof(args[k]))
    end
    p("   外层:", table.concat(outer, " "))
    local shot = args["\1"]
    if type(shot) == "table" then
        local inner = {}
        for k, v in pairs(shot) do
            inner[#inner + 1] = string.format("%q=%s", tostring(k),
                typeof(v) == "Instance" and fullName(v) or typeof(v))
        end
        p("   \\1:", table.concat(inner, " "))
        local c0 = shot["\0"]
        if type(c0) == "table" then
            p(string.format("   \\0 = %.1f, %.1f, %.1f | rot %.2f, %.2f, %.2f",
                tonumber(c0["\0"]) or 0, tonumber(c0["\1"]) or 0, tonumber(c0["\2"]) or 0,
                tonumber(c0["\3"]) or 0, tonumber(c0["\4"]) or 0, tonumber(c0["\5"]) or 0))
        end
    else
        p("   \\1 =", typeof(shot))
    end
end

local hooked = "none"
local mt = nil
local oldNamecall = nil
if type(getrawmetatable) == "function" and type(getnamecallmethod) == "function" then
    local ok, m = pcall(getrawmetatable, game)
    if ok and type(m) == "table" and type(m.__namecall) == "function" then
        mt, oldNamecall = m, m.__namecall
        local hook = function(self, ...)
            local okName, method = pcall(getnamecallmethod)
            if okName and method == "FireServer" then
                if self == useItem then
                    local objectId, action, args = ...
                    dumpShot("UseItem", objectId, action, args)
                elseif self == updateRotation then
                    rotationPackets = rotationPackets + 1
                    if rotationPackets <= 5 then
                        local a, b = ...
                        p("ROT#" .. rotationPackets, "args:", typeof(a), typeof(b))
                        if type(a) == "table" then
                            p(string.format("   rot = %.1f, %.1f, %.1f | %.2f, %.2f, %.2f",
                                tonumber(a["\0"]) or 0, tonumber(a["\1"]) or 0, tonumber(a["\2"]) or 0,
                                tonumber(a["\3"]) or 0, tonumber(a["\4"]) or 0, tonumber(a["\5"]) or 0))
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end
        local ok2 = pcall(function()
            if type(setreadonly) == "function" then setreadonly(m, false) end
            m.__namecall = hook
            if type(setreadonly) == "function" then setreadonly(m, true) end
        end)
        local probeOk = false
        if ok2 then
            probeOk = pcall(function()
                local kids = workspace:GetChildren()
                assert(type(kids) == "table" and #kids > 0)
            end)
        end
        if ok2 and probeOk then
            hooked = "namecall"
        else
            pcall(function()
                if type(setreadonly) == "function" then setreadonly(m, false) end
                m.__namecall = oldNamecall
                if type(setreadonly) == "function" then setreadonly(m, true) end
            end)
        end
    end
end
p("监听方式 =", hooked)

--============================================================
-- 5. 目标扫描：谁能被选中、为什么被跳过
--============================================================
local function headOf(char)
    local h = char:FindFirstChild("HitboxHead") or char:FindFirstChild("HitboxHeadSmall")
    if h and h:IsA("BasePart") then return h end
    return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function() rayParams.RespectCanCollide = true end)

local function visible(fromPos, part, char)
    local filter = {}
    if char then filter[#filter + 1] = char end
    if LP.Character then filter[#filter + 1] = LP.Character end
    rayParams.FilterDescendantsInstances = filter
    local hit = workspace:Raycast(fromPos, part.Position - fromPos, rayParams)
    return hit == nil or hit.Instance == part or (char and char:IsAncestorOf(hit.Instance))
end

task.spawn(function()
    for round = 1, 6 do
        task.wait(3)
        local cam = workspace.CurrentCamera
        if cam == nil then
            p("scan: no camera")
        else
            local vp = cam.ViewportSize
            local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
            local mineTeam = LP:GetAttribute("TeamID")
            local lines = {}
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LP then
                    local char = pl.Character
                    local head = char and headOf(char)
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local theirTeam = pl:GetAttribute("TeamID")
                    local note
                    if char == nil then
                        note = "无角色"
                    elseif hum == nil or hum.Health <= 0 then
                        note = "死亡"
                    elseif head == nil then
                        note = "无 HitboxHead"
                    else
                        local sp, onScreen = cam:WorldToViewportPoint(head.Position)
                        local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        note = string.format("dist=%.0fpx onScreen=%s vis=%s team=%s/%s",
                            dist, tostring(onScreen), tostring(visible(cam.CFrame.Position, head, char)),
                            tostring(mineTeam), tostring(theirTeam))
                    end
                    lines[#lines + 1] = pl.Name .. ": " .. note
                end
            end
            p("scan#" .. round, table.concat(lines, " | "))
        end
    end
end)

p("probe 已就绪：进游戏、拿枪、开 2~3 枪，然后看上面 SHOT / ROT 行")
