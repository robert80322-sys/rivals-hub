--[[
════════════════════════════════════════════════════════════
  SNIPER · 5 度自动甩狙
    只在手里拿狙时工作：
      准星 5° 内出现敌人 → 瞬间甩到头上 → 直接开枪
    不插值、不弹簧，就是硬甩，要的就是快。

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

local CFG = {
    snapDeg    = 5.0,    -- 准星多少度以内才触发
    cooldown   = 1.1,    -- 开枪后等多久（狙击上膛时间）
    aimDist    = 800,    -- 目标最远距离
    teamCheck  = true,
    visibleOnly= true,   -- 隔着墙不甩
    useStartAiming = true, -- 先发一次开镜，再开枪（狙通常需要）
}

--═══════════ 接口 ═══════════
local RIVALS = { ready = false }
pcall(function()
    local rem = RS:WaitForChild("Remotes", 15)
    local rep = rem and rem:WaitForChild("Replication", 10)
    local fighter = rep and rep:WaitForChild("Fighter", 10)
    if fighter then RIVALS.use = fighter:WaitForChild("UseItem", 10) end
    local mods = RS:WaitForChild("Modules", 10)
    local util = mods and mods:WaitForChild("Utility", 10)
    local enums = mods and mods:WaitForChild("EnumLibrary", 10)
    if util  then pcall(function() RIVALS.util  = require(util)  end) end
    if enums then pcall(function() RIVALS.enums = require(enums) end) end
    RIVALS.ready = (RIVALS.use and RIVALS.util and RIVALS.enums) ~= nil
    print(string.format("[SNIPER] 接口 use=%s util=%s enums=%s",
        tostring(RIVALS.use ~= nil), tostring(RIVALS.util ~= nil), tostring(RIVALS.enums ~= nil)))
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

--═══════════ 开火 ═══════════
local nextFire = 0

local function fireAt(head)
    local item = equippedItem()
    if not item then return false end
    local objId = item.Get and item:Get("ObjectID")
    if not objId then return false end

    local cam = workspace.CurrentCamera
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local originPos = myRoot and (myRoot.Position + Vector3.new(0, 1.5, 0)) or cam.CFrame.Position
    local targetPos = head.Position

    local aimCF  = CFrame.lookAt(originPos, targetPos)
    local targetCF = head.CFrame
    local objSpace = targetCF:ToObjectSpace(CFrame.new(targetPos))

    local C0, C1, C2, C3 = string.char(0), string.char(1), string.char(2), string.char(3)
    local shot = {
        [C0] = RIVALS.util:EncodeCFrame(aimCF),
        [C1] = RIVALS.util:EncodeCFrame(targetCF),
        [C2] = head,
        [C3] = RIVALS.util:EncodeCFrame(objSpace),
    }
    local data = { [C1] = shot, [C2] = true }

    local ok = true
    if CFG.useStartAiming then
        ok = pcall(function()
            RIVALS.use:FireServer(objId, RIVALS.enums:ToEnum("StartAiming"), data, nil)
        end)
    end
    pcall(function()
        RIVALS.use:FireServer(objId, RIVALS.enums:ToEnum("StartShooting"), data, nil)
    end)
    return ok
end

--═══════════ 主循环：5 度内甩头 + 开枪 ═══════════
RunService.RenderStepped:Connect(function()
    if not RIVALS.ready then return end
    if os.clock() < nextFire then return end

    local item = equippedItem()
    if not item or not isSniper(item) then return end

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

    if best then
        -- 硬甩：不做任何插值，直接指过去
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, best.Position)
        fireAt(best)
        nextFire = os.clock() + CFG.cooldown
    end
end)

print("[SNIPER] 已加载 · 持狙时 5° 内自动甩头开枪")
