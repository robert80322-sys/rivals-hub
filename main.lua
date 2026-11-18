--[[
════════════════════════════════════════════════════════════
  Rivals Hub  v7   ·   LittleCodeSauce
  手机执行器：Delta / Codex / Fluxus
  本轮新增（照着 Kicia/LxYHook 的配置表抄的）：
    · 第三人称（相机后拉，高/远可调）
    · 相机视野 FOV 覆盖
    · 击中音效 Hitsound（对面掉血就响）
  已有：ESP / 自瞄 / Trigger / 真静默（UpdateCameraRotation 发包）
        / 命中盒瞄准（HitboxHead·HitboxBody）/ 贴人 TP / 自动重生
  用法：执行器里 loadstring 加载 loader.lua，或直接粘本文件
════════════════════════════════════════════════════════════
]]
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
if not LP then
    repeat task.wait(0.1) until Players.LocalPlayer
    LP = Players.LocalPlayer
end

--═══════════ 1. 配置 ═══════════
local CFG = {
    esp        = true,
    aim        = false,
    trigger    = false,
    silent     = false,
    speed      = false,
    jump       = false,
    visibleOnly= false,
    teamCheck  = true,
    selfBox    = true,
    part       = "Head",
    fov        = 170,
    smooth     = 0.22,
    maxDist    = 1500,
    speedVal   = 60,
    jumpVal    = 85,
    -- 传送 / autofarm
    tp         = false,
    tpFire     = false,
    tpMode     = "nearest",   -- nearest / random / weak
    tpOffset   = "behind",    -- behind / above / front
    tpRange    = 12,
    tpRate     = 0.15,
    -- 游戏原生接口
    silentRemote = true,   -- 用 UpdateCameraRotation 做静默
    autoRespawn  = false,  -- 死后自动重生
    hitboxAim    = true,   -- 瞄准/透视用 HitboxHead 判定盒
    -- 视觉
    thirdPerson  = false,
    tpCamY       = 2,
    tpCamZ       = 6,
    camFov       = false,
    fovVal       = 90,
    hitSound     = false,
    -- 手机上 mouse1press / SendMouseButtonEvent 会召唤鼠标指针，多指时乱飘，默认关
    mouseSim     = false,
    -- 按键布局：X = 距屏幕右边缘的像素，Y = 相对屏幕垂直中心的像素
    aimX   = 18,  aimY   = 0,
    tpX    = 30,  tpY    = -108,
    bhopX  = 30,  bhopY  = 108,
    aimSize = 94, tpSize = 76, bhopSize = 76,
    bhopAuto = false,   -- 不按住也连跳
    -- 陀螺仪
    gyro      = false,
    gyroSens  = 1.0,    -- 灵敏度倍率
    gyroInvY  = false,  -- 左右反向
    gyroInvX  = false,  -- 上下反向
}

-- 仓库地址（改了仓库记得同步改这里）
local RAW_BASE = "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/"
local RAW_MIRRORS = {
    RAW_BASE,
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/",
}

local CFG_FILE = "RivalsCFG_v4.json"

local function loadCfg()
    pcall(function()
        if isfile and readfile and isfile(CFG_FILE) then
            local t = HttpService:JSONDecode(readfile(CFG_FILE))
            for k, v in pairs(t) do
                if CFG[k] ~= nil and type(CFG[k]) == type(v) then CFG[k] = v end
            end
        end
    end)
end

local function saveCfg()
    pcall(function()
        if writefile then writefile(CFG_FILE, HttpService:JSONEncode(CFG)) end
    end)
end

loadCfg()

--═══════════ 2. 工具 ═══════════
local function getAimPart(ch)
    if not ch then return nil end
    if CFG.hitboxAim then
        return ch:FindFirstChild("HitboxHead")
            or ch:FindFirstChild(CFG.part)
            or ch:FindFirstChild("Head")
    end
    return ch:FindFirstChild(CFG.part)
        or ch:FindFirstChild("UpperTorso")
        or ch:FindFirstChild("Head")
end

local function sameTeam(p)
    return p.Team ~= nil and LP.Team ~= nil and p.Team == LP.Team
end

local rayP = RaycastParams.new()
pcall(function() rayP.FilterType = Enum.RaycastFilterType.Exclude end)
rayP.IgnoreWater = true

local function canSee(part)
    local cam = workspace.CurrentCamera
    if not cam or not part then return false end
    local arr = { cam }
    if LP.Character then table.insert(arr, LP.Character) end
    rayP.FilterDescendantsInstances = arr
    local origin = cam.CFrame.Position
    local hit = workspace:Raycast(origin, part.Position - origin, rayP)
    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

--═══════════ 3. UI 宿主 ═══════════
local function uiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2, c = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and c then return c end
    return LP:WaitForChild("PlayerGui")
end

pcall(function()
    local host = uiParent()
    for _, v in ipairs(host:GetChildren()) do
        if v.Name:sub(1, 12) == "RivalsAssist" then v:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "RivalsAssist4"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local okParent = pcall(function() gui.Parent = uiParent() end)
if not okParent then gui.Parent = LP:WaitForChild("PlayerGui") end

--═══════════ 4. FOV 圆环 ═══════════
local RING_SEGS = 44
local ring = {}
for i = 1, RING_SEGS do
    local s = Instance.new("Frame")
    s.Size = UDim2.fromOffset(7, 2)
    s.AnchorPoint = Vector2.new(0.5, 0.5)
    s.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    s.BackgroundTransparency = 0.45
    s.BorderSizePixel = 0
    s.Visible = false
    s.ZIndex = 950
    s.Parent = gui
    ring[i] = s
end

local function layoutRing()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local cx, cy = vp.X * 0.5, vp.Y * 0.5
    local on = CFG.aim
    for i, s in ipairs(ring) do
        local a = (i - 1) / RING_SEGS * math.pi * 2
        s.Position = UDim2.fromOffset(cx + math.cos(a) * CFG.fov, cy + math.sin(a) * CFG.fov)
        s.Rotation = math.deg(a)
        s.Visible = on
    end
end

--═══════════ 5. ESP 池 ═══════════
local esp = {}

local function newBox(color)
    local b = {}
    for i = 1, 4 do
        local f = Instance.new("Frame")
        f.BackgroundColor3 = color
        f.BorderSizePixel = 0
        f.Visible = false
        f.ZIndex = 900
        f.Parent = gui
        b[i] = f
    end
    return b
end

local function hideBox(b)
    for i = 1, 4 do b[i].Visible = false end
end

local function ensure(p, color)
    local d = esp[p]
    if d then return d end
    d = {}
    d.box = newBox(color)

    d.name = Instance.new("TextLabel")
    d.name.BackgroundTransparency = 1
    d.name.Font = Enum.Font.GothamBold
    d.name.TextSize = 13
    d.name.TextColor3 = color
    d.name.TextStrokeTransparency = 0.25
    d.name.TextXAlignment = Enum.TextXAlignment.Center
    d.name.Visible = false
    d.name.ZIndex = 901
    d.name.Parent = gui

    d.hpBg = Instance.new("Frame")
    d.hpBg.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    d.hpBg.BackgroundTransparency = 0.25
    d.hpBg.BorderSizePixel = 0
    d.hpBg.Visible = false
    d.hpBg.ZIndex = 901
    d.hpBg.Parent = gui

    d.hpFill = Instance.new("Frame")
    d.hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
    d.hpFill.BorderSizePixel = 0
    d.hpFill.ZIndex = 902
    d.hpFill.Parent = d.hpBg

    d.dist = Instance.new("TextLabel")
    d.dist.BackgroundTransparency = 1
    d.dist.Font = Enum.Font.Gotham
    d.dist.TextSize = 11
    d.dist.TextColor3 = Color3.fromRGB(240, 240, 240)
    d.dist.TextStrokeTransparency = 0.35
    d.dist.TextXAlignment = Enum.TextXAlignment.Center
    d.dist.Visible = false
    d.dist.ZIndex = 901
    d.dist.Parent = gui

    esp[p] = d
    return d
end

local function drop(p)
    local d = esp[p]
    if not d then return end
    pcall(function()
        for i = 1, 4 do d.box[i]:Destroy() end
        d.name:Destroy(); d.hpBg:Destroy(); d.dist:Destroy()
    end)
    esp[p] = nil
end

--═══════════ 6. 面板（可滚动） ═══════════
local _vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(720, 1280)
local _panelH = math.clamp(math.floor(_vp.Y * 0.62), 300, 460)
local box = Instance.new("Frame")
box.Size = UDim2.fromOffset(228, _panelH)
box.AnchorPoint = Vector2.new(0.5, 0)
box.Position = UDim2.new(0.5, 0, 0.10, 66)
box.BackgroundColor3 = Color3.fromRGB(13, 14, 20)
box.BackgroundTransparency = 0.1
box.BorderSizePixel = 0
box.Visible = false
box.ZIndex = 3000
box.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = box
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60, 255, 170); s.Transparency = 0.6; s.Parent = box
end

local title = Instance.new("TextButton")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
title.BorderSizePixel = 0
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Text = "  RIVALS v8.2   ·   拖动移动"
title.TextColor3 = Color3.fromRGB(70, 255, 175)
title.TextXAlignment = Enum.TextXAlignment.Left
title.AutoButtonColor = false
title.ZIndex = 3001
title.Parent = box
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = title
end

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(1, 0, 1, -30)
panel.Position = UDim2.fromOffset(0, 30)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 3
panel.ScrollBarImageColor3 = Color3.fromRGB(80, 255, 175)
panel.ScrollBarImageTransparency = 0.45
panel.CanvasSize = UDim2.fromOffset(0, 0)
panel.ZIndex = 3001
panel.Parent = box
pcall(function()
    panel.ScrollingDirection = Enum.ScrollingDirection.Y
    panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
    panel.ElasticBehavior = Enum.ElasticBehavior.Never
end)
do
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 3)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = panel
    local pd = Instance.new("UIPadding")
    pd.PaddingTop = UDim.new(0, 4)
    pd.PaddingBottom = UDim.new(0, 6)
    pd.PaddingLeft = UDim.new(0, 4)
    pd.PaddingRight = UDim.new(0, 4)
    pd.Parent = panel
end

local dragging, dragStart, panelStart = false, nil, nil
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = i.Position
        panelStart = box.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and dragStart
    and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - dragStart
        box.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + d.X,
                                 panelStart.Y.Scale, panelStart.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local rows = {}
local order = 0
local aimBtn          -- 前向声明：面板行闭包要用
local stat            -- 前向声明：状态栏
local savePoint       -- 前向声明：记录点
local myChar, applyTP, tpOnce, pickTP, goalFrom   -- 前向声明：传送函数
local loadKicia, unloadKicia                      -- 前向声明：Kicia 整套
local applyLayout                                 -- 前向声明：按键布局
local openSkincare                                -- 前向声明：皮肤面板

local function refreshRows()
    for _, r in ipairs(rows) do
        local on = r.get()
        r.st.Text = on and "ON" or "OFF"
        r.st.TextColor3 = on and Color3.fromRGB(90, 255, 160) or Color3.fromRGB(120, 120, 130)
    end
    layoutRing()
end

local function addHeader(text)
    order = order + 1
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, 0, 0, 22)
    h.BackgroundTransparency = 1
    h.Font = Enum.Font.GothamBold
    h.TextSize = 12
    h.Text = "  " .. text
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.TextColor3 = Color3.fromRGB(110, 200, 255)
    h.LayoutOrder = order
    h.ZIndex = 3001
    h.Parent = panel
end

local function addRow(label, getter, setter)
    order = order + 1
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 33)
    b.BackgroundColor3 = Color3.fromRGB(27, 29, 38)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.Text = "  " .. label
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextColor3 = Color3.fromRGB(232, 232, 238)
    b.AutoButtonColor = true
    b.LayoutOrder = order
    b.ZIndex = 3002
    b.Parent = panel

    local st = Instance.new("TextLabel")
    st.AnchorPoint = Vector2.new(1, 0.5)
    st.Position = UDim2.new(1, -10, 0.5, 0)
    st.Size = UDim2.fromOffset(42, 20)
    st.BackgroundTransparency = 1
    st.Font = Enum.Font.GothamBold
    st.TextSize = 12
    st.TextXAlignment = Enum.TextXAlignment.Right
    st.Text = "OFF"
    st.TextColor3 = Color3.fromRGB(120, 120, 130)
    st.Parent = b

    b.MouseButton1Click:Connect(function()
        setter(not getter())
        saveCfg()
        refreshRows()
    end)
    rows[#rows + 1] = { st = st, get = getter }
end

local function addButton(label, action)
    order = order + 1
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 33)
    b.BackgroundColor3 = Color3.fromRGB(30, 40, 52)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.Text = "  " .. label
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextColor3 = Color3.fromRGB(150, 230, 255)
    b.AutoButtonColor = true
    b.LayoutOrder = order
    b.ZIndex = 3002
    b.Parent = panel
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = b
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(action)
        if not ok then warn("[Rivals v5] " .. tostring(err)) end
    end)
end

local function addStepper(label, getter, setter, step)
    order = order + 1
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 33)
    holder.BackgroundColor3 = Color3.fromRGB(27, 29, 38)
    holder.BorderSizePixel = 0
    holder.LayoutOrder = order
    holder.ZIndex = 3002
    holder.Parent = panel

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -110, 1, 0)
    lbl.Position = UDim2.fromOffset(8, 0)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(232, 232, 238)
    lbl.Parent = holder

    local val = Instance.new("TextLabel")
    val.AnchorPoint = Vector2.new(1, 0.5)
    val.Position = UDim2.new(1, -38, 0.5, 0)
    val.Size = UDim2.fromOffset(38, 20)
    val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold
    val.TextSize = 12
    val.TextXAlignment = Enum.TextXAlignment.Center
    val.TextColor3 = Color3.fromRGB(90, 255, 160)
    val.Parent = holder

    local function mk(txt, dx)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, dx, 0.5, 0)
        b.Size = UDim2.fromOffset(30, 26)
        b.BackgroundColor3 = Color3.fromRGB(48, 51, 64)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.Text = txt
        b.TextColor3 = Color3.fromRGB(238, 238, 244)
        b.Parent = holder
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = b
        return b
    end

    local minus = mk("-", -78)
    local plus  = mk("+", -6)

    local function upd()
        val.Text = tostring(math.floor(getter() + 0.5))
    end

    minus.MouseButton1Click:Connect(function()
        setter(getter() - step); upd(); saveCfg()
    end)
    plus.MouseButton1Click:Connect(function()
        setter(getter() + step); upd(); saveCfg()
    end)

    upd()
    return upd
end

addHeader("识别")
addRow("ESP 透视",        function() return CFG.esp end,         function(v) CFG.esp = v end)
addRow("只锁可见目标",    function() return CFG.visibleOnly end, function(v) CFG.visibleOnly = v end)
addRow("队友过滤",        function() return CFG.teamCheck end,   function(v) CFG.teamCheck = v end)

addHeader("瞄准")
addRow("自瞄 AIM",        function() return CFG.aim end,         function(v) CFG.aim = v; if aimBtn then aimBtn.Visible = v end end)
addRow("自动开火",        function() return CFG.trigger end,     function(v) CFG.trigger = v end)
addRow("鼠标模拟开火",    function() return CFG.mouseSim end,    function(v) CFG.mouseSim = v end)
addRow("静默·官方接口",   function() return CFG.silentRemote end, function(v) CFG.silentRemote = v end)
addRow("静默·Hook",       function() return CFG.silent end,      function(v) CFG.silent = v; installSilent() end)
addRow("命中盒瞄准",      function() return CFG.hitboxAim end,   function(v) CFG.hitboxAim = v end)
addRow("锁头部",          function() return CFG.part == "Head" end,
    function(v) CFG.part = v and "Head" or "Torso" end)
addStepper("FOV",    function() return CFG.fov end,    function(v) CFG.fov = math.clamp(v, 30, 500) end, 10)
addStepper("平滑",   function() return CFG.smooth * 100 end,
    function(v) CFG.smooth = math.clamp(v, 5, 100) / 100 end, 5)

addHeader("移动")
addRow("加速",            function() return CFG.speed end,       function(v) CFG.speed = v end)
addRow("超级跳",          function() return CFG.jump end,        function(v) CFG.jump = v end)

addHeader("视角 / 音效")
addRow("第三人称",       function() return CFG.thirdPerson end, function(v) CFG.thirdPerson = v end)
addRow("相机视野覆盖",   function() return CFG.camFov end,      function(v) CFG.camFov = v end)
addRow("击中音效",       function() return CFG.hitSound end,    function(v) CFG.hitSound = v end)
addStepper("视野值", function() return CFG.fovVal end, function(v) CFG.fovVal = math.clamp(v, 40, 130) end, 5)
addStepper("相机高", function() return CFG.tpCamY end, function(v) CFG.tpCamY = math.clamp(v, -5, 12) end, 1)
addStepper("相机远", function() return CFG.tpCamZ end, function(v) CFG.tpCamZ = math.clamp(v, 0, 20) end, 1)
addRow("陀螺仪", function() return CFG.gyro end, function(v)
    CFG.gyro = v
    if v and not _G.GYRO_OK then
        stat.Text = "  这台设备没报陀螺仪（GYROSCOPE 未启用）"
    end
end)
addStepper("陀螺灵敏度", function() return CFG.gyroSens * 100 end,
    function(v) CFG.gyroSens = math.clamp(v, 10, 500) / 100 end, 10)
addRow("陀螺左右反向", function() return CFG.gyroInvY end, function(v) CFG.gyroInvY = v end)
addRow("陀螺上下反向", function() return CFG.gyroInvX end, function(v) CFG.gyroInvX = v end)

addHeader("传送 / 刷人")
addRow("自动重生",        function() return CFG.autoRespawn end, function(v) CFG.autoRespawn = v end)
addRow("贴人 TP",         function() return CFG.tp end,          function(v) CFG.tp = v end)
addRow("贴上就开火",      function() return CFG.tpFire end,      function(v) CFG.tpFire = v end)
addRow("站背后",          function() return CFG.tpOffset == "behind" end,
    function(v) CFG.tpOffset = v and "behind" or "above" end)
addRow("选最近的",        function() return CFG.tpMode == "nearest" end,
    function(v) CFG.tpMode = v and "nearest" or "random" end)
addButton("→  立即贴一次", function() tpOnce() end)
addButton("◎  记录当前位置", function()
    local _, root = myChar()
    if root then savePoint = root.CFrame; stat.Text = "  已记录：" .. tostring(math.floor(root.Position.X)) .. "," .. tostring(math.floor(root.Position.Y)) .. "," .. tostring(math.floor(root.Position.Z)) end
end)
addButton("←  回记录点", function()
    if savePoint then applyTP(savePoint) else stat.Text = "  还没有记录点" end
end)
addStepper("贴身距离", function() return CFG.tpRange end, function(v) CFG.tpRange = math.clamp(v, 3, 30) end, 1)

addHeader("按键布局 · 右边距 / 垂直偏移")
addStepper("AIM 右边距",  function() return CFG.aimX end,  function(v) CFG.aimX = math.clamp(v, 0, 600); applyLayout() end, 10)
addStepper("AIM 垂直",    function() return CFG.aimY end,  function(v) CFG.aimY = math.clamp(v, -700, 700); applyLayout() end, 10)
addStepper("AIM 大小",    function() return CFG.aimSize end, function(v) CFG.aimSize = math.clamp(v, 50, 160); applyLayout() end, 6)
addStepper("TP 右边距",   function() return CFG.tpX end,   function(v) CFG.tpX = math.clamp(v, 0, 600); applyLayout() end, 10)
addStepper("TP 垂直",     function() return CFG.tpY end,   function(v) CFG.tpY = math.clamp(v, -700, 700); applyLayout() end, 10)
addStepper("TP 大小",     function() return CFG.tpSize end, function(v) CFG.tpSize = math.clamp(v, 40, 160); applyLayout() end, 6)
addStepper("BHOP 右边距", function() return CFG.bhopX end, function(v) CFG.bhopX = math.clamp(v, 0, 600); applyLayout() end, 10)
addStepper("BHOP 垂直",   function() return CFG.bhopY end, function(v) CFG.bhopY = math.clamp(v, -700, 700); applyLayout() end, 10)
addStepper("BHOP 大小",   function() return CFG.bhopSize end, function(v) CFG.bhopSize = math.clamp(v, 40, 160); applyLayout() end, 6)
addRow("自动连跳（免按）", function() return CFG.bhopAuto end, function(v) CFG.bhopAuto = v end)

addHeader("外观")
addButton("🎨 打开皮肤列表（Skinchanger）", function() openSkincare() end)
addButton("↩ 换回原皮肤", function()
    if originalSkin then stat.Text = "  " .. applySkin(originalSkin) else stat.Text = "  还没换过皮肤" end
end)

addHeader("Kicia 全套 · ragebot / 物品修改器")
addButton("⚡ 载入 Kicia 全套（2.1MB）", function()
    stat.Text = "  正在拉 Kicia…"
    task.spawn(function()
        local msg = loadKicia()
        stat.Text = "  " .. msg
    end)
end)
addButton("⏏ 卸载 Kicia 全套", function()
    stat.Text = "  " .. unloadKicia()
end)

stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1, 0, 0, 40)
stat.BackgroundTransparency = 1
stat.Font = Enum.Font.Code
stat.TextSize = 11
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextColor3 = Color3.fromRGB(170, 175, 190)
stat.Text = "  加载中…"
stat.LayoutOrder = 99
stat.ZIndex = 3001
stat.Parent = panel

-- 开面板按钮
local fab = Instance.new("TextButton")
fab.Size = UDim2.fromOffset(56, 56)
fab.AnchorPoint = Vector2.new(0.5, 0)
fab.Position = UDim2.new(0.5, 0, 0.10, -2)
fab.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
fab.BackgroundTransparency = 0.1
fab.BorderSizePixel = 0
fab.Font = Enum.Font.GothamBold
fab.TextSize = 16
fab.Text = "R"
fab.TextColor3 = Color3.fromRGB(80, 255, 175)
fab.ZIndex = 3000
fab.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = fab
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(80, 255, 175); s.Transparency = 0.4; s.Parent = fab
end

fab.MouseButton1Click:Connect(function()
    box.Visible = not box.Visible
    if box.Visible then refreshRows() end
end)

-- AIM 触屏按住键
aimBtn = Instance.new("TextButton")
aimBtn.Size = UDim2.fromOffset(CFG.aimSize, CFG.aimSize)
aimBtn.AnchorPoint = Vector2.new(1, 0.5)
aimBtn.Position = UDim2.new(1, -CFG.aimX, 0.5, CFG.aimY)
aimBtn.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
aimBtn.BackgroundTransparency = 0.75
aimBtn.BorderSizePixel = 0
aimBtn.Font = Enum.Font.GothamBold
aimBtn.TextSize = 13
aimBtn.Text = "AIM"
aimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
aimBtn.Visible = CFG.aim
aimBtn.ZIndex = 3000
aimBtn.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = aimBtn
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 90, 90); s.Transparency = 0.5; s.Parent = aimBtn
end

local holding = false
aimBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        holding = true
        aimBtn.BackgroundTransparency = 0.45
    end
end)
aimBtn.InputEnded:Connect(function()
    holding = false
    aimBtn.BackgroundTransparency = 0.75
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        holding = false
        aimBtn.BackgroundTransparency = 0.75
    end
end)

-- TP 快捷键（右侧，AIM 上方）
local tpBtn = Instance.new("TextButton")
tpBtn.Size = UDim2.fromOffset(CFG.tpSize, CFG.tpSize)
tpBtn.AnchorPoint = Vector2.new(1, 0.5)
tpBtn.Position = UDim2.new(1, -CFG.tpX, 0.5, CFG.tpY)
tpBtn.BackgroundColor3 = Color3.fromRGB(40, 220, 255)
tpBtn.BackgroundTransparency = 0.72
tpBtn.BorderSizePixel = 0
tpBtn.Font = Enum.Font.GothamBold
tpBtn.TextSize = 13
tpBtn.Text = "TP"
tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpBtn.ZIndex = 3000
tpBtn.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = tpBtn
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60, 230, 255); s.Transparency = 0.5; s.Parent = tpBtn
end
tpBtn.MouseButton1Click:Connect(function()
    local ok = tpOnce()
    tpBtn.Text = ok and "TP ✓" or "没人"
    task.delay(0.7, function() tpBtn.Text = "TP" end)
end)

-- BHOP 快捷键（按住连跳）
local bhopBtn = Instance.new("TextButton")
bhopBtn.Size = UDim2.fromOffset(CFG.bhopSize, CFG.bhopSize)
bhopBtn.AnchorPoint = Vector2.new(1, 0.5)
bhopBtn.Position = UDim2.new(1, -CFG.bhopX, 0.5, CFG.bhopY)
bhopBtn.BackgroundColor3 = Color3.fromRGB(170, 90, 255)
bhopBtn.BackgroundTransparency = 0.72
bhopBtn.BorderSizePixel = 0
bhopBtn.Font = Enum.Font.GothamBold
bhopBtn.TextSize = 12
bhopBtn.Text = "BHOP"
bhopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
bhopBtn.ZIndex = 3000
bhopBtn.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = bhopBtn
    local s2 = Instance.new("UIStroke"); s2.Color = Color3.fromRGB(180, 110, 255); s2.Transparency = 0.5; s2.Parent = bhopBtn
end

local bhopHold = false
bhopBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        bhopHold = true
        bhopBtn.BackgroundTransparency = 0.42
    end
end)
bhopBtn.InputEnded:Connect(function()
    bhopHold = false
    bhopBtn.BackgroundTransparency = 0.72
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch then
        bhopHold = false
        bhopBtn.BackgroundTransparency = 0.72
    end
end)

-- 连跳本体：Humanoid.Jump 每帧请求，落地瞬间就会被下一帧顶起来
RunService.Heartbeat:Connect(function()
    if not (bhopHold or CFG.bhopAuto) then return end
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        hum.Jump = true
    end
end)

-- 布局应用（面板步进器改完立即生效）
function applyLayout()
    if aimBtn  then aimBtn.Size  = UDim2.fromOffset(CFG.aimSize, CFG.aimSize)
                    aimBtn.Position  = UDim2.new(1, -CFG.aimX, 0.5, CFG.aimY) end
    if tpBtn   then tpBtn.Size   = UDim2.fromOffset(CFG.tpSize, CFG.tpSize)
                    tpBtn.Position   = UDim2.new(1, -CFG.tpX, 0.5, CFG.tpY) end
    if bhopBtn then bhopBtn.Size = UDim2.fromOffset(CFG.bhopSize, CFG.bhopSize)
                    bhopBtn.Position = UDim2.new(1, -CFG.bhopX, 0.5, CFG.bhopY) end
end

applyLayout()
refreshRows()

--═══════════ 7. 开火模拟 ═══════════
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local isTouch = false
pcall(function()
    isTouch = (UIS.TouchEnabled and not UIS.KeyboardEnabled)
end)

local firing = false

-- 注意：mouse1press / VIM:SendMouseButtonEvent 在手机上会把客户端切进
-- 鼠标输入模式，屏幕上冒出一个指针，多指操作时它跟着乱飘并把视角带跑。
-- 所以手机上默认不碰它们（CFG.mouseSim = false），只在真鼠标/桌面端才用。
local function setFire(on)
    if on == firing then return end
    firing = on
    if not CFG.mouseSim then return end
    if isTouch then return end
    local cx, cy = 0, 0
    local cam = workspace.CurrentCamera
    if cam then
        local vp = cam.ViewportSize
        cx, cy = math.floor(vp.X * 0.5), math.floor(vp.Y * 0.5)
    end
    if on then
        if mouse1press then
            pcall(mouse1press)
        elseif VIM then
            pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 1) end)
        end
    else
        if mouse1release then
            pcall(mouse1release)
        elseif VIM then
            pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 1) end)
        end
    end
end

--═══════════ 8. 静默瞄准 ═══════════
local silentReady = false
local oldRaycast = nil

function installSilent()
    if oldRaycast then silentReady = true; return true end
    if not hookfunction then return false end

    local ray = workspace.Raycast
    local ok = pcall(function()
        oldRaycast = hookfunction(ray, function(self, origin, direction, params)
            if not CFG.silent or checkcaller() then
                return oldRaycast(self, origin, direction, params)
            end
            local cam = workspace.CurrentCamera
            if not cam then return oldRaycast(self, origin, direction, params) end
            local look = cam.CFrame.LookVector
            local dir  = direction
            if dir.Magnitude < 0.01 then return oldRaycast(self, origin, dir, params) end
            local unit = dir.Unit
            -- 只改写"从摄像机发出、几乎沿视线"的射线，避免干扰角色碰撞检测
            if unit:Dot(look) > 0.985 and (origin - cam.CFrame.Position).Magnitude < 8 then
                local best, bestD = nil, math.huge
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP then
                        local ch = p.Character
                        if ch then
                            local hum = ch:FindFirstChildOfClass("Humanoid")
                            local part = getAimPart(ch)
                            if hum and hum.Health > 0 and part
                            and not (CFG.teamCheck and sameTeam(p)) then
                                local sp = (part.Position - cam.CFrame.Position)
                                if sp.Magnitude > 0.5 and sp.Magnitude <= CFG.maxDist then
                                    local ang = unit:Dot(sp.Unit)
                                    local d = 1 - ang
                                    if ang > 0.90 and d < bestD then bestD = d; best = part end
                                end
                            end
                        end
                    end
                end
                if best then
                    return oldRaycast(self, origin, best.Position - origin, params)
                end
            end
            return oldRaycast(self, origin, dir, params)
        end)
    end)
    silentReady = ok
    return ok
end

if CFG.silent then installSilent() end

--═══════════ 8.5 Rivals 原生 remote（Kicia 源码里扒的路径） ═══════════
local RIVALS = { ready = false }
pcall(function()
    local RS = game:GetService("ReplicatedStorage")
    local rem = RS:WaitForChild("Remotes", 8)
    if not rem then return end
    local rep     = rem:WaitForChild("Replication", 5)
    local fighter = rep  and rep:WaitForChild("Fighter", 5)
    local duels   = rem:WaitForChild("Duels", 5)
    if fighter then
        RIVALS.cam  = fighter:FindFirstChild("UpdateCameraRotation")
        RIVALS.use  = fighter:FindFirstChild("UseItem")
    end
    if duels then
        RIVALS.respawn = duels:FindFirstChild("RespawnNow")
    end
    local mods = RS:FindFirstChild("Modules")
    local util = mods and mods:FindFirstChild("Utility")
    if util then
        pcall(function() RIVALS.util = require(util) end)
    end
    RIVALS.ready = (RIVALS.cam ~= nil and RIVALS.util ~= nil)
end)

local lastYawSend = 0

local function sendSilentYaw(worldPos)
    if not RIVALS.ready or not worldPos then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local origin = cam.CFrame.Position
    if CFG.thirdPerson and LP.Character then
        local hb = LP.Character:FindFirstChild("HitboxHead") or LP.Character:FindFirstChild("Head")
        if hb then origin = hb.Position end
    end
    local delta = worldPos - origin
    if delta.Magnitude < 0.8 then return false end     -- 贴脸时 lookAt 会炸
    local now = os.clock()
    if now - lastYawSend < 0.02 then return false end   -- 50Hz 上限
    lastYawSend = now
    return (pcall(function()
        local dirCF = CFrame.lookAt(origin, worldPos)
        local _, yaw = dirCF:ToOrientation()
        local enc = RIVALS.util:EncodeCameraRotation(Vector2.new(0, yaw))
        RIVALS.cam:FireServer(enc, nil)
    end))
end

--═══════════ 9. 移动 ═══════════
task.spawn(function()
    while task.wait(0.2) do
        local ch = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            if CFG.speed then
                if hum.WalkSpeed ~= CFG.speedVal then hum.WalkSpeed = CFG.speedVal end
            elseif hum.WalkSpeed == CFG.speedVal then
                hum.WalkSpeed = 16
            end
            if CFG.jump then
                pcall(function()
                    hum.UseJumpPower = true
                    hum.JumpPower = CFG.jumpVal
                end)
            end
        end
    end
end)

--═══════════ 10. ESP 主循环 ═══════════
local fpsCount, fpsT = 0, os.clock()
local nEnemy, nPlayer = 0, 0

local function drawBox(b, cx, cy, w, h)
    local x0, y0 = cx - w * 0.5, cy - h * 0.5
    local t, bo, l, r = b[1], b[2], b[3], b[4]
    t.Visible  = true; t.Position  = UDim2.fromOffset(x0, y0);       t.Size = UDim2.fromOffset(w, 2)
    bo.Visible = true; bo.Position = UDim2.fromOffset(x0, y0 + h);   bo.Size = UDim2.fromOffset(w, 2)
    l.Visible  = true; l.Position  = UDim2.fromOffset(x0, y0);       l.Size = UDim2.fromOffset(2, h)
    r.Visible  = true; r.Position  = UDim2.fromOffset(x0 + w, y0);   r.Size = UDim2.fromOffset(2, h)
end

local function setColor(b, c)
    for i = 1, 4 do b[i].BackgroundColor3 = c end
end

RunService.RenderStepped:Connect(function()
    fpsCount = fpsCount + 1

    local cam = workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    local ne, np = 0, 0

    for _, p in ipairs(Players:GetPlayers()) do
        np = np + 1
        local drawn = false
        local ch = p.Character
        local d = esp[p]

        if ch and CFG.esp then
            local hrp  = ch:FindFirstChild("HumanoidRootPart")
            local head = ch:FindFirstChild("Head")
            local hum  = ch:FindFirstChildOfClass("Humanoid")
            if hrp and head and hum and hum.Health > 0 then
                local self_ = (p == LP)
                local show, col, tag = false, Color3.fromRGB(255, 60, 60), p.Name
                if self_ then
                    show = CFG.selfBox
                    col  = Color3.fromRGB(70, 230, 110)
                    tag  = "YOU"
                elseif not (CFG.teamCheck and sameTeam(p)) then
                    local dist = (hrp.Position - camPos).Magnitude
                    if dist <= CFG.maxDist then
                        show = true
                        ne = ne + 1
                        tag = string.format("%s  %dm", p.Name, math.floor(dist))
                    end
                    if sameTeam(p) then col = Color3.fromRGB(60, 160, 255) end
                end

                if show then
                    local topP = ch:FindFirstChild("HitboxHead") or head
                    local botP = ch:FindFirstChild("HitboxBody") or hrp
                    local topY = (typeof(topP.Size) == "Vector3") and topP.Size.Y or 1
                    local botY = (typeof(botP.Size) == "Vector3") and botP.Size.Y or 6
                    local a, aOn  = cam:WorldToViewportPoint(topP.Position + Vector3.new(0, topY * 0.5, 0))
                    local b2, bOn = cam:WorldToViewportPoint(botP.Position - Vector3.new(0, botY * 0.5, 0))
                    if (aOn or bOn) and a.Z > 0 then
                        local h = math.abs(b2.Y - a.Y)
                        if h >= 8 and h <= 1200 then
                            local cx, cy = a.X, (a.Y + b2.Y) * 0.5
                            local w = h * 0.58
                            d = ensure(p, col)
                            setColor(d.box, col)
                            drawBox(d.box, cx, cy, w, h)

                            d.name.Visible = true
                            d.name.Text = tag
                            d.name.TextColor3 = col
                            d.name.Size = UDim2.fromOffset(w + 120, 14)
                            d.name.Position = UDim2.fromOffset(cx - (w + 120) * 0.5, cy - h * 0.5 - 16)

                            d.hpBg.Visible = true
                            d.hpBg.Size = UDim2.fromOffset(3, h)
                            d.hpBg.Position = UDim2.fromOffset(cx - w * 0.5 - 7, cy - h * 0.5)

                            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            d.hpFill.Size = UDim2.fromScale(1, ratio)
                            d.hpFill.Position = UDim2.fromScale(0, 1 - ratio)
                            d.hpFill.BackgroundColor3 = Color3.fromRGB(
                                math.floor(255 * (1 - ratio)) + 40,
                                math.floor(210 * ratio) + 40, 70)

                            d.dist.Visible = not self_
                            d.dist.Text = string.format("%dm", math.floor((hrp.Position - camPos).Magnitude))
                            d.dist.Size = UDim2.fromOffset(w + 40, 12)
                            d.dist.Position = UDim2.fromOffset(cx - (w + 40) * 0.5, cy + h * 0.5 + 3)
                            drawn = true
                        end
                    end
                end
            end
        end

        if not drawn and d then
            hideBox(d.box)
            d.name.Visible = false
            d.hpBg.Visible = false
            d.dist.Visible = false
        end
    end

    nEnemy, nPlayer = ne, np

    local now = os.clock()
    if now - fpsT >= 0.5 then
        local fps = math.floor(fpsCount / (now - fpsT))
        fpsCount, fpsT = 0, now
        stat.Text = string.format("  敌人 %d / 玩家 %d   FPS %d\n  %s",
            nEnemy, nPlayer, fps,
            (CFG.silentRemote and (RIVALS.ready and "原生 已接" or "原生 未接")) 
            .. " / " .. (CFG.silent and (silentReady and "hook 已挂" or "hook 失败") or "hook 关"))
    end
end)

--═══════════ 11. 瞄准（Camera 优先级之后） ═══════════
local aimScore = math.huge

RunService:BindToRenderStep("RivalsAimV4", Enum.RenderPriority.Camera.Value + 1, function()
    aimScore = math.huge
    local cam = workspace.CurrentCamera
    if not cam then return end
    if not CFG.aim and not CFG.trigger and not CFG.silentRemote then setFire(false); return end

    local center = cam.ViewportSize * 0.5
    local camPos = cam.CFrame.Position
    local best, bestScore = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local ch = p.Character
            if ch then
                local hum = ch:FindFirstChildOfClass("Humanoid")
                local part = getAimPart(ch)
                if hum and hum.Health > 0 and part
                and not (CFG.teamCheck and sameTeam(p)) then
                    if (part.Position - camPos).Magnitude <= CFG.maxDist then
                        local s, on = cam:WorldToViewportPoint(part.Position)
                        if on and s.Z > 0 then
                            local d = (Vector2.new(s.X, s.Y) - center).Magnitude
                            if d <= CFG.fov and d < bestScore then
                                if (not CFG.visibleOnly) or canSee(part) then
                                    bestScore = d
                                    best = part
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    aimScore = bestScore

    -- 真·静默：只把方向发给服务端，本地相机不动
    if CFG.silentRemote and best then
        sendSilentYaw(best.Position)
    end

    if best and CFG.aim and (holding or CFG.trigger) then
        local goal = CFrame.lookAt(cam.CFrame.Position, best.Position)
        cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(CFG.smooth, 0.02, 1))
    end

    if CFG.tp and CFG.tpFire then
        -- 开火权交给贴人模块
    elseif CFG.trigger and best and bestScore <= 34 then
        setFire(true)
    else
        setFire(false)
    end
end)

--═══════════ 11.5 传送 / 贴人 autofarm ═══════════
function myChar()
    local ch = LP.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local root = ch:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return nil end
    return ch, root, hum
end

function goalFrom(hrp)
    local r = CFG.tpRange
    if CFG.tpOffset == "above" then
        return hrp.CFrame * CFrame.new(0, r + 1, 0)
    elseif CFG.tpOffset == "front" then
        return hrp.CFrame * CFrame.new(0, 0, -r)
    end
    return hrp.CFrame * CFrame.new(0, 0, r) * CFrame.Angles(0, math.rad(180), 0)
end

function applyTP(cf)
    local ch, root = myChar()
    if not ch or not root or not cf then return false end
    local ok = pcall(function() ch:PivotTo(cf) end)
    if not ok then pcall(function() root.CFrame = cf end) end
    return true
end

function pickTP()
    local _, root = myChar()
    if not root then return nil end
    local pool, best, bestScore = {}, nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 and not (CFG.teamCheck and sameTeam(p)) then
                if CFG.tpMode == "random" then
                    table.insert(pool, hrp)
                elseif CFG.tpMode == "weak" then
                    if hum.Health < bestScore then bestScore = hum.Health; best = hrp end
                else
                    local d = (hrp.Position - root.Position).Magnitude
                    if d < bestScore then bestScore = d; best = hrp end
                end
            end
        end
    end
    if CFG.tpMode == "random" then
        if #pool == 0 then return nil end
        return pool[math.random(1, #pool)]
    end
    return best
end

function tpOnce()
    local t = pickTP()
    if not t then return false end
    return applyTP(goalFrom(t))
end

task.spawn(function()
    while true do
        if CFG.tp then
            local _, root = myChar()
            local t = root and pickTP() or nil
            if t then
                applyTP(goalFrom(t))
            end
            if CFG.tpFire then setFire(t ~= nil) end
        elseif firing then
            setFire(false)
        end
        task.wait(math.clamp(CFG.tpRate, 0.08, 1))
    end
end)

--═══════════ 11.7 自动重生 ═══════════
local respawnBusy = false

local function tryRespawn()
    if not CFG.autoRespawn or respawnBusy then return end
    respawnBusy = true
    task.spawn(function()
        if RIVALS.respawn then
            for _ = 1, 6 do
                pcall(function() RIVALS.respawn:FireServer() end)
                task.wait(0.12)
            end
        end
        task.wait(0.6)
        respawnBusy = false
    end)
end

local function watchChar(ch)
    local hum = ch:WaitForChild("Humanoid", 10)
    if hum then
        hum.Died:Connect(tryRespawn)
    end
end

if LP.Character then pcall(watchChar, LP.Character) end
LP.CharacterAdded:Connect(function(ch) pcall(watchChar, ch) end)

--═══════════ 11.8 视觉：第三人称 / FOV / 命中音 ═══════════
local SoundService = game:GetService("SoundService")

local hitSnd = Instance.new("Sound")
hitSnd.SoundId = "rbxassetid://7149516994"
hitSnd.Volume = 0.45
hitSnd.Parent = SoundService

task.spawn(function()
    local track = {}
    while task.wait(0.12) do
        if CFG.hitSound then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local prev = track[p]
                        local cur = hum.Health
                        if prev and cur < prev - 0.4 then
                            pcall(function()
                                hitSnd.TimePosition = 0
                                hitSnd:Play()
                            end)
                        end
                        track[p] = cur
                    end
                end
            end
        end
    end
end)

-- 相机视野
local origFov = nil
RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    if CFG.camFov then
        if not origFov then origFov = cam.FieldOfView end
        if math.abs(cam.FieldOfView - CFG.fovVal) > 0.6 then
            cam.FieldOfView = CFG.fovVal
        end
    elseif origFov then
        cam.FieldOfView = origFov
        origFov = nil
    end
end)

-- 第三人称（排在游戏相机之后覆盖）
RunService:BindToRenderStep("RivalsThirdPerson", Enum.RenderPriority.Camera.Value + 2, function()
    if not CFG.thirdPerson then return end
    local cam = workspace.CurrentCamera
    if cam then
        cam.CFrame = cam.CFrame * CFrame.new(0, CFG.tpCamY, CFG.tpCamZ)
    end
end)

-- 陀螺仪：用手机姿态做视角增量，叠在游戏自己的触摸控制上
_G.GYRO_OK = false
pcall(function() _G.GYRO_OK = (UIS.GyroscopeEnabled == true) end)

local gLastYaw, gLastPitch = nil, nil

task.delay(4, function()
    if CFG.gyro and not _G.GYRO_OK and stat then
        stat.Text = "  陀螺仪开着，但设备没上报 GYROSCOPE —— 执行器或系统禁了传感器"
    end
end)

RunService:BindToRenderStep("RivalsGyro", Enum.RenderPriority.Camera.Value + 3, function()
    if not (CFG.gyro and _G.GYRO_OK) then
        gLastYaw, gLastPitch = nil, nil
        return
    end
    local rot
    local ok = pcall(function() rot = UIS:GetDeviceRotation() end)
    if not ok or not rot then return end
    local ok2, yaw, pitch = pcall(function() return rot:ToEulerAnglesYXZ() end)
    if not ok2 or not yaw then return end
    if gLastYaw == nil then
        gLastYaw, gLastPitch = yaw, pitch
        return
    end
    local dy = yaw - gLastYaw
    local dp = pitch - gLastPitch
    gLastYaw, gLastPitch = yaw, pitch
    -- 跨 ±180° 的跳变丢掉
    if dy > math.pi then dy = dy - math.pi * 2
    elseif dy < -math.pi then dy = dy + math.pi * 2 end
    if math.abs(dy) > 0.4 or math.abs(dp) > 0.4 then return end
    if CFG.gyroInvY then dy = -dy end
    if CFG.gyroInvX then dp = -dp end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local s = CFG.gyroSens
    cam.CFrame = cam.CFrame
        * CFrame.Angles(0, -dy * s, 0)
        * CFrame.Angles(-dp * s, 0, 0)
end)

--═══════════ 11.9 Kicia 全套（vendor） ═══════════
local function pullVendor(name)
    for _, b in ipairs(RAW_MIRRORS) do
        local ok, res = pcall(function() return game:HttpGet(b .. name, true) end)
        if not ok then
            ok, res = pcall(function() return game:HttpGet(b .. name) end)
        end
        if ok and type(res) == "string" and #res > 1000 then
            return res
        end
    end
    return nil
end

function loadKicia()
    if getgenv().RivalsHubKiciaLoaded and getgenv().KiciaRebuild then
        return "已经载入了"
    end
    local src = pullVendor("vendor/kicia.lua")
    if not src then return "拉取失败（网络/镜像）" end
    local fn = loadstring(src)
    if not fn then return "编译失败（执行器不支持）" end
    local ok, err = pcall(fn)
    if not ok then return "运行出错: " .. tostring(err) end
    getgenv().RivalsHubKiciaLoaded = true
    -- 它和本脚本会抢相机/远程，先把自己这边的关掉
    CFG.aim = false
    CFG.silentRemote = false
    CFG.silent = false
    CFG.trigger = false
    CFG.tp = false
    saveCfg()
    refreshRows()
    return "已载入 · 用它的菜单调 ragebot"
end

function unloadKicia()
    local K = getgenv().KiciaRebuild
    if K and K.Unload then
        pcall(K.Unload)
        getgenv().RivalsHubKiciaLoaded = false
        return "已卸载"
    end
    return "它没在跑"
end

--═══════════ 11.95 Skinchanger ═══════════
local RS = game:GetService("ReplicatedStorage")

local function findModule(name)
    local roots = {}
    local ps  = LP:FindFirstChild("PlayerScripts")
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

local skinPanel, skinList, skinSearch, skinStatus
local fillSkinList
local skinCache = {}
local originalSkin = nil

local function getSkinList()
    local out = {}
    pcall(function()
        local mod = findModule("CosmeticLibrary")
        if not mod then return end
        local lib = require(mod)
        local cos = lib and (lib.Cosmetics or lib.cosmetics) or lib
        if type(cos) ~= "table" then return end
        for name, data in pairs(cos) do
            if type(name) == "string" and type(data) == "table" then
                local img = data.Image or data.ImageHighResolution
                if img then table.insert(out, { name = name, image = img }) end
            end
        end
    end)
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- 本地换皮：重建手持 viewmodel（照 Kicia 的做法，只改自己画面）
local function applySkin(skinName)
    if not skinName then return "没有皮肤名" end
    local identity
    pcall(function() if getthreadidentity then identity = getthreadidentity() end end)
    local ok, res = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 2) end
        local FC  = findModule("FighterController")
        local RC  = findModule("ReplicatedClass")
        local CVM = findModule("ClientViewModel")
        if not (FC and RC and CVM) then return "缺少游戏模块" end
        FC, RC, CVM = require(FC), require(RC), require(CVM)
        local fighter = FC:GetFighter(LP)
        if not fighter or not fighter.Items then return "拿不到 fighter" end
        local item = fighter.EquippedItem
        if not item then
            for _, it in pairs(fighter.Items) do item = it break end
        end
        if not item then return "没有手持武器" end
        local old = item.ViewModel
        if not (type(old) == "table" and old._serial) then return "viewmodel 结构变了" end
        local serial = table.clone(old._serial)
        local dataKey = RC:ToEnum("Data")
        local data = table.clone(serial.Data or serial[dataKey] or {})
        serial[dataKey] = data
        serial.Data = nil
        data[RC:ToEnum("Skin")] = { Name = skinName }
        data[RC:ToEnum("Name")] = skinName
        data.Skin = nil
        data.Name = nil
        local built, nvm = pcall(function() return CVM.new(serial, item) end)
        if not built or type(nvm) ~= "table" then return "构建 viewmodel 失败" end
        if old.Unequip then pcall(old.Unequip, old) end
        item.ViewModel = nvm
        if nvm.Equip then pcall(nvm.Equip, nvm, true) end
        if old.Destroy then pcall(old.Destroy, old) end
        return true
    end)
    if setthreadidentity and identity then pcall(setthreadidentity, identity) end
    if ok and res == true then return "✅ 已换成 " .. skinName end
    return "❌ " .. tostring(res)
end

local function buildSkinPanel()
    if skinPanel then return end

    skinPanel = Instance.new("Frame")
    skinPanel.Size = UDim2.fromOffset(268, 392)
    skinPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    skinPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
    skinPanel.BackgroundColor3 = Color3.fromRGB(12, 13, 19)
    skinPanel.BackgroundTransparency = 0.06
    skinPanel.BorderSizePixel = 0
    skinPanel.Visible = false
    skinPanel.ZIndex = 4000
    skinPanel.Parent = gui
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = skinPanel
        local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(180, 110, 255); st.Transparency = 0.5; st.Parent = skinPanel
    end

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 30)
    head.BackgroundColor3 = Color3.fromRGB(26, 22, 38)
    head.BorderSizePixel = 0
    head.Font = Enum.Font.GothamBold
    head.TextSize = 13
    head.Text = "  SKINCHANGER   ×"
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.TextColor3 = Color3.fromRGB(190, 140, 255)
    head.AutoButtonColor = false
    head.ZIndex = 4001
    head.Parent = skinPanel
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = head
    end
    head.MouseButton1Click:Connect(function() skinPanel.Visible = false end)

    skinSearch = Instance.new("TextBox")
    skinSearch.Size = UDim2.new(1, -12, 0, 28)
    skinSearch.Position = UDim2.fromOffset(6, 34)
    skinSearch.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
    skinSearch.BorderSizePixel = 0
    skinSearch.PlaceholderText = "搜索皮肤…"
    skinSearch.Text = ""
    skinSearch.TextSize = 13
    skinSearch.TextColor3 = Color3.fromRGB(235, 235, 240)
    skinSearch.ClearTextOnFocus = false
    skinSearch.ZIndex = 4001
    skinSearch.Parent = skinPanel
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = skinSearch
    end

    skinList = Instance.new("ScrollingFrame")
    skinList.Size = UDim2.new(1, -12, 1, -112)
    skinList.Position = UDim2.fromOffset(6, 66)
    skinList.BackgroundTransparency = 1
    skinList.BorderSizePixel = 0
    skinList.ScrollBarThickness = 3
    skinList.ScrollBarImageColor3 = Color3.fromRGB(190, 140, 255)
    skinList.CanvasSize = UDim2.fromOffset(0, 0)
    skinList.ZIndex = 4001
    skinList.Parent = skinPanel
    pcall(function()
        skinList.ScrollingDirection = Enum.ScrollingDirection.Y
        skinList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    end)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = skinList

    skinStatus = Instance.new("TextLabel")
    skinStatus.Size = UDim2.new(1, -12, 0, 40)
    skinStatus.AnchorPoint = Vector2.new(0, 1)
    skinStatus.Position = UDim2.new(0, 6, 1, -6)
    skinStatus.BackgroundTransparency = 1
    skinStatus.Font = Enum.Font.Code
    skinStatus.TextSize = 11
    skinStatus.TextXAlignment = Enum.TextXAlignment.Left
    skinStatus.TextYAlignment = Enum.TextYAlignment.Top
    skinStatus.TextColor3 = Color3.fromRGB(170, 175, 190)
    skinStatus.Text = "  点一项试试"
    skinStatus.ZIndex = 4001
    skinStatus.Parent = skinPanel

    skinSearch:GetPropertyChangedSignal("Text"):Connect(function()
        if fillSkinList and #skinCache > 0 then fillSkinList(skinSearch.Text) end
    end)
end

function fillSkinList(filter)
    if not skinList then return end
    for _, ch in ipairs(skinList:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    filter = string.lower(filter or "")
    local n = 0
    for i, sk in ipairs(skinCache) do
        if filter == "" or string.find(string.lower(sk.name), filter, 1, true) then
            n = n + 1
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -6, 0, 30)
            b.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
            b.BorderSizePixel = 0
            b.Font = Enum.Font.Gotham
            b.TextSize = 13
            b.Text = "  " .. sk.name
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextColor3 = Color3.fromRGB(230, 230, 240)
            b.LayoutOrder = i
            b.ZIndex = 4002
            b.Parent = skinList
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
            b.MouseButton1Click:Connect(function()
                local _, root = myChar()
                if originalSkin == nil then originalSkin = sk.name end
                skinStatus.Text = "  " .. applySkin(sk.name)
            end)
        end
    end
    skinStatus.Text = string.format("  共 %d 个皮肤（显示 %d）", #skinCache, n)
end

function openSkincare()
    buildSkinPanel()
    skinPanel.Visible = not skinPanel.Visible
    if not skinPanel.Visible then return end
    if #skinCache == 0 then
        skinStatus.Text = "  正在读皮肤列表…"
        task.spawn(function()
            skinCache = getSkinList()
            if #skinCache == 0 then
                skinStatus.Text = "  没读到皮肤（要先进一局，或者游戏改了模块名）"
            else
                fillSkinList(skinSearch and skinSearch.Text or "")
            end
        end)
    else
        fillSkinList(skinSearch and skinSearch.Text or "")
    end
end

--═══════════ 12. 收尾 ═══════════
Players.PlayerRemoving:Connect(drop)
LP.CharacterAdded:Connect(function()
    holding = false
    setFire(false)
    for p in pairs(esp) do drop(p) end
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.wait(0.2)
    layoutRing()
end)

pcall(function()
    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutRing)
    end
end)

print("[Rivals Hub v8.2] 已加载 · 左上角 R 打开面板 · 右侧 TP 一点就贴")
