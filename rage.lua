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
    -- 三个键的位置：X = 距右边缘像素，Y = 相对屏幕垂直中心
    tpX   = 26,  tpY   = -112, tpSize   = 84,
    aimX  = 26,  aimY  = 0,    aimSize  = 92,
    rageX = 26,  rageY = 118,  rageSize = 92,
}

local RAGE_CFG_FILE = "RivalsRageCfg.json"
local HttpService = game:GetService("HttpService")

local function saveCfg()
    pcall(function()
        if writefile then
            writefile(RAGE_CFG_FILE, HttpService:JSONEncode(CFG))
        end
    end)
end

local function loadCfg()
    pcall(function()
        if isfile and readfile and isfile(RAGE_CFG_FILE) then
            local t = HttpService:JSONDecode(readfile(RAGE_CFG_FILE))
            for k, v in pairs(t) do
                if CFG[k] ~= nil and type(CFG[k]) == type(v) then CFG[k] = v end
            end
        end
    end)
end

loadCfg()

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

-- 队友识别：Team 对象 / Team 属性 / 手动黑名单，任一层命中就算自己人
local ALLY_IDS = {}   -- 手动排除：[UserId] = true

local function isAlly(p)
    if p == LP then return true end
    if ALLY_IDS[p.UserId] then return true end
    if p.Team and LP.Team and p.Team == LP.Team then return true end
    local a, b = p:GetAttribute("Team"), LP:GetAttribute("Team")
    if a ~= nil and b ~= nil and a == b then return true end
    local na, nb = p:GetAttribute("TeamName"), LP:GetAttribute("TeamName")
    if type(na) == "string" and type(nb) == "string" and na == nb then return true end
    return false
end

getgenv().RageLiteAlly = function(userId, on)
    if on == false then ALLY_IDS[userId] = nil else ALLY_IDS[userId] = true end
end

local function nearestEnemy()
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local hum, ch = humOf(p)
            if hum and not isAlly(p) then
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
local aimOn = false

RunService:BindToRenderStep("RageLiteAim", Enum.RenderPriority.Camera.Value + 1, function()
    if not aimOn then return end
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

--═══════════ RAGE（Kicia 打法：贴到目标身上再发包，穿墙） ═══════════
local rageOn     = false
local rageNext   = 0
local rageStatus = "待命"
local rageTPNext = 0
local rageHome   = nil      -- 按下去之前站在哪
local rageBack   = true     -- 松手回原位

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

-- 传送到目标身边（服务端会认为你就在那儿，所以后面的包打得到）
local function rageTeleport(targetChar)
    local myChar = LP.Character
    if not myChar or not targetChar then return false end
    local thrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not thrp then return false end
    -- 站到目标身后 2 米并转身面对他
    local goal = thrp.CFrame * CFrame.new(0, 0, 2) * CFrame.Angles(0, math.rad(180), 0)
    local ok = pcall(function() myChar:PivotTo(goal) end)
    if not ok then
        local root = myChar:FindFirstChild("HumanoidRootPart")
        if root then pcall(function() root.CFrame = goal end) end
    end
    return true
end

local function rageFire()
    if not RIVALS.ready then rageStatus = "缺游戏模块（Utility/EnumLibrary）" return false end
    local now = os.clock()
    if now < rageNext then return false end

    local p = nearestEnemy()
    if not p then rageStatus = "没有目标（队友已排除）" return false end
    local _, ch = humOf(p)
    if not ch then return false end
    local head, body = partsOf(ch)
    local part = head or body
    if not part then rageStatus = "目标没有命中盒" return false end

    -- 先贴过去：贴了包才有效，这才是 ragebot 和"隔着地图发个假包"的区别
    if now >= rageTPNext then
        rageTeleport(ch)
        rageTPNext = now + 0.11
    end

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
        rageStatus = "贴脸开火 → " .. p.Name
        return true
    end
    rageStatus = "发包失败：" .. tostring(err)
    return false
end

task.spawn(function()
    while true do
        if rageOn then
            rageFire()
            task.wait(CFG.rageDelay)
        else
            task.wait(0.1)
        end
    end
end)

--═══════════ UI ═══════════
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

local function makeBtn(key, text, color)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Size = UDim2.fromOffset(CFG[key .. "Size"], CFG[key .. "Size"])
    b.Position = UDim2.new(1, -CFG[key .. "X"], 0.5, CFG[key .. "Y"])
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
    local s2 = Instance.new("UIStroke"); s2.Color = color; s2.Transparency = 0.45; s2.Parent = b
    return b
end

local btnTp   = makeBtn("tp",   "TP",   Color3.fromRGB(40, 210, 235))
local btnAim  = makeBtn("aim",  "AIM",  Color3.fromRGB(255, 70, 70))
local btnRage = makeBtn("rage", "RAGE", Color3.fromRGB(255, 175, 40))

local function applyLayout()
    local function set(btn, key)
        if not btn then return end
        btn.Size = UDim2.fromOffset(CFG[key .. "Size"], CFG[key .. "Size"])
        btn.Position = UDim2.new(1, -CFG[key .. "X"], 0.5, CFG[key .. "Y"])
    end
    set(btnTp, "tp")
    set(btnAim, "aim")
    set(btnRage, "rage")
end

local function paint(btn, on, base)
    btn.BackgroundTransparency = on and 0.22 or 0.72
    btn.Text = on and (base .. " ●") or base
end

-- TP 还是按住（松开立刻停，贴人这种事要能随时断）
btnTp.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        tpHold = true
        paint(btnTp, true, "TP")
    end
end)
btnTp.InputEnded:Connect(function()
    tpHold = false
    paint(btnTp, false, "TP")
end)

-- AIM / RAGE 是开关：点一下开，再点一下关
btnAim.MouseButton1Click:Connect(function()
    aimOn = not aimOn
    paint(btnAim, aimOn, "AIM")
end)

btnRage.MouseButton1Click:Connect(function()
    rageOn = not rageOn
    if rageOn then
        local ch = LP.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        rageHome = root and root.CFrame or nil
        rageNext, rageTPNext = 0, 0
    else
        rageNext = math.huge
        if rageBack and rageHome and LP.Character then
            pcall(function() LP.Character:PivotTo(rageHome) end)
        end
    end
    paint(btnRage, rageOn, "RAGE")
end)

--═══════════ 布局面板（齿轮） ═══════════
local function makeStepper(parent, label, key, step, minv, maxv, order)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 32)
    holder.BackgroundColor3 = Color3.fromRGB(27, 29, 38)
    holder.BorderSizePixel = 0
    holder.LayoutOrder = order
    holder.ZIndex = 4001
    holder.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -112, 1, 0)
    lbl.Position = UDim2.fromOffset(8, 0)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(230, 230, 238)
    lbl.Parent = holder

    local val = Instance.new("TextLabel")
    val.AnchorPoint = Vector2.new(1, 0.5)
    val.Position = UDim2.new(1, -40, 0.5, 0)
    val.Size = UDim2.fromOffset(40, 20)
    val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold
    val.TextSize = 12
    val.TextXAlignment = Enum.TextXAlignment.Center
    val.TextColor3 = Color3.fromRGB(120, 220, 255)
    val.Parent = holder

    local function mk(txt, dx)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, dx, 0.5, 0)
        b.Size = UDim2.fromOffset(28, 24)
        b.BackgroundColor3 = Color3.fromRGB(48, 51, 64)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.TextSize = 15
        b.Text = txt
        b.TextColor3 = Color3.fromRGB(240, 240, 245)
        b.ZIndex = 4002
        b.Parent = holder
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 5); cc.Parent = b
        return b
    end
    local minus = mk("-", -80)
    local plus  = mk("+", -6)

    local function upd() val.Text = tostring(math.floor(CFG[key] + 0.5)) end
    local function chg(d)
        CFG[key] = math.clamp(math.floor(CFG[key] + d + 0.5), minv, maxv)
        upd(); applyLayout(); saveCfg()
    end
    minus.MouseButton1Click:Connect(function() chg(-step) end)
    plus.MouseButton1Click:Connect(function() chg(step) end)
    upd()
end

local gear = Instance.new("TextButton")
gear.Size = UDim2.fromOffset(40, 40)
gear.AnchorPoint = Vector2.new(0, 0.5)
gear.Position = UDim2.new(0, 12, 0.5, 200)
gear.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
gear.BackgroundTransparency = 0.35
gear.BorderSizePixel = 0
gear.Font = Enum.Font.GothamBold
gear.TextSize = 16
gear.Text = "⚙"
gear.TextColor3 = Color3.fromRGB(200, 205, 220)
gear.ZIndex = 3000
gear.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = gear
end

local layoutPanel = Instance.new("Frame")
layoutPanel.Size = UDim2.fromOffset(228, 336)
layoutPanel.AnchorPoint = Vector2.new(0.5, 0.5)
layoutPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
layoutPanel.BackgroundColor3 = Color3.fromRGB(12, 13, 19)
layoutPanel.BackgroundTransparency = 0.05
layoutPanel.BorderSizePixel = 0
layoutPanel.Visible = false
layoutPanel.ZIndex = 4000
layoutPanel.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = layoutPanel
    local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 175, 40); st.Transparency = 0.5; st.Parent = layoutPanel
end

local head = Instance.new("TextButton")
head.Size = UDim2.new(1, 0, 0, 30)
head.BackgroundColor3 = Color3.fromRGB(30, 26, 18)
head.BorderSizePixel = 0
head.Font = Enum.Font.GothamBold
head.TextSize = 13
head.Text = "  按键位置   ×"
head.TextXAlignment = Enum.TextXAlignment.Left
head.TextColor3 = Color3.fromRGB(255, 190, 80)
head.AutoButtonColor = false
head.ZIndex = 4001
head.Parent = layoutPanel
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = head
end
head.MouseButton1Click:Connect(function() layoutPanel.Visible = false end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -40)
scroll.Position = UDim2.fromOffset(6, 34)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 175, 40)
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.ZIndex = 4001
scroll.Parent = layoutPanel
pcall(function()
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
end)
local lst = Instance.new("UIListLayout")
lst.Padding = UDim.new(0, 3)
lst.SortOrder = Enum.SortOrder.LayoutOrder
lst.Parent = scroll

local ord = 0
local function nextOrd() ord = ord + 1; return ord end
local function header(text)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, 0, 0, 22)
    h.BackgroundTransparency = 1
    h.Font = Enum.Font.GothamBold
    h.TextSize = 12
    h.Text = "  " .. text
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.TextColor3 = Color3.fromRGB(120, 200, 255)
    h.LayoutOrder = nextOrd()
    h.ZIndex = 4001
    h.Parent = scroll
end

header("TP 键")
makeStepper(scroll, "右边距", "tpX", 10, 0, 600, nextOrd())
makeStepper(scroll, "垂直",   "tpY", 10, -700, 700, nextOrd())
makeStepper(scroll, "大小",   "tpSize", 6, 50, 160, nextOrd())
header("AIM 键")
makeStepper(scroll, "右边距", "aimX", 10, 0, 600, nextOrd())
makeStepper(scroll, "垂直",   "aimY", 10, -700, 700, nextOrd())
makeStepper(scroll, "大小",   "aimSize", 6, 50, 160, nextOrd())
header("RAGE 键")
makeStepper(scroll, "右边距", "rageX", 10, 0, 600, nextOrd())
makeStepper(scroll, "垂直",   "rageY", 10, -700, 700, nextOrd())
makeStepper(scroll, "大小",   "rageSize", 6, 50, 160, nextOrd())

gear.MouseButton1Click:Connect(function()
    layoutPanel.Visible = not layoutPanel.Visible
end)

-- 状态条
local stat = Instance.new("TextLabel")
stat.Size = UDim2.fromOffset(268, 46)
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
        local allies = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and isAlly(p) then allies = allies + 1 end
        end
        stat.Text = string.format(
            "  TP %s   AIM %s   RAGE %s   队友 %d\n  %s · %s",
            tpHold and "●" or "○",
            aimOn and "●" or "○",
            rageOn and "●" or "○",
            allies, okTxt, rageStatus)
    end
end)

getgenv().RageLiteUnload = function()
    rageOn, aimOn, tpHold = false, false, false
    pcall(function() gui:Destroy() end)
    pcall(function() RunService:UnbindFromRenderStep("RageLiteAim") end)
    getgenv().RageLiteUnload = nil
end

print("[RAGE LITE] 已加载 · TP 按住 / AIM·RAGE 点一下开关 · 左侧 ⚙ 调位置")
