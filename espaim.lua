--[[
════════════════════════════════════════════════════════════
  ESP + AIM · 全自动（0d233ac 起重写）
    · 骨骼透视 + 血量条 + 名字（Drawing，GPU 画）
    · 能看见 → 红色，被墙挡着 → 绿色
    · 自瞄只在「你开火的那一刻」生效，平时不动视角
    · 隔着墙不锁
    · 没有按钮，加载就一直跑

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/espaim.lua?t=" .. os.time()))()
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
    espOn       = true,
    espMaxDist  = 900,
    espRefresh  = 1,      -- 1 = 每帧刷，位置跟角色完全同步
    visRefresh  = 3,      -- 可见性(射线)每几帧算一次，结果缓存
    showBones   = true,
    showHealth  = true,
    showName    = true,
    colVisible  = Color3.fromRGB(255, 60, 60),   -- 能看见 = 红
    colHidden   = Color3.fromRGB(60, 255, 120),  -- 被挡住 = 绿
    aimOn       = true,
    aimFOV      = 170,
    aimSmoothYaw   = 0.24,  -- 左右追赶比例（越小越顺）
    aimSmoothPitch = 0.52,  -- 上下追赶比例（比左右狠一点，但不硬锁）
    aimSnapAngle   = 0.012, -- 差多少弧度才硬对齐（越小越不会"顿一下"）
    aimMaxDist  = 500,
    aimHoldSec  = 0.55,   -- 开火后锁多久
    teamCheck   = true,
    visibleOnly = true,   -- 隔墙不锁
}

--═══════════ 队友识别 ═══════════
-- 三层：
--   ① DuelController 里的 Dueler TeamID（对局中最准，开源 ragebot 就用这个）
--   ② Player.Team 对象 / TeamID 属性（空串不算）
--   ③ 手动名单（getgenv().ESPAIM_Ally(userId, true)）
local allyIds = {}
local duelTeam = {}     -- [player] = teamId

local function findModuleEarly(name)
    local ps = LP:FindFirstChild("PlayerScripts")
    for _, root in ipairs({ ps, RS }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ModuleScript") and d.Name == name then return d end
            end
        end
    end
    return nil
end

task.spawn(function()
    while task.wait(1) do
        local newMap = {}
        pcall(function()
            local mod = findModuleEarly("SpectateController")
            if not mod then return end
            local SC = require(mod)
            local duel = SC and SC.CurrentDuelSubject
            if not duel then return end
            local duelers = duel.Duelers
            if not duelers then return end
            for _, dueler in ipairs(duelers) do
                local plr = dueler.Player
                if plr then
                    local tid
                    pcall(function() tid = dueler:Get("TeamID") end)
                    if tid ~= nil and tid ~= "" then newMap[plr] = tid end
                end
            end
        end)
        if next(newMap) then duelTeam = newMap end
    end
end)

local function isAlly(p)
    if p == LP then return true end
    if allyIds[p.UserId] then return true end
    if not CFG.teamCheck then return false end

    -- ① 对局里的队伍表
    local mine = duelTeam[LP]
    if mine ~= nil and duelTeam[p] ~= nil then
        return mine == duelTeam[p]
    end

    -- ② Team 对象 / TeamID 属性（空串忽略，否则一屋子人都被当成队友）
    if p.Team ~= nil and LP.Team ~= nil and p.Team == LP.Team then return true end
    local a, b = p:GetAttribute("TeamID"), LP:GetAttribute("TeamID")
    if type(a) == "string" and type(b) == "string" and a ~= "" and b ~= "" then
        return a == b
    end
    local pa, pb = p:GetAttribute("PartyId"), LP:GetAttribute("PartyId")
    if type(pa) == "string" and type(pb) == "string" and pa ~= "" and pa == pb then
        return true
    end
    return false
end

getgenv().ESPAIM_Ally = function(userId, on)
    if on == false then allyIds[userId] = nil else allyIds[tonumber(userId) or userId] = true end
end

--═══════════ 可见性 ═══════════
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

local function refreshCache(p)
    local ch = p.Character
    if not ch then cache[p] = nil return end
    local bones = {}
    if ch:FindFirstChild("UpperTorso") then
        for _, pair in ipairs({
            {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
            {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
            {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
            {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
            {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
        }) do
            local a, b = ch:FindFirstChild(pair[1]), ch:FindFirstChild(pair[2])
            if a and b then bones[#bones + 1] = { a, b } end
        end
    elseif ch:FindFirstChild("Torso") then
        for _, pair in ipairs({
            {"Head","Torso"},{"Torso","Right Arm"},{"Torso","Left Arm"},
            {"Torso","Right Leg"},{"Torso","Left Leg"},
        }) do
            local a, b = ch:FindFirstChild(pair[1]), ch:FindFirstChild(pair[2])
            if a and b then bones[#bones + 1] = { a, b } end
        end
    end

    cache[p] = {
        char = ch,
        head = ch:FindFirstChild("Head"),
        hrp  = ch:FindFirstChild("HumanoidRootPart"),
        hum  = ch:FindFirstChildOfClass("Humanoid"),
        bones = bones,
        visible = false,
        visAt = 0,
    }
end

local function watch(p)
    if p == LP then return end
    refreshCache(p)
    p.CharacterAdded:Connect(function() task.wait(0.3) refreshCache(p) end)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p) cache[p] = nil end)

task.spawn(function()
    while task.wait(1) do
        for _, p in ipairs(Players:GetPlayers()) do
            local c = cache[p]
            if not c or c.char ~= p.Character or (c.hrp and not c.hrp.Parent) then refreshCache(p) end
        end
    end
end)

--═══════════ Drawing ═══════════
local useDrawing = false
pcall(function()
    local t = Drawing.new("Line")
    t:Remove()
    useDrawing = true
end)
if not useDrawing then
    print("[ESPAIM] 执行器不支持 Drawing，骨骼透视会关掉，只保留自瞄")
    CFG.showBones = false
end

local SKEL_R15 = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
}
local SKEL_R6 = {
    {"Head","Torso"},{"Torso","Right Arm"},{"Torso","Left Arm"},
    {"Torso","Right Leg"},{"Torso","Left Leg"},
}
local MAXBONES = 14

local pool = {}

local function newPool()
    local e = { lines = {}, drawing = true }
    for i = 1, MAXBONES do
        local l = Drawing.new("Line")
        l.Thickness = 1
        l.Transparency = 1
        l.Visible = false
        e.lines[i] = l
    end
    e.hpBg = Drawing.new("Square")
    e.hpBg.Filled = true
    e.hpBg.Thickness = 1
    e.hpBg.Visible = false
    e.hpFill = Drawing.new("Square")
    e.hpFill.Filled = true
    e.hpFill.Thickness = 1
    e.hpFill.Visible = false
    e.name = Drawing.new("Text")
    e.name.Size = 13
    e.name.Center = true
    e.name.Outline = true
    e.name.Visible = false
    pool[#pool + 1] = e
    return e
end

local function hide(e)
    for i = 1, MAXBONES do
        if e.lines[i] then e.lines[i].Visible = false end
    end
    e.hpBg.Visible = false
    e.hpFill.Visible = false
    e.name.Visible = false
end

--═══════════ ESP 主循环 ═══════════
local frame = 0

RunService.RenderStepped:Connect(function()
    frame = frame + 1
    if frame % CFG.espRefresh ~= 0 then return end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position

    local idx = 0
    for p, c in pairs(cache) do
        local head, hrp, hum, ch = c.head, c.hrp, c.hum, c.char
        local drew = false

        if CFG.espOn and head and hrp and hum and hum.Health > 0
        and head.Parent and hrp.Parent and not isAlly(p) then
            local dist = (hrp.Position - camPos).Magnitude
            if dist <= CFG.espMaxDist then
                local headPos, onScreen = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local footPos = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                if onScreen and headPos.Z > 0 then
                    idx = idx + 1
                    local e = pool[idx] or newPool()
                    local now = os.clock()
                    if now - (c.visAt or 0) > (CFG.visRefresh / 60) then
                        c.visible = canSee(head, ch, cam)
                        c.visAt = now
                    end
                    local vis = c.visible
                    local col = vis and CFG.colVisible or CFG.colHidden
                    local drewAny = false

                    -- 骨骼（部件已经在缓存里，这里只做投影）
                    if CFG.showBones then
                        local bl = c.bones
                        for i = 1, MAXBONES do
                            local l = e.lines[i]
                            if l then
                                local pair = bl and bl[i]
                                if pair then
                                    local sa, oka = cam:WorldToViewportPoint(pair[1].Position)
                                    local sb, okb = cam:WorldToViewportPoint(pair[2].Position)
                                    if oka and okb and sa.Z > 0 and sb.Z > 0 then
                                        l.Visible = true
                                        l.From = Vector2.new(sa.X, sa.Y)
                                        l.To   = Vector2.new(sb.X, sb.Y)
                                        l.Color = col
                                        drewAny = true
                                    else
                                        l.Visible = false
                                    end
                                else
                                    l.Visible = false
                                end
                            end
                        end
                    end

                    -- 血量条：贴着头顶往下一段，宽度按距离自适应
                    local topY = headPos.Y
                    local botY = footPos.Y
                    local barH = math.clamp(math.abs(botY - topY), 20, 400)
                    local bx = headPos.X - 22
                    if CFG.showHealth and hum.MaxHealth > 0 then
                        local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                        e.hpBg.Visible = true
                        e.hpBg.Size = Vector2.new(4, barH)
                        e.hpBg.Position = Vector2.new(bx, topY)
                        e.hpBg.Color = Color3.fromRGB(20, 20, 20)
                        e.hpFill.Visible = true
                        e.hpFill.Size = Vector2.new(4, barH * ratio)
                        e.hpFill.Position = Vector2.new(bx, topY + barH * (1 - ratio))
                        e.hpFill.Color = Color3.fromRGB(
                            math.floor(255 * (1 - ratio)) + 40,
                            math.floor(220 * ratio) + 30, 70)
                        drewAny = true
                    end

                    if CFG.showName then
                        e.name.Visible = true
                        e.name.Text = string.format("%s  %d%%  %dm", p.Name,
                            math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100), math.floor(dist))
                        e.name.Position = Vector2.new(headPos.X, topY - 18)
                        e.name.Color = col
                        drewAny = true
                    end

                    drew = drewAny
                    if not drew then hide(e) end
                end
            end
        end

        if not drew then
            -- 这个玩家这一帧没画：找到属于他的对象池太麻烦，靠末尾统一清理
        end
    end

    -- 把没用到的对象池全部隐藏
    for i = idx + 1, #pool do hide(pool[i]) end
end)

--═══════════ 开火检测（弹药变少 = 刚开了一枪） ═══════════
local function findModule(name)
    local ps = LP:FindFirstChild("PlayerScripts")
    local direct = {
        ps and ps:FindFirstChild("Controllers") and ps.Controllers:FindFirstChild(name),
        ps and ps:FindFirstChild("Modules") and ps.Modules:FindFirstChild(name),
        RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild(name),
    }
    for _, m in ipairs(direct) do
        if m and m:IsA("ModuleScript") then return m end
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
        if not f then return nil end
        return f.EquippedItem
    end)
    return ok and item or nil
end

local firingUntil = 0
local lastAmmo = nil

if CFG.aimOn then
    task.spawn(function()
        while task.wait(0.05) do
            local item = equippedItem()
            local ammo
            pcall(function() ammo = item and item.Get and item:Get("Ammo") end)
            if type(ammo) == "number" then
                if lastAmmo and ammo < lastAmmo then
                    firingUntil = os.clock() + CFG.aimHoldSec
                end
                lastAmmo = ammo
            else
                lastAmmo = nil
            end
        end
    end)
end

--═══════════ AIM（只在开火瞬间锁，且必须看得见） ═══════════
if CFG.aimOn then
    RunService:BindToRenderStep("espaim_lock", Enum.RenderPriority.Camera.Value + 1, function(dt)
        if os.clock() > firingUntil then return end

        local cam = workspace.CurrentCamera
        if not cam then return end
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end

        local vp = cam.ViewportSize
        local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

        local best, bestScore = nil, math.huge
        for p, c in pairs(cache) do
            local head, hum, ch = c.head, c.hum, c.char
            if head and hum and hum.Health > 0 and head.Parent and not isAlly(p) then
                local dd = (head.Position - myRoot.Position).Magnitude
                if dd <= CFG.aimMaxDist then
                    local sp, on = cam:WorldToViewportPoint(head.Position)
                    if on and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d <= CFG.aimFOV and d < bestScore then
                            if (not CFG.visibleOnly) or canSee(head, ch, cam) then
                                bestScore = d
                                best = head
                            end
                        end
                    end
                end
            end
        end

        if best then
            local camPos = cam.CFrame.Position
            local goal = CFrame.lookAt(camPos, best.Position)
            local diff = (goal.LookVector - cam.CFrame.LookVector).Magnitude
            if diff < CFG.aimSnapAngle then
                cam.CFrame = goal
            else
                -- 左右 / 上下分开追：pitch 追得更快，抬头低头更跟手
                local curPitch, curYaw = cam.CFrame:ToOrientation()
                local goalPitch, goalYaw = goal:ToOrientation()

                -- 指数平滑：alpha = 1 - e^(-k*dt)，手感比线性插值顺，且不受帧率影响
                local kYaw   = -math.log(math.max(1 - CFG.aimSmoothYaw,   0.001))
                local kPitch = -math.log(math.max(1 - CFG.aimSmoothPitch, 0.001))
                local aYaw   = math.clamp(1 - math.exp(-kYaw   * dt), 0.02, 1)
                local aPitch = math.clamp(1 - math.exp(-kPitch * dt), 0.02, 1)

                local dy = goalYaw - curYaw
                if dy > math.pi then dy = dy - math.pi * 2
                elseif dy < -math.pi then dy = dy + math.pi * 2 end

                local newYaw   = curYaw   + dy * aYaw
                local newPitch = curPitch + (goalPitch - curPitch) * aPitch

                cam.CFrame = CFrame.new(camPos)
                    * CFrame.Angles(0, newYaw, 0)
                    * CFrame.Angles(newPitch, 0, 0)
            end
        end
    end)
end

print("[ESPAIM] 已加载 · 骨骼透视 + 开火瞬间锁头（无按钮）")
