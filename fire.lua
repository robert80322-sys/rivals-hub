--[[
════════════════════════════════════════════════════════════
  FIRE LITE · 只有一个开关
    屏幕上就一个圆键，点一下 = 自动开火开，再点一下 = 关。
    准星附近有敌人就替你把枪打出去，没有别的东西。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/fire.lua"))()
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
    on      = false,
    window  = 70,      -- 准星多少像素内有敌人才开枪
    maxDist = 1000,    -- 目标最远距离
}

--═══════════ 游戏接口 ═══════════
local RIVALS = { ready = false }
pcall(function()
    local rem = RS:WaitForChild("Remotes", 8)
    local rep = rem and rem:WaitForChild("Replication", 5)
    local fighter = rep and rep:WaitForChild("Fighter", 5)
    if fighter then RIVALS.use = fighter:FindFirstChild("UseItem") end
    local mods = RS:FindFirstChild("Modules")
    local util = mods and mods:FindFirstChild("Utility")
    local enums = mods and mods:FindFirstChild("EnumLibrary")
    if util  then pcall(function() RIVALS.util  = require(util)  end) end
    if enums then pcall(function() RIVALS.enums = require(enums) end) end
    RIVALS.ready = (RIVALS.use ~= nil and RIVALS.util ~= nil and RIVALS.enums ~= nil)
end)

local function findModule(name)
    local ps  = LP:FindFirstChild("PlayerScripts")
    local roots = {}
    local rsm = RS:FindFirstChild("Modules")
    local psm = ps and ps:FindFirstChild("Modules")
    if rsm then table.insert(roots, rsm) end
    if psm then table.insert(roots, psm) end
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ModuleScript") and d.Name == name then return d end
        end
    end
    return nil
end

local function equippedItem()
    local ident
    pcall(function() if getthreadidentity then ident = getthreadidentity() end end)
    local ok, item = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 2) end
        local mod = findModule("FighterController")
        if not mod then return nil end
        local FC = require(mod)
        local fighter = FC and FC:GetFighter(LP)
        if not fighter then return nil end
        if fighter.EquippedItem then return fighter.EquippedItem end
        if fighter.Items then
            local _, it = next(fighter.Items)
            return it
        end
        return nil
    end)
    if setthreadidentity and ident then pcall(setthreadidentity, ident) end
    return ok and item or nil
end

local function isTeammate(p)
    if p == LP then return true end
    if p.Team and LP.Team and p.Team == LP.Team then return true end
    local a, b = p:GetAttribute("Team"), LP:GetAttribute("Team")
    if a ~= nil and b ~= nil and a == b then return true end
    return false
end

--═══════════ 自动开火 ═══════════
local fireNext = 0

local function tick()
    if not CFG.on then return end
    if not RIVALS.ready then return end
    local now = os.clock()
    if now < fireNext then return end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

    local bestPart, bestD = nil, CFG.window
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")

    for _, p in ipairs(Players:GetPlayers()) do
        if not isTeammate(p) then
            local ch = p.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local part = ch:FindFirstChild("HitboxHead") or ch:FindFirstChild("Head")
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if part and hrp and myRoot then
                    if (hrp.Position - myRoot.Position).Magnitude <= CFG.maxDist then
                        local sp, on = cam:WorldToViewportPoint(part.Position)
                        if on and sp.Z > 0 then
                            local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                            if d < bestD then bestD = d; bestPart = part end
                        end
                    end
                end
            end
        end
    end

    if not bestPart then return end

    local item = equippedItem()
    if not item then return end
    local objId = item.Get and item:Get("ObjectID")
    if not objId then return end

    local cd = 0.12
    local info = item.Info
    if type(info) == "table" then
        local raw = info.FireCooldown or info.ShootCooldown or info.AttackCooldown
        if type(raw) == "number" and raw > 0 then cd = raw end
    end
    fireNext = now + math.max(cd, 0.05)

    local origin = myRoot.Position
    local aim = CFrame.new(origin, bestPart.Position)
    local shot = {
        [utf8.char(0)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(1)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(2)] = bestPart,
        [utf8.char(3)] = RIVALS.util:EncodeCFrame(CFrame.Angles(0, math.pi / 2, 0)),
    }
    pcall(function()
        RIVALS.use:FireServer(
            objId,
            RIVALS.enums:ToEnum("StartShooting"),
            { [utf8.char(1)] = shot, [utf8.char(2)] = true },
            nil
        )
    end)
end

task.spawn(function()
    while true do
        tick()
        task.wait(0.03)
    end
end)

--═══════════ 一个按钮 ═══════════
pcall(function()
    local host = (gethui and gethui()) or game:GetService("CoreGui")
    for _, v in ipairs(host:GetChildren()) do
        if v.Name == "FireLiteUI" then v:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "FireLiteUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okP = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not okP then gui.Parent = LP:WaitForChild("PlayerGui") end

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(88, 88)
btn.AnchorPoint = Vector2.new(1, 0.5)
btn.Position = UDim2.new(1, -26, 0.5, 60)
btn.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
btn.BackgroundTransparency = 0.72
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.TextSize = 13
btn.Text = "FIRE"
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.ZIndex = 3000
btn.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = btn
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 225, 100); s.Transparency = 0.45; s.Parent = btn
end

btn.MouseButton1Click:Connect(function()
    CFG.on = not CFG.on
    btn.BackgroundTransparency = CFG.on and 0.2 or 0.72
    btn.Text = CFG.on and "FIRE ON" or "FIRE"
    fireNext = 0
end)

getgenv().FireLiteUnload = function()
    pcall(function() gui:Destroy() end)
    getgenv().FireLiteUnload = nil
end

print("[FIRE LITE] 已加载 · 右侧黄色 FIRE 键，点一下开自动开火")
