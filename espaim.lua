--[[
════════════════════════════════════════════════════════════
  ESP + AIM · 全自动，没有按钮
    加载完就一直在跑：透视 + 平滑锁头。
    性能方面：ESP 走 Drawing（GPU 画，不占实例树），
    每 3 帧才刷一次；角色部件全部缓存，不每帧 FindFirstChild。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/espaim.lua"))()
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

--═══════════ 参数 ═══════════
local CFG = {
    espOn      = true,
    espMaxDist = 900,
    espRefresh = 3,        -- 每几帧刷一次 ESP（3 ≈ 20fps，够用且省）
    aimOn      = true,
    aimFOV     = 150,      -- 屏幕像素半径
    aimSmooth  = 0.18,     -- 每帧插值比例，越小越慢越自然
    aimMaxDist = 500,
    aimPart    = "Head",
    teamCheck  = true,
}

--═══════════ 队友判断 ═══════════
local function isAlly(p)
    if p == LP then return true end
    if not CFG.teamCheck then return false end
    if p.Team ~= nil and LP.Team ~= nil and p.Team == LP.Team then return true end
    local a, b = p:GetAttribute("TeamID"), LP:GetAttribute("TeamID")
    if a ~= nil and b ~= nil then return a == b end
    return false
end

--═══════════ 角色部件缓存（关键性能点） ═══════════
local cache = {}   -- [player] = {char=, head=, hrp=, hum=, t=}

local function refreshCache(p)
    local ch = p.Character
    if not ch then cache[p] = nil return end
    cache[p] = {
        char = ch,
        head = ch:FindFirstChild("Head"),
        hrp  = ch:FindFirstChild("HumanoidRootPart"),
        hum  = ch:FindFirstChildOfClass("Humanoid"),
        t    = os.clock(),
    }
end

local function watchPlayer(p)
    if p == LP then return end
    refreshCache(p)
    p.CharacterAdded:Connect(function() task.wait(0.3) refreshCache(p) end)
end

for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(p) cache[p] = nil end)

-- 每 1 秒兜底刷一次（防止角色重置、部件换掉）
task.spawn(function()
    while task.wait(1) do
        for _, p in ipairs(Players:GetPlayers()) do
            local c = cache[p]
            if not c or c.char ~= p.Character or (c.hrp and not c.hrp.Parent) then
                refreshCache(p)
            end
        end
    end
end)

--═══════════ ESP（Drawing 优先） ═══════════
local useDrawing = false
pcall(function()
    local t = Drawing.new("Square")
    t:Remove()
    useDrawing = true
end)

local pool = {}   -- [player] = {box=, name=, dist=}  或 Frame 三件套

local function newEsp()
    if useDrawing then
        local box = Drawing.new("Square")
        box.Thickness = 1
        box.Filled = false
        box.Transparency = 1
        box.Visible = false
        local name = Drawing.new("Text")
        name.Size = 13
        name.Center = true
        name.Outline = true
        name.Visible = false
        local dist = Drawing.new("Text")
        dist.Size = 11
        dist.Center = true
        dist.Outline = true
        dist.Visible = false
        return { box = box, name = name, dist = dist, drawing = true }
    end
    -- 回退：三个 Frame（慢，但至少能显示）
    local box = Instance.new("Frame")
    box.BorderSizePixel = 0
    box.BackgroundColor3 = Color3.fromRGB(90, 255, 140)
    box.Visible = false
    box.ZIndex = 900
    box.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Font = Enum.Font.GothamBold
    name.TextSize = 12
    name.TextColor3 = Color3.fromRGB(120, 255, 160)
    name.TextStrokeTransparency = 0.3
    name.Visible = false
    name.ZIndex = 901
    name.Parent = box.Parent
    local dist = Instance.new("TextLabel")
    dist.BackgroundTransparency = 1
    dist.Font = Enum.Font.Gotham
    dist.TextSize = 11
    dist.TextColor3 = Color3.fromRGB(230, 230, 230)
    dist.TextStrokeTransparency = 0.3
    dist.Visible = false
    dist.ZIndex = 901
    dist.Parent = box.Parent
    return { box = box, name = name, dist = dist }
end

local function hide(e)
    if e.drawing then
        e.box.Visible = false
        e.name.Visible = false
        e.dist.Visible = false
    else
        e.box.Visible = false
        e.name.Visible = false
        e.dist.Visible = false
    end
end

--═══════════ 主循环 ═══════════
local frame = 0

RunService.RenderStepped:Connect(function()
    frame = frame + 1
    if frame % CFG.espRefresh ~= 0 then return end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position

    if not CFG.espOn then
        for _, e in pairs(pool) do hide(e) end
        return
    end

    for p, c in pairs(cache) do
        local head, hrp, hum = c.head, c.hrp, c.hum
        local e = pool[p]
        local drawn = false

        if head and hrp and hum and hum.Health > 0 and not isAlly(p)
        and head.Parent and hrp.Parent then
            local d = (hrp.Position - camPos).Magnitude
            if d <= CFG.espMaxDist then
                local a, onA = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local b, onB = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                if onA and onB then
                    local h = math.abs(b.Y - a.Y)
                    if h > 8 and h < 900 then
                        if not e then e = newEsp() pool[p] = e end
                        local w  = h * 0.55
                        local x0 = a.X - w / 2
                        local y0 = a.Y
                        if e.drawing then
                            e.box.Visible  = true
                            e.box.Size     = Vector2.new(w, h)
                            e.box.Position = Vector2.new(x0, y0)
                            e.name.Visible  = true
                            e.name.Text     = p.Name
                            e.name.Position = Vector2.new(a.X, y0 - 15)
                            e.dist.Visible  = true
                            e.dist.Text     = string.format("%dm", math.floor(d))
                            e.dist.Position = Vector2.new(a.X, y0 + h + 2)
                        else
                            e.box.Visible  = true
                            e.box.Position = UDim2.fromOffset(x0, y0)
                            e.box.Size     = UDim2.fromOffset(w, 2)
                            e.name.Visible = true
                            e.name.Text = p.Name
                            e.name.Size = UDim2.fromOffset(w + 80, 14)
                            e.name.Position = UDim2.fromOffset(x0 - 40, y0 - 15)
                            e.dist.Visible = true
                            e.dist.Text = string.format("%dm", math.floor(d))
                            e.dist.Size = UDim2.fromOffset(w + 40, 12)
                            e.dist.Position = UDim2.fromOffset(x0 - 20, y0 + h + 2)
                        end
                        drawn = true
                    end
                end
            end
        end

        if not drawn and e then hide(e) end
    end
end)

--═══════════ AIM（平滑锁头） ═══════════
if not CFG.aimOn then return end

RunService:BindToRenderStep("espaim_lock", Enum.RenderPriority.Camera.Value + 1, function(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local camPos = cam.CFrame.Position

    local best, bestScore = nil, math.huge
    for p, c in pairs(cache) do
        local head, hum = c.head, c.hum
        if head and hum and hum.Health > 0 and head.Parent and not isAlly(p) then
            local dd = (head.Position - myRoot.Position).Magnitude
            if dd <= CFG.aimMaxDist then
                local sp, on = cam:WorldToViewportPoint(head.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d <= CFG.aimFOV and d < bestScore then
                        bestScore = d
                        best = head
                    end
                end
            end
        end
    end

    if best then
        local goal = CFrame.lookAt(cam.CFrame.Position, best.Position)
        -- 按帧率归一化，120fps 和 30fps 手感一致
        local alpha = 1 - (1 - CFG.aimSmooth) ^ (dt * 60)
        cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(alpha, 0.01, 1))
    end
end)

print("[ESPAIM] 已加载 · 透视 + 平滑自瞄常驻（无按钮）")
