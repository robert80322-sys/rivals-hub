--[[
════════════════════════════════════════════════════════════
  RAGE LITE · 三个键
    TP   —— 按住：贴到最近的敌人身边 1 米
    AIM  —— 按住：暴力锁头，360° 无死角，自动跳过墙后的目标
    RAGE —— 按住：Kicia 那套 ragebot 发包，不看视线、直接穿墙打

  不依赖 main.lua，单独一个文件，手机触屏直接用。
    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/rage.lua"))()
════════════════════════════════════════════════════════════
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
if not LP then
    repeat task.wait(0.1) until Players.LocalPlayer
    LP = Players.LocalPlayer
end

local CFG = {
    tpRange   = 1.0,     -- 贴到敌人身上的距离（米）
    tpRate    = 0.12,    -- TP 刷新间隔
    aimPart   = "HitboxHead",
    rageDelay = 0.07,    -- ragebot 每次发包间隔
    maxDist   = 1200,
    bone      = true,    -- AIM 优先打头，被挡则打身体
}

--═══════════ Rivals 原生接口 ═══════════
local RIVALS = { ready = false }
pcall(function()
    local rem = RS:WaitForChild("Remotes", 8)
    local rep = rem and rem:WaitForChild("Replication", 5)
    local fighter = rep and rep:WaitForChild("Fighter", 5)
    if fighter then
        RIVALS.use = fighter:FindFirstChild("UseItem")
        RIVALS.cam = fighter:FindFirstChild("UpdateCameraRotation")
    end
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

--═══════════ 基础 ═══════════
local function humOf(plr)
    local ch = plr.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return hum, ch
end

local function partsOf(ch)
    local head = ch:FindFirstChild("HitboxHead") or ch:FindFirstChild("Head")
    local body = ch:FindFirstChild("HitboxBody") or ch:FindFirstChild("HumanoidRootPart")
    return head, body
end

local rp = RaycastParams.new()
pcall(function() rp.FilterType = Enum.RaycastFilterType.Exclude end)
rp.IgnoreWater = true

local function canSee(part, ch)
    if not part then return false end
    local cam = workspace.CurrentCamera
    local arr = { cam }
    if LP.Character then table.insert(arr, LP.Character) end
    rp.FilterDescendantsInstances = arr
    local hit = workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rp)
    return hit == nil or hit.Instance:IsDescendantOf(ch)
end

local function nearestEnemy()
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local hum, ch = humOf(p)
            if hum and not (p.Team and LP.Team and p.Team == LP.Team) then
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d <= CFG.maxDist and d < bd then bd = d; best = p end
                end
            end
        end
    end
    return best
end

--═══════════ TP ═══════════
local tpHold = false

local function doTP()
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local p = nearestEnemy()
    if not p then return false end
    local _, tch = humOf(p)
    local thrp = tch and tch:FindFirstChild("HumanoidRootPart")
    if not thrp then return false end
    local goal = thrp.CFrame * CFrame.new(0, 0, CFG.tpRange)
    local ok = pcall(function() ch0:PivotTo(goal) end)
    if not ok then pcall(function() root.CFrame = goal end) end
    return true
end

task.spawn(function()
    while true do
        if tpHold then doTP() end
        task.wait(CFG.tpRate)
    end
end)

--═══════════ AIM（360°，跳过墙后） ═══════════
local aimHold = false

RunService:BindToRenderStep("RageLiteAim", Enum.RenderPriority.Camera.Value + 1, function()
    if not aimHold then return end
    local p = nearestEnemy()
    if not p then return end
    local _, ch = humOf(p)
    if not ch then return end
    local head, body = partsOf(ch)
    local part = nil
    if CFG.bone then
        if head and canSee(head, ch) then part = head
        elseif body and canSee(body, ch) then part = body end
    else
        part = head or body
    end
    if not part then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position)
end)

--═══════════ RAGE（Kicia 发包，穿墙） ═══════════
local rageHold = false
local rageNext = 0
local rageStatus = "待命"

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

local function rageFire()
    if not RIVALS.ready then rageStatus = "缺游戏模块（Utility/EnumLibrary）" return false end
    local now = os.clock()
    if now < rageNext then return false end
    local p = nearestEnemy()
    if not p then rageStatus = "没有目标" return false end
    local _, ch = humOf(p)
    local head, body = partsOf(ch)
    local part = head or body
    if not part then rageStatus = "目标没有命中盒" return false end

    local item = equippedItem()
    if not item then rageStatus = "拿不到武器" return false end
    local objId = item.Get and item:Get("ObjectID")
    if not objId then rageStatus = "武器没有 ObjectID" return false end

    rageNext = now + CFG.rageDelay

    local myChar = LP.Character
    local myRoot = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Head"))
    local origin = myRoot and myRoot.Position or workspace.CurrentCamera.CFrame.Position
    local aim = CFrame.new(origin, part.Position)
    local shot = {
        [utf8.char(0)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(1)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(2)] = part,
        [utf8.char(3)] = RIVALS.util:EncodeCFrame(CFrame.Angles(0, math.pi / 2, 0)),
    }
    local ok, err = pcall(function()
        RIVALS.use:FireServer(
            objId,
            RIVALS.enums:ToEnum("StartShooting"),
            { [utf8.char(1)] = shot, [utf8.char(2)] = true },
            nil
        )
    end)
    if ok then
        rageStatus = "开火 → " .. p.Name
        return true
    end
    rageStatus = "发包失败：" .. tostring(err)
    return false
end

task.spawn(function()
    while true do
        if rageHold then
            rageFire()
            task.wait(CFG.rageDelay)
        else
            task.wait(0.1)
        end
    end
end)

--═══════════ UI：三个键 ═══════════
pcall(function()
    local host = (gethui and gethui()) or game:GetService("CoreGui")
    for _, v in ipairs(host:GetChildren()) do
        if v.Name == "RageLiteUI" then v:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "RageLiteUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okP = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not okP then gui.Parent = LP:WaitForChild("PlayerGui") end

local function makeBtn(text, color, yOffset, size)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(size, size)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, -26, 0.5, yOffset)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.72
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.ZIndex = 3000
    b.Parent = gui
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
    local s = Instance.new("UIStroke"); s.Color = color; s.Transparency = 0.45; s.Parent = b
    return b
end

local btnTp   = makeBtn("TP",   Color3.fromRGB(40, 210, 235), -112, 84)
local btnAim  = makeBtn("AIM",  Color3.fromRGB(255, 70, 70),    0,   92)
local btnRage = makeBtn("RAGE", Color3.fromRGB(255, 175, 40),   118, 92)

local function bindHold(btn, setter)
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            setter(true)
            btn.BackgroundTransparency = 0.42
        end
    end)
    btn.InputEnded:Connect(function()
        setter(false)
        btn.BackgroundTransparency = 0.72
    end)
end

bindHold(btnTp,   function(v) tpHold = v   end)
bindHold(btnAim,  function(v) aimHold = v  end)
bindHold(btnRage, function(v) rageHold = v end)

-- 状态条
local stat = Instance.new("TextLabel")
stat.Size = UDim2.fromOffset(260, 46)
stat.AnchorPoint = Vector2.new(0, 1)
stat.Position = UDim2.new(0, 10, 1, -8)
stat.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
stat.BackgroundTransparency = 0.35
stat.BorderSizePixel = 0
stat.Font = Enum.Font.Code
stat.TextSize = 11
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextColor3 = Color3.fromRGB(200, 205, 220)
stat.Text = "  RAGE LITE 启动中…"
stat.ZIndex = 3000
stat.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = stat
end

task.spawn(function()
    while true do
        task.wait(0.35)
        local okTxt = RIVALS.ready and "原生接口 OK" or "原生接口 缺"
        stat.Text = string.format(
            "  TP %s   AIM %s   RAGE %s\n  %s · %s",
            tpHold and "●" or "○",
            aimHold and "●" or "○",
            rageHold and "●" or "○",
            okTxt, rageStatus)
    end
end)

getgenv().RageLiteUnload = function()
    pcall(function() gui:Destroy() end)
    pcall(function() RunService:UnbindFromRenderStep("RageLiteAim") end)
    getgenv().RageLiteUnload = nil
end

print("[RAGE LITE] 已加载 · 右侧 TP / AIM / RAGE 三个键，按住生效")
