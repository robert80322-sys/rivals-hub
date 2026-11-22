--[[
════════════════════════════════════════════════════════════
  SNIPER · 5 度强制甩头（所有枪通用）
    手里是任意枪械（刀/近战自动跳过）：
      准星 5° 内出现敌人 → 强制鼠标位移到头上
    不发任何包 → 子弹走游戏原生流程，不会莫名其妙少子弹。
    狙：甩完等你扣扳机；连发：每帧都跟着头，准星像被吸住。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/sniper.lua?t=" .. os.time()))()
════════════════════════════════════════════════════════════
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
if not LP then
    repeat task.wait(0.1) until Players.LocalPlayer
    LP = Players.LocalPlayer
end

local DBG = {}
local lastDbgAt = 0
local function dbg(m, force)
    local now = os.clock()
    if not force and now - lastDbgAt < 2 then return end
    lastDbgAt = now
    DBG[#DBG + 1] = os.date("%H:%M:%S") .. " " .. tostring(m)
    if #DBG > 120 then table.remove(DBG, 1) end
    pcall(function() if writefile then writefile("sniper_debug.txt", table.concat(DBG, "\n")) end end)
end

local CFG = {
    snapDeg    = 5.0,    -- 准星多少度以内才触发
    cooldown   = 0.12,   -- 狙击：两次甩头之间的最小间隔
    autoCd     = 0.0,    -- 连发枪：0 = 每帧都跟（准星被吸住的感觉）
    aimDist    = 800,    -- 目标最远距离
    teamCheck  = true,
    visibleOnly= true,   -- 隔着墙不甩
    mouseMode  = true,   -- 强制鼠标位移（不发包 → 不会莫名其妙少子弹）
    debug      = true,   -- 写 sniper_debug.txt
    fireAtAll  = false,  -- 只甩不打：玩家自己扣扳机，走游戏正常弹道
}

--═══════════ 接口 ═══════════
-- 注意：鼠标模式根本不需要这些远程，所以放到后台去等，别挡住主循环。
-- 之前 WaitForChild 最长 15 秒，整个脚本就"没效果"了 15 秒。
local RIVALS = { ready = false }
task.spawn(function()
    pcall(function()
        local rem = RS:WaitForChild("Remotes", 10)
        local rep = rem and rem:WaitForChild("Replication", 5)
        local fighter = rep and rep:WaitForChild("Fighter", 5)
        if fighter then RIVALS.use = fighter:FindFirstChild("UseItem") end
        local mods = RS:FindFirstChild("Modules")
        local util = mods and mods:FindFirstChild("Utility")
        local enums = mods and mods:FindFirstChild("EnumLibrary")
        if util  then pcall(function() RIVALS.util  = require(util)  end) end
        if enums then pcall(function() RIVALS.enums = require(enums) end) end
        RIVALS.ready = true
    end)
end)

local moduleCache = {}
local function findModule(name)
    if moduleCache[name] then return moduleCache[name] end
    local ps = LP:FindFirstChild("PlayerScripts")
    local direct = {
        ps and ps:FindFirstChild("Controllers") and ps.Controllers:FindFirstChild(name),
        ps and ps:FindFirstChild("Modules") and ps.Modules:FindFirstChild(name),
        RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild(name),
    }
    for _, m in ipairs(direct) do
        if m and m:IsA("ModuleScript") then moduleCache[name] = m return m end
    end
    for _, root in ipairs({ ps, RS }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ModuleScript") and d.Name == name then moduleCache[name] = d return d end
            end
        end
    end
    return nil
end

local function equippedItem()
    local ok, item = pcall(function()
        local mod = findModule("FighterController")
        if not mod then return nil end
        local FC = require(mod)
        local f = FC and FC.LocalFighter
        if not f and FC and FC.GetFighter then f = FC:GetFighter(LP) end
        return f and f.EquippedItem or nil
    end)
    return ok and item or nil
end

local function itemName(item)
    local n
    pcall(function() n = item and item.Get and item:Get("Name") end)
    if not n then pcall(function() n = item and item.Name end) end
    return tostring(n or "")
end

local MELEE_WORDS = { "knife", "dagger", "blade", "bat", "sword", "axe", "hammer", "fist", "gauntlet" }

local function isGun(item)
    local n = string.lower(itemName(item))
    if n == "" then return false end
    for _, w in ipairs(MELEE_WORDS) do
        if string.find(n, w, 1, true) then return false end
    end
    return true
end

local function isSniper(item)
    local n = string.lower(itemName(item))
    return string.find(n, "sniper", 1, true) ~= nil
        or string.find(n, "awp", 1, true) ~= nil
        or string.find(n, "railgun", 1, true) ~= nil
end

--═══════════ 队友 / 可见 ═══════════
local function isAlly(p)
    if p == LP then return true end
    if not CFG.teamCheck then return false end
    if p.Team ~= nil and LP.Team ~= nil and p.Team == LP.Team then return true end
    local a, b = p:GetAttribute("TeamID"), LP:GetAttribute("TeamID")
    if type(a) == "string" and type(b) == "string" and a ~= "" and b ~= "" then return a == b end
    return false
end

local rp = RaycastParams.new()
pcall(function() rp.FilterType = Enum.RaycastFilterType.Exclude end)
rp.IgnoreWater = true

local function canSee(part, char, cam)
    if not (part and char and cam) then return false end
    local arr = { cam }
    if LP.Character then table.insert(arr, LP.Character) end
    rp.FilterDescendantsInstances = arr
    local origin = cam.CFrame.Position
    local hit = workspace:Raycast(origin, part.Position - origin, rp)
    return hit == nil or hit.Instance:IsDescendantOf(char)
end

--═══════════ 角色缓存 ═══════════
local cache = {}
local function refresh(p)
    local ch = p.Character
    cache[p] = ch and { char = ch, head = ch:FindFirstChild("Head"), hum = ch:FindFirstChildOfClass("Humanoid") } or nil
end
local function watch(p)
    if p == LP then return end
    refresh(p)
    p.CharacterAdded:Connect(function() task.wait(0.3) refresh(p) end)
end
for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p) cache[p] = nil end)
task.spawn(function()
    while task.wait(1) do
        for _, p in ipairs(Players:GetPlayers()) do
            local c = cache[p]
            if not c or c.char ~= p.Character or (c.head and not c.head.Parent) then refresh(p) end
        end
    end
end)

--═══════════ 强制鼠标位移 ═══════════
-- 不发任何包，只把鼠标（视角）强行甩到目标头上。
-- 好处：子弹走游戏原生流程，打出去几颗就是几颗，不会出现"弹药少了但没伤害"。
local MOVE = mousemoverel or MouseMoveRel or mouse_move_rel or mousemoverelo
dbg("mousemoverel=" .. tostring(type(mousemoverel)) .. " MouseMoveRel=" .. tostring(type(MouseMoveRel)), true)

local function mouseMoveTo(head)
    if type(MOVE) ~= "function" then
        dbg("!! 没有可用的鼠标位移函数")
        return false
    end
    local cam = workspace.CurrentCamera
    if not cam then return false end

    local goal = CFrame.lookAt(cam.CFrame.Position, head.Position)
    local tPitch, tYaw = goal:ToOrientation()
    local cPitch, cYaw = cam.CFrame:ToOrientation()

    local dYaw = tYaw - cYaw
    if dYaw > math.pi then dYaw = dYaw - math.pi * 2
    elseif dYaw < -math.pi then dYaw = dYaw + math.pi * 2 end
    local dPitch = tPitch - cPitch

    -- 角度 → 像素：屏幕半高 / tan(FOV/2)
    local vp = cam.ViewportSize
    local ppd = (vp.Y * 0.5) / math.tan(math.rad(cam.FieldOfView) * 0.5)

    local dx = dYaw * ppd
    local dy = -dPitch * ppd      -- 屏幕 Y 向下为正，pitch 向上是负

    pcall(MOVE, dx, dy)
    return true
end

--═══════════ 主循环：5 度内甩头 + 开枪 ═══════════
RunService.RenderStepped:Connect(function()
    if os.clock() < nextFire then return end

    local item = equippedItem()
    if not item then
        if CFG.debug then dbg("拿不到武器（FighterController.LocalFighter）") end
        return
    end
    if not isGun(item) then
        if CFG.debug then dbg("手里是近战：" .. itemName(item)) end
        return
    end
    local sniperMode = isSniper(item)

    local cam = workspace.CurrentCamera
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (cam and myRoot) then return end

    local look = cam.CFrame.LookVector
    local camPos = cam.CFrame.Position
    local limit = math.rad(CFG.snapDeg)

    local best, bestAngle = nil, limit
    for p, c in pairs(cache) do
        local head, hum = c.head, c.hum
        if head and hum and hum.Health > 0 and head.Parent and not isAlly(p) then
            local toHead = head.Position - camPos
            if toHead.Magnitude <= CFG.aimDist and toHead.Magnitude > 0.5 then
                local angle = math.acos(math.clamp(look:Dot(toHead.Unit), -1, 1))
                if angle <= bestAngle then
                    if (not CFG.visibleOnly) or canSee(head, c.char, cam) then
                        bestAngle = angle
                        best = head
                    end
                end
            end
        end
    end

    if CFG.debug then
        dbg(string.format("武器=%s 候选=%s 角度=%.1f°",
            itemName(item), tostring(best ~= nil), math.deg(bestAngle)))
    end

    if best then
        if CFG.mouseMode then
            -- 强制鼠标甩到头，不开枪，让玩家自己扣扳机
            mouseMoveTo(best)
        else
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, best.Position)
        end
        nextFire = os.clock() + (sniperMode and CFG.cooldown or CFG.autoCd)
    end
end)

print("[SNIPER] 已加载 · 所有枪：5° 内强制甩到头（不发包，子弹正常消耗）")
