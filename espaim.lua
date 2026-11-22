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

--═══════════ Rivals 原生接口（静默自瞄要用） ═══════════
local RIVALS = { cam = nil, util = nil }
pcall(function()
    local rem = RS:WaitForChild("Remotes", 15)
    local rep = rem and rem:WaitForChild("Replication", 10)
    local fighter = rep and rep:WaitForChild("Fighter", 10)
    if fighter then
        RIVALS.cam = fighter:WaitForChild("UpdateCameraRotation", 10)
    end
    local mods = RS:WaitForChild("Modules", 10)
    local util = mods and mods:WaitForChild("Utility", 10)
    if util then pcall(function() RIVALS.util = require(util) end) end
    print(string.format("[ESPAIM] 接口: cam=%s util=%s",
        tostring(RIVALS.cam ~= nil), tostring(RIVALS.util ~= nil)))
end)

--═══════════ 参数 ═══════════
local CFG = {
    espOn       = true,
    espMaxDist  = 900,
    espRefresh  = 1,      -- ESP 每帧刷（这块不卡）
    visRefresh  = 3,      -- 可见性(射线)每几帧算一次，结果缓存
    showBones   = true,
    showHealth  = true,
    showName    = true,
    colVisible  = Color3.fromRGB(255, 60, 60),   -- 能看见 = 红
    colHidden   = Color3.fromRGB(60, 255, 120),  -- 被挡住 = 绿
    aimOn       = false,  -- 相机锁定：关掉，视角完全交给你自己
    aimFOV      = 300,   -- 屏幕范围（像素半径），调大能锁更靠边的目标
    -- 弹簧平滑（照 Kicia 的 critically damped spring 抄的），比线性插值自然得多
    aimCircleDeg   = 8,     -- 进入这个角度圈 = 开始精细锁头（圈外瞄身体、圈内上头）
    fastSpeed      = 50,    -- 圈外速度（甩得快）
    slowSpeed      = 19,    -- 圈内速度（精调，慢一点才像人）
    springSpeed    = 34,    -- 基础频率（下面两个会覆盖它）
    springDamper   = 0.9,   -- 略微欠阻尼 → 有一点点"手"的过冲，不做完美机器
    aimSnapAngle   = 0.002, -- 几乎不硬跳（之前 0.015 那一下就是"咔"的来源）
    approachBoost  = 2.6,   -- 离得远时额外加速的倍率上限
    approachGain   = 8,     -- 多快进入加速状态
    tremor         = 0.00035, -- 生理抖动幅度（弧度），0 = 关掉
    -- 压枪 / 后坐力清零
    recoilOn       = false,  -- 压枪关掉：和自瞄一起改 CFrame 就是抖的根源
    zeroRecoil     = true,  -- 尝试直接把武器 Info 里的后坐力字段清零
    logGunInfo     = true,  -- 把每把枪的后坐力参数写进 guninfo.txt
    recoilComp     = 1.0,   -- 后坐力补偿比例，1.0 = 完全抵消
    recoilYawComp  = 0.85,  -- 左右抖动补偿
    recoilEvery    = 1,     -- 每帧都算，隔帧会抖
    -- 静默自瞄
    silentOn       = true,
    silentAlways   = true,  -- 开火检测失败时也发静默（否则一发都不会生效）
    silentEvery    = 3,     -- 每几帧发一次视角包（每帧发会卡）
    silentStepDeg  = 4.2,   -- 每次最多推进多少度（贴着服务端 5° 上限走）
    silentRangeDeg = 360,   -- 静默覆盖角度，360 = 背后的人也能拐
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

--═══════════ 弹簧平滑（临界阻尼） ═══════════
-- 和 Kicia 的 c5 Spring 同一个公式：给定 p0/v0/target/speed/damper，返回下一帧的 p 和 v。
local function springStep(p0, v0, target, speed, damper, dt)
    local t = speed * dt
    local d = damper or 1
    local d2 = d * d
    local h, si, co
    if d2 < 1 then
        h = math.sqrt(1 - d2)
        local ep = math.exp(-d * t) / h
        co, si = ep * math.cos(h * t), ep * math.sin(h * t)
    else
        h = 1
        local ep = math.exp(-d * t)
        co, si = ep, ep * t
    end
    local a0 = h * co + d * si
    local a1 = 1 - a0
    local a2 = si / speed
    local b0 = -speed * si
    local b1 = speed * si
    local b2 = h * co - d * si
    return a0 * p0 + a1 * target + a2 * v0, b0 * p0 + b1 * target + b2 * v0
end

local vYaw, vPitch = 0, 0
local aimLocked = false
local sentYaw = nil      -- 已经上报给服务端的视角，逐帧往目标挪

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
local ammoSeen = false
local ammoLogged = false

if CFG.aimOn then
    task.spawn(function()
        while task.wait(0.05) do
            local item = equippedItem()
            local ammo
            pcall(function() ammo = item and item.Get and item:Get("Ammo") end)
            if type(ammo) == "number" then
                ammoSeen = true
                if lastAmmo and ammo < lastAmmo then
                    firingUntil = os.clock() + CFG.aimHoldSec
                end
                lastAmmo = ammo
            else
                if not ammoLogged then
                    ammoLogged = true
                    pcall(function()
                        if writefile then
                            writefile("silent_debug.txt", "读不到 Ammo 字段（item:Get(\"Ammo\") = " ..
                                tostring(ammo) .. "），已退化为常驻静默")
                        end
                    end)
                end
                lastAmmo = nil
            end
        end
    end)
end

--═══════════ AIM（只在开火瞬间锁，且必须看得见） ═══════════
if false and CFG.aimOn then
    RunService:BindToRenderStep("espaim_lock", Enum.RenderPriority.Camera.Value + 1, function(dt)
        if os.clock() > firingUntil then return end

        local cam = workspace.CurrentCamera
        if not cam then return end
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end

        local vp = cam.ViewportSize
        local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

        local best, bestScore, bestChar = nil, math.huge, nil
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
                                bestChar = ch
                            end
                        end
                    end
                end
            end
        end

        aimLocked = (best ~= nil)
        if best then
            local camPos = cam.CFrame.Position
            local bodyPart = bestChar and (bestChar:FindFirstChild("UpperTorso") or bestChar:FindFirstChild("HumanoidRootPart"))
            local bodyPos = bodyPart and (bodyPart.Position + Vector3.new(0, 0.8, 0)) or best.Position

            -- 当前准星离目标头还差多少角度
            local toHead = best.Position - camPos
            local angle = 0
            if toHead.Magnitude > 0.01 then
                angle = math.acos(math.clamp(cam.CFrame.LookVector:Dot(toHead.Unit), -1, 1))
            end

            -- 两段式：圈外先奔身体（快），进圈后转头上（慢、精细）
            local aimPoint, baseSpeed
            if angle > math.rad(CFG.aimCircleDeg) then
                aimPoint  = bodyPos
                baseSpeed = CFG.fastSpeed
            else
                aimPoint  = best.Position
                baseSpeed = CFG.slowSpeed
            end

            local goal = CFrame.lookAt(camPos, aimPoint)
            local curPitch, curYaw = cam.CFrame:ToOrientation()
            local goalPitch, goalYaw = goal:ToOrientation()

            local dy = goalYaw - curYaw
            if dy > math.pi then dy = dy - math.pi * 2
            elseif dy < -math.pi then dy = dy + math.pi * 2 end
            goalYaw = curYaw + dy

            -- 开火期间要稳：不加速、不过冲、不抖手。
            -- 这时候后坐力在顶、自瞄在追，两边一夹就容易抖成筛子。
            local firing = os.clock() < firingUntil

            local gap = math.abs(goalYaw - curYaw) + math.abs(goalPitch - curPitch)
            local boost = 1 + math.min(gap * CFG.approachGain, CFG.approachBoost)
            if firing then boost = 1 end

            local speedScale = firing and 0.55 or 1
            local damperNow  = firing and 1.0 or CFG.springDamper

            local speedYaw   = baseSpeed * boost * speedScale
            local speedPitch = baseSpeed * boost * 1.2 * speedScale

            local newYaw, newVYaw     = springStep(curYaw,   vYaw,   goalYaw,   speedYaw,   damperNow, dt)
            local newPitch, newVPitch = springStep(curPitch, vPitch, goalPitch, speedPitch, damperNow, dt)

            if CFG.tremor > 0 and not firing then
                local t2 = os.clock() * 11
                newYaw   = newYaw   + math.sin(t2 * 1.7) * CFG.tremor
                newPitch = newPitch + math.sin(t2 * 2.3 + 1.1) * CFG.tremor * 0.7
            end

            vYaw, vPitch = newVYaw, newVPitch

            if math.abs(goalYaw - newYaw) < CFG.aimSnapAngle
            and math.abs(goalPitch - newPitch) < CFG.aimSnapAngle then
                cam.CFrame = goal
                vYaw, vPitch = 0, 0
            else
                cam.CFrame = CFrame.new(camPos)
                    * CFrame.Angles(0, newYaw, 0)
                    * CFrame.Angles(newPitch, 0, 0)
            end

            -- 静默：服务端只认"视角变化 ≤5°"的包，一次跨太多就丢。
            -- 所以每帧只把上报视角往目标推 silentStepDeg，几帧之内平滑挪过去 ——
            -- 这就是为什么近距离 100% 中、远角度全空。
            if CFG.silentOn and RIVALS.cam and RIVALS.util then
                local curYawNow = select(2, cam.CFrame:ToOrientation())
                local _, yawGoal = goal:ToOrientation()

                if sentYaw == nil then sentYaw = curYawNow end
                if os.clock() > firingUntil then sentYaw = curYawNow end   -- 没在打就跟相机走

                local dyS = yawGoal - sentYaw
                if dyS > math.pi then dyS = dyS - math.pi * 2
                elseif dyS < -math.pi then dyS = dyS + math.pi * 2 end

                if math.abs(dyS) <= math.rad(CFG.silentRangeDeg) then
                    local maxStep = math.rad(CFG.silentStepDeg)
                    local step = math.clamp(dyS, -maxStep, maxStep)
                    sentYaw = sentYaw + step
                    if frame % CFG.silentEvery == 0 then
                        pcall(function()
                            RIVALS.cam:FireServer(RIVALS.util:EncodeCameraRotation(Vector2.new(0, sentYaw)), nil)
                        end)
                    end
                end
            end
        else
            vYaw, vPitch = 0, 0
        end
    end)
end

--═══════════ 武器后坐力：读参数 + 尝试清零 ═══════════
-- Rivals 每把枪的后坐力存在 item.Info 里。先把所有相关字段抄下来（guninfo.txt），
-- 再试着清零 —— 客户端能改的话就不用靠相机硬压了。
local gunLog = {}
local function logGun(line)
    gunLog[#gunLog + 1] = line
    if #gunLog > 200 then table.remove(gunLog, 1) end
    pcall(function()
        if writefile then writefile("guninfo.txt", table.concat(gunLog, "\n")) end
    end)
end

-- 这些是 guninfo.txt 里读回来的真实字段名（Rivals 的武器 Info 结构）
local recoilKeys = {
    "ShootRecoil",                      -- 后坐力主值
    "ShootSpread",                      -- 静止扩散
    "ShootSpreadPerVelocityUnit",       -- 移动中额外扩散
    "ShootSpreadPerVelocityLimit",      -- 移动扩散上限
    "AimSpreadMultiplier",              -- 开镜扩散倍率
}

local function touchGunInfo(item)
    local info = item and item.Info
    if type(info) ~= "table" then return nil end
    local found = {}
    for _, key in ipairs(recoilKeys) do
        local v = info[key]
        if v ~= nil then
            local before = tostring(v)
            if CFG.zeroRecoil and type(v) == "number" and v ~= 0 then
                local ok = pcall(function() info[key] = 0 end)
                local after = ok and tostring(info[key]) or "改失败"
                table.insert(found, string.format("%s %s→%s", key, before, after))
            else
                table.insert(found, string.format("%s=%s", key, before))
            end
        end
    end
    -- 相机位移后坐力是 Vector2(userdata)，单独探一下
    if info.ShootCameraDisplacementRecoil ~= nil then
        table.insert(found, "ShootCameraDisplacementRecoil=" .. tostring(info.ShootCameraDisplacementRecoil))
    end
    return found
end

task.spawn(function()
    local lastItem = nil
    while task.wait(1) do
        local item = equippedItem()
        if item then
            local refresh = (item ~= lastItem)
            if refresh then lastItem = item end
            local nm = ""
            pcall(function() nm = item.Get and item:Get("Name") or "" end)
            local found = refresh and touchGunInfo(item) or nil
            if found then
                logGun(string.format("[%s] %s", tostring(nm), #found > 0
                    and table.concat(found, "  ") or "（Info 里没有后坐力相关字段）"))
                -- 顺便把全部字段名也列一遍，方便下次对照
                local keys = {}
                for k, v in pairs(item.Info) do
                    if type(v) == "number" then table.insert(keys, tostring(k)) end
                end
                table.sort(keys)
                logGun("    全部数值字段: " .. table.concat(keys, ", "))
            end
        end
    end
end)

--═══════════ 压枪 ═══════════
-- Roblox 客户端拿不到"后坐力原始数值"（那在内核里，只有外部读内存才能碰到），
-- 但能拿到相机被顶出来的角度。做法就是把每一帧被顶上去的量原样压回去 ——
-- 补偿比例 1.0 时，枪口在世界坐标里基本不动。
local lastPitch2, lastYaw2 = nil, nil
local weaponFactor = 1.0
local weaponYawFactor = 0.85
local weaponName = ""
local recoilFrame = 0

task.spawn(function()
    while task.wait(0.5) do
        local item = equippedItem()
        local n = ""
        pcall(function() n = item and item.Get and item:Get("Name") or "" end)
        weaponName = string.lower(tostring(n or ""))
        if string.find(weaponName, "sniper", 1, true) or string.find(weaponName, "revolver", 1, true) then
            weaponFactor, weaponYawFactor = 0.7, 0.6
        elseif string.find(weaponName, "shotgun", 1, true) then
            weaponFactor, weaponYawFactor = 1.0, 1.0
        elseif string.find(weaponName, "wildcat", 1, true) then
            weaponFactor, weaponYawFactor = 1.0, 0.9
        elseif string.find(weaponName, "smg", 1, true) or string.find(weaponName, "minigun", 1, true) then
            weaponFactor, weaponYawFactor = 1.0, 1.0
        elseif weaponName == "" then
            weaponFactor, weaponYawFactor = 0, 0
        else
            weaponFactor, weaponYawFactor = 1.0, 0.85
        end
    end
end)

RunService.RenderStepped:Connect(function()
    recoilFrame = recoilFrame + 1
    if recoilFrame % CFG.recoilEvery ~= 0 then return end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local pitch, yaw = cam.CFrame:ToOrientation()

    if CFG.recoilOn and not aimLocked and os.clock() < firingUntil
    and lastPitch2 and weaponFactor > 0 then
        local dPitch = pitch - lastPitch2
        local dYaw   = yaw   - lastYaw2
        if dYaw > math.pi then dYaw = dYaw - math.pi * 2
        elseif dYaw < -math.pi then dYaw = dYaw + math.pi * 2 end

        local compPitch = 0
        local compYaw = 0
        if dPitch > 0.0004 then compPitch = -dPitch * CFG.recoilComp * weaponFactor end
        -- 横向抖动：只在幅度很小（1°以内）时算作后坐力，避免把玩家自己转身也吃掉
        if math.abs(dYaw) > 0.0004 and math.abs(dYaw) < 0.018 then
            compYaw = -dYaw * CFG.recoilYawComp * weaponYawFactor
        end

        if compPitch ~= 0 or compYaw ~= 0 then
            cam.CFrame = cam.CFrame * CFrame.Angles(compPitch, compYaw, 0)
            pitch, yaw = cam.CFrame:ToOrientation()
        end
    end

    lastPitch2, lastYaw2 = pitch, yaw
end)

--═══════════ 静默自瞄（hook UseItem，改包不改视角） ═══════════
-- UpdateCameraRotation 只影响"别人看到你瞄哪"，不参与命中判定 —— 所以之前那版全空。
-- 真正要让子弹拐弯，只能改玩家自己发出去的 UseItem 包，也就是 hook 它。
-- 只 hook 这一个函数（不是 __namecall），开火时才进一次，不会卡。
local SLOGS = {}
local function slog(m)
    SLOGS[#SLOGS + 1] = os.date("%H:%M:%S") .. " " .. tostring(m)
    if #SLOGS > 120 then table.remove(SLOGS, 1) end
    pcall(function() if writefile then writefile("silent_debug.txt", table.concat(SLOGS, "\n")) end end)
end

local silentTarget = nil     -- 每帧预选，hook 里直接用，别在 hook 里算
local hookOK = false

-- 目标预选（和 ESP 同一套筛选）
RunService.RenderStepped:Connect(function()
    if not CFG.silentOn then silentTarget = nil return end
    local cam = workspace.CurrentCamera
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (cam and myRoot) then silentTarget = nil return end

    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local best, bestScore = nil, math.huge
    for p, c in pairs(cache) do
        local head, hum = c.head, c.hum
        if head and hum and hum.Health > 0 and head.Parent and not isAlly(p) then
            if (head.Position - myRoot.Position).Magnitude <= CFG.aimMaxDist then
                local sp, on = cam:WorldToViewportPoint(head.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d <= CFG.aimFOV and d < bestScore then
                        if (not CFG.visibleOnly) or canSee(head, c.char, cam) then
                            bestScore = d
                            best = head
                        end
                    end
                end
            end
        end
    end
    silentTarget = best
end)

local function installSilentHook()
    if hookOK then return end
    if type(hookfunction) ~= "function" then
        slog("执行器没有 hookfunction，静默用不了")
        return
    end
    local ok, err = pcall(function()
        local old = hookfunction(RIVALS.use.FireServer, function(self, objId, action, data, extra)
            if CFG.silentOn and silentTarget and type(data) == "table" and RIVALS.util then
                local ok2 = pcall(function()
                    -- 完全照开源 ragebot 的构造：
                    --   [ ] aimCF        = 从"目标旁边"看向目标头（起点不能是相机，服务端会按墙挡）
                    --   [] targetCF     = 目标头自己的 CFrame
                    --   [] targetHead   = 目标部件
                    --   [] headOffset   = 目标局部空间里的微小偏移
                    local C0, C1, C2, C3 = string.char(0), string.char(1), string.char(2), string.char(3)
                    local shot = data[C1]
                    if type(shot) == "table" then
                        local targetPos = silentTarget.Position
                        -- 站位取目标旁边一点（相当于"人在那儿"），不是相机位置
                        local originPos = targetPos
                            + Vector3.new(math.random(-20, 20) / 10, math.random(0, 20) / 10, math.random(-20, 20) / 10)
                        local aimCF  = CFrame.lookAt(originPos, targetPos)
                        local targetCF = silentTarget.CFrame
                        local aimedPos = targetPos + Vector3.new(
                            (math.random() - 0.5) * 0.1,
                            (math.random() - 0.5) * 0.1,
                            (math.random() - 0.5) * 0.1)
                        local objSpaceHeadOffset = targetCF:ToObjectSpace(CFrame.new(aimedPos))

                        shot[C0] = RIVALS.util:EncodeCFrame(aimCF)
                        shot[C1] = RIVALS.util:EncodeCFrame(targetCF)
                        shot[C2] = silentTarget
                        shot[C3] = RIVALS.util:EncodeCFrame(objSpaceHeadOffset)
                    end
                end)
                if ok2 then slog("改包 → 目标（含 [\3] 偏移）") end
            end
            return old(self, objId, action, data, extra)
        end)
        hookOK = true
    end)
    slog(hookOK and "静默 hook 已安装" or ("静默 hook 失败: " .. tostring(err)))
end

if CFG.silentOn then installSilentHook() end

print("[ESPAIM] 已加载 · 骨骼透视 + 开火瞬间锁头（无按钮）")
