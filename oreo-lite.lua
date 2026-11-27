--[[
  ==========================================================================
   OREO LITE  ·  Rivals  ·  v1.0
   从 Kicia Rebuild（vendor/kicia.lua）里剥出来的 5 个模块：
     Silent Aim / Aimbot / Fire Assist / Player ESP / Weapon Visuals
   不含 Kicia 的 UI 框架、配置系统、Cosmetics、Movement、World、
   Automation、Ragebot、Detection —— 只保留这五块 + 一个迷你菜单。

   一键加载：
     loadstring(game:HttpGet(OREOLITE_URL))()  -- OREOLITE_URL 见交付说明

   依赖执行器：hookmetamethod / getgenv / Drawing(可选) / mouse1click(可选)
  ==========================================================================
]]

local VERSION = "1.0.0"

local old = getgenv().OreoLite
if old and type(old) == "table" and old.Unload then pcall(old.Unload) end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer
local function cam() return Workspace.CurrentCamera end
local function viewport()
    local c = cam()
    return c and c.ViewportSize or Vector2.new(1920, 1080)
end

-- 手机：没有键盘，按键全失效，改用屏幕上的悬浮触发键
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--=========================  配 置  =========================--
local C = {
    aimbot = {
        enabled = false, key = Enum.KeyCode.E, mode = "Camera",
        fov = 150, smooth = 0.28, part = "Head",
        wallcheck = true, teamcheck = true, circle = true,
        touchHeld = false,
    },
    silent = {
        enabled = false, key = Enum.KeyCode.Q, fov = 260, part = "Head",
        chance = 100, wallcheck = false, teamcheck = true,
    },
    fireassist = {
        enabled = false, key = Enum.KeyCode.F, fov = 130,
        flick = 0.09, shoot = false, cooldown = 0.22, part = "Head",
        touchHeld = false,
    },
    esp = {
        enabled = false, box = true, name = true, health = true,
        distance = true, maxdist = 1200,
        color = Color3.fromRGB(120, 220, 255),
    },
    wv = {
        chams = false, transparency = 0.65,
        material = "Glass",
        nomuzzle = false, tracers = false,
        tracerColor = Color3.fromRGB(120, 220, 255),
    },
}

--=========================  工 具  =========================--
local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function v2(x, y) return Vector2.new(x, y) end

local function isAlive(plr)
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function sameArena(plr)
    local mine = LP:GetAttribute("EnvironmentID")
    if mine == nil then return true end
    return plr:GetAttribute("EnvironmentID") == mine
end

local function isTeamMate(plr, cfg)
    if plr == LP then return true end
    if cfg and cfg.teamcheck == false then return false end
    local a, b = plr.Team, LP.Team
    if a == nil or b == nil then return false end
    return a == b
end

--=========================  游 戏 桥  =========================--
-- Utility 模块提供 EncodeCFrame：Rivals 的射击包用 "\0".."\3" 四个键，
-- 值都是 Utility:EncodeCFrame(CFrame) 的结果（见 kicia 67266 行）。
local Bridge = { utility = nil, fc = nil }

local function preloadUtility()
    if Bridge.utility then return Bridge.utility end
    local m = safe(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 5)
        if not modules then return nil end
        return require(modules:WaitForChild("Utility", 5))
    end)
    if type(m) == "table" then Bridge.utility = m end
    return Bridge.utility
end

local function fighterController()
    if Bridge.fc then return Bridge.fc end
    local fc = safe(function()
        return require(LP.PlayerScripts.Controllers.FighterController)
    end)
    if fc then Bridge.fc = fc end
    return fc
end

local function localFighter()
    local fc = fighterController()
    if not fc then return nil end
    return safe(function() return fc:GetFighter(LP) end)
end

--=========================  目 标 选 择  =========================--
local Targets = {}

local function partOf(plr, wanted)
    local char = plr.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    local p = char:FindFirstChild(wanted or "Head")
    if p and p:IsA("BasePart") then return p, char end
    p = char:FindFirstChild("HumanoidRootPart")
    if p then return p, char end
    return nil
end

local function screenOf(part)
    local c = cam()
    if not c then return nil, false end
    local pos, onScreen = c:WorldToViewportPoint(part.Position)
    return v2(pos.X, pos.Y), onScreen, pos.Z
end

local function rayClear(part)
    local c = cam()
    if not c then return true end
    local char = LP.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char, c }
    params.IgnoreWater = true
    local origin = c.CFrame.Position
    local dir = part.Position - origin
    local hit = Workspace:Raycast(origin, dir, params)
    if hit == nil then return true end
    return hit.Instance:IsDescendantOf(part.Parent)
end

-- 屏幕中心距离优先；同分取近的
function Targets.best(cfg, originScreen)
    local c = cam()
    if not c then return nil end
    local center = originScreen or viewport() / 2
    local best, bestScore, bestData = nil, math.huge, nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeamMate(plr, cfg) and sameArena(plr) then
            local part = partOf(plr, cfg.part)
            if part then
                local sp, onScreen = screenOf(part)
                if sp and onScreen then
                    local d = (sp - center).Magnitude
                    if d <= (cfg.fov or 150) then
                        local ok = true
                        if cfg.wallcheck then ok = rayClear(part) end
                        if ok then
                            local score = d
                            if score < bestScore then
                                bestScore = score
                                best = plr
                                bestData = { player = plr, part = part, screen = sp, dist = d }
                            end
                        end
                    end
                end
            end
        end
    end
    return bestData
end

--=========================  绘 制 库  =========================--
-- Drawing 优先（轻、不进 CoreGui）；没有就退化成 ScreenGui + Frame。
local HasDrawing = safe(function() return type(Drawing) == "table" or type(Drawing) == "userdata" end) == true
local Draw = {}

function Draw.newLine()
    if HasDrawing then
        local l = Drawing.new("Line")
        l.Thickness = 1; l.Visible = false; l.Transparency = 1
        return { kind = "line", obj = l }
    end
    return nil
end

function Draw.newText()
    if HasDrawing then
        local t = Drawing.new("Text")
        t.Size = 13; t.Center = true; t.Outline = true; t.Visible = false
        return { kind = "text", obj = t }
    end
    return nil
end

function Draw.setLine(h, from, to, color, thickness, visible)
    if not h then return end
    local o = h.obj
    o.From = from; o.To = to; o.Color = color
    o.Thickness = thickness or 1
    o.Visible = visible ~= false
end

function Draw.setText(h, pos, text, color, size)
    if not h then return end
    local o = h.obj
    o.Position = pos; o.Text = text; o.Color = color
    o.Size = size or 13
    o.Visible = text ~= nil and text ~= ""
end

function Draw.hide(h)
    if h and h.obj then h.obj.Visible = false end
end

function Draw.remove(h)
    if h and h.obj then pcall(function() h.obj:Remove() end) end
end

--=========================  FOV 圆  =========================--
local fovCircle = nil
local function updateFovCircle(cfg)
    if not cfg.circle then
        if fovCircle then fovCircle.Visible = false end
        return
    end
    if not fovCircle and HasDrawing then
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 1
        fovCircle.Filled = false
        fovCircle.NumSides = 60
        fovCircle.Transparency = 0.6
        fovCircle.Color = C.esp.color
    end
    if fovCircle then
        fovCircle.Radius = cfg.fov
        fovCircle.Position = viewport() / 2
        fovCircle.Visible = true
    end
end

--=========================  A I M B O T  =========================--
-- 原版走游戏的 CameraController:SetRotation（25354 行），这里两套都实现：
--   "Camera"  -> 直接写 Camera.CFrame（最兼容）
--   "Native"  -> 写 CameraController.Rotation（和 Kicia 一样，交给游戏相机管线）
local Aimbot = { active = false }

local function cameraControllerSet()
    local cc = safe(function()
        local controllers = LP.PlayerScripts:FindFirstChild("Controllers")
        if not controllers then return nil end
        return require(controllers.CameraController)
    end)
    if not cc then return nil end
    local setRotation = safe(function()
        return getmetatable(cc).__index.SetRotation
    end)
    if not setRotation then return nil end
    return { cc = cc, set = setRotation }
end

local nativeCam = nil

local function aimAtLook(goalCF)
    local c = cam()
    c.CFrame = goalCF
end

function Aimbot.step(dt)
    local cfg = C.aimbot
    if not cfg.enabled then return end
    local held = UserInputService:IsKeyDown(cfg.key) or cfg.touchHeld
    if not held then return end
    local t = Targets.best(cfg)
    if not t then return end
    local c = cam()
    if not c then return end
    local goal = CFrame.lookAt(c.CFrame.Position, t.part.Position)
    if cfg.mode == "Native" then
        if nativeCam == nil then nativeCam = cameraControllerSet() end
        if nativeCam then
            local _, yaw, pitch = goal:ToEulerAnglesYXZ()
            -- 游戏 Rotation 是 (pitch, yaw)
            safe(function() nativeCam.set(nativeCam.cc, Vector2.new(pitch, yaw)) end)
            return
        end
    end
    c.CFrame = c.CFrame:Lerp(goal, math.clamp(cfg.smooth, 0.01, 1))
end

--=========================  S I L E N T   A I M  =========================--
-- 思路和 Kicia 一样，但改在 RemoteEvent 层而不是内部事件总线：
--   FireServer(objectId, encode("StartShooting"), { ["\1"] = {
--        ["\0"] = EncodeCFrame(起点朝目标),
--        ["\1"] = EncodeCFrame(终点),
--        ["\2"] = 目标 BasePart,
--        ["\3"] = EncodeCFrame(枪口偏移),
--   } }, nil)
local Tracers -- forward（Weapon Visuals 段里赋值）
local Silent = { installed = false }

local function isShotPayload(payload)
    if type(payload) ~= "table" then return nil end
    local shot = payload["\1"]
    if type(shot) ~= "table" then return nil end
    if shot["\0"] == nil or shot["\1"] == nil then return nil end
    return shot
end

local function installSilent()
    if Silent.installed then return true end
    local hookMethod = getgenv().hookmetamethod or hookmetamethod
    if type(hookMethod) ~= "function" then return false end
    local oldNamecall
    oldNamecall = hookMethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and C.silent.enabled and type(self) == "userdata" then
            local args = { ... }
            local shot = isShotPayload(args[3])
            if shot then
                local U = Bridge.utility
                local t = Targets.best(C.silent)
                if U and t and math.random() <= (C.silent.chance / 100) then
                    local c = cam()
                    if c then
                        local origin = c.CFrame.Position
                        local aim = CFrame.lookAt(origin, t.part.Position)
                        shot["\0"] = U:EncodeCFrame(aim)
                        shot["\1"] = U:EncodeCFrame(aim)
                        shot["\2"] = t.part
                        if Tracers and C.wv.tracers then
                            Tracers.add(origin, t.part.Position)
                        end
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    Silent.installed = true
    return true
end

function Silent.step()
    if C.silent.enabled and not Silent.installed then
        -- utility 没预热就 hook 里会 yield，先在这里拉一次
        preloadUtility()
        installSilent()
    end
end

--=========================  F I R E   A S S I S T  =========================--
-- 原版是"屏幕轨迹甩枪 + 定时开火"（62552 行）。这里给同效果的最小实现：
-- 按下键 -> 在 flick 时长内把相机插值到目标 -> 到点后 mouse1click -> 冷却。
local FA = { state = "idle", timer = 0, target = nil, startCF = nil }

local function click()
    if IS_MOBILE then
        safe(function()
            VirtualInputManager:SendMouseButtonEvent(
                math.floor(viewport().X / 2), math.floor(viewport().Y / 2),
                0, true, game, 1)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(
                math.floor(viewport().X / 2), math.floor(viewport().Y / 2),
                0, false, game, 1)
        end)
        return
    end
    local ok = safe(function() mouse1click() end)
    if ok then return end
    safe(function()
        VirtualInputManager:SendMouseButtonEvent(
            math.floor(viewport().X / 2), math.floor(viewport().Y / 2),
            0, true, game, 1)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(
            math.floor(viewport().X / 2), math.floor(viewport().Y / 2),
            0, false, game, 1)
    end)
end

function FA.step(dt)
    local cfg = C.fireassist
    if not cfg.enabled then FA.state = "idle" return end

    if FA.state == "idle" then
        if (UserInputService:IsKeyDown(cfg.key) or cfg.touchHeld) then
            local t = Targets.best({ fov = cfg.fov, part = cfg.part, wallcheck = true })
            if t then
                FA.target = t
                FA.startCF = cam().CFrame
                FA.timer = 0
                FA.state = "flicking"
            end
        end
        return
    end

    if FA.state == "flicking" then
        if not FA.target or not FA.target.part.Parent then
            FA.state = "idle"; return
        end
        FA.timer = FA.timer + dt
        local alpha = math.clamp(FA.timer / math.max(cfg.flick, 0.01), 0, 1)
        local goal = CFrame.lookAt(cam().CFrame.Position, FA.target.part.Position)
        cam().CFrame = FA.startCF:Lerp(goal, alpha)
        if alpha >= 1 then
            if cfg.shoot then click() end
            FA.state = "cooldown"
            FA.timer = cfg.cooldown
        end
        return
    end

    if FA.state == "cooldown" then
        FA.timer = FA.timer - dt
        if FA.timer <= 0 then FA.state = "idle" end
    end
end

--=========================  P L A Y E R   E S P  =========================--
local ESP = { items = {} }

local function newEspEntry()
    return {
        boxTop = Draw.newLine(), boxBot = Draw.newLine(),
        boxL = Draw.newLine(), boxR = Draw.newLine(),
        name = Draw.newText(), dist = Draw.newText(),
        hpBg = Draw.newLine(), hp = Draw.newLine(),
    }
end

local function hideEntry(e)
    for _, v in pairs(e) do Draw.hide(v) end
end

local function destroyEntry(e)
    for _, v in pairs(e) do Draw.remove(v) end
end

local espLast = 0
function ESP.step()
    local nowEsp = os.clock()
    if nowEsp - espLast < 0.05 then return end
    espLast = nowEsp
    local cfg = C.esp
    if not HasDrawing then
        if type(ESP.fallbackStep) == "function" then ESP.fallbackStep() end
        return
    end
    if not cfg.enabled then
        for _, e in pairs(ESP.items) do hideEntry(e) end
        return
    end

    local c = cam()
    if not c then return end
    local seen = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeamMate(plr) then
            local part, char = partOf(plr, "Head")
            if part and char then
                local sp, onScreen, depth = screenOf(part)
                local dist = (c.CFrame.Position - part.Position).Magnitude
                if sp and onScreen and dist <= cfg.maxdist then
                    local e = ESP.items[plr]
                    if not e then
                        e = newEspEntry()
                        ESP.items[plr] = e
                    end
                    seen[plr] = true

                    local hrp = char:FindFirstChild("HumanoidRootPart") or part
                    local topPos = c:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                    local botPos = c:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local top = v2(topPos.X, topPos.Y)
                    local bot = v2(botPos.X, botPos.Y)
                    local h = math.abs(bot.Y - top.Y)
                    local w = h * 0.55
                    local left = v2(sp.X - w / 2, top.Y)
                    local right = v2(sp.X + w / 2, bot.Y)

                    if cfg.box then
                        Draw.setLine(e.boxTop, v2(left.X, top.Y), v2(right.X, top.Y), cfg.color, 1, true)
                        Draw.setLine(e.boxBot, v2(left.X, bot.Y), v2(right.X, bot.Y), cfg.color, 1, true)
                        Draw.setLine(e.boxL, v2(left.X, top.Y), v2(left.X, bot.Y), cfg.color, 1, true)
                        Draw.setLine(e.boxR, v2(right.X, top.Y), v2(right.X, bot.Y), cfg.color, 1, true)
                    else
                        Draw.hide(e.boxTop); Draw.hide(e.boxBot)
                        Draw.hide(e.boxL); Draw.hide(e.boxR)
                    end

                    if cfg.name then
                        Draw.setText(e.name, v2(sp.X, top.Y - 16),
                            plr.DisplayName or plr.Name, cfg.color, 13)
                    else
                        Draw.hide(e.name)
                    end

                    if cfg.distance then
                        Draw.setText(e.dist, v2(sp.X, bot.Y + 14),
                            string.format("%dm", math.floor(dist)), cfg.color, 12)
                    else
                        Draw.hide(e.dist)
                    end

                    if cfg.health then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        local hp = hum and (hum.Health / math.max(hum.MaxHealth, 1)) or 0
                        local barTop = v2(left.X - 5, top.Y)
                        local barBot = v2(left.X - 5, bot.Y)
                        Draw.setLine(e.hpBg, barTop, barBot, Color3.fromRGB(40, 40, 40), 3, true)
                        local filled = v2(left.X - 5, bot.Y - (bot.Y - top.Y) * hp)
                        Draw.setLine(e.hp, barTop, filled, Color3.fromRGB(90, 220, 120), 3, true)
                    else
                        Draw.hide(e.hpBg); Draw.hide(e.hp)
                    end
                else
                    local e = ESP.items[plr]
                    if e then hideEntry(e) end
                end
            end
        end
    end

    for plr, e in pairs(ESP.items) do
        if not seen[plr] then hideEntry(e) end
    end
end

function ESP.clear()
    for plr, e in pairs(ESP.items) do
        destroyEntry(e)
        ESP.items[plr] = nil
    end
end

--=========================  W E A P O N   V I S U A L S  =========================--
-- 原版的 Held Item Chams：给 viewmodel 的每个部件写 Material / Transparency，
-- 保留原材质时（Original）就只改透明度 —— 也就是"半透明皮肤"。
local WV = { snapshots = {}, applied = false }

local function findViewModel()
    local c = cam()
    if not c then return nil end
    for _, v in ipairs(c:GetChildren()) do
        if v:IsA("Model") then
            if v:FindFirstChild("Handle") or v.Name:lower():find("viewmodel") then
                return v
            end
        end
    end
    for _, v in ipairs(Workspace:GetChildren()) do
        if v:IsA("Model") and v.Name:lower():find("viewmodel") then
            return v
        end
    end
    return nil
end

local function snapshot(model)
    WV.snapshots = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            WV.snapshots[d] = {
                material = d.Material,
                transparency = d.Transparency,
                color = d.Color,
            }
        elseif d:IsA("Texture") or d:IsA("Decal") then
            WV.snapshots[d] = { transparency = d.Transparency }
        end
    end
end

local function restore(model)
    for inst, snap in pairs(WV.snapshots) do
        if inst and inst.Parent then
            if inst:IsA("BasePart") then
                safe(function() inst.Material = snap.material end)
            end
            safe(function() inst.Transparency = snap.transparency end)
        end
    end
    WV.snapshots = {}
    WV.applied = false
end

local wvLast = 0
function WV.step()
    local now = os.clock()
    if now - wvLast < 0.12 then return end
    wvLast = now
    local cfg = C.wv
    local model = findViewModel()
    if not model then return end

    if cfg.chams or cfg.nomuzzle then
        if not WV.applied then
            if not WV.model or WV.model ~= model then
                snapshot(model)
                WV.model = model
            end
            WV.applied = true
        end
        if cfg.chams then
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    local mat = cfg.material ~= "Original" and Enum.Material[cfg.material] or nil
                    if mat then safe(function() d.Material = mat end) end
                    safe(function() d.Transparency = cfg.transparency end)
                    for _, tx in ipairs(d:GetChildren()) do
                        if tx:IsA("Texture") or tx:IsA("Decal") then
                            safe(function() tx.Transparency = cfg.transparency end)
                        end
                    end
                end
            end
        end
        if cfg.nomuzzle then
            for _, d in ipairs(model:GetDescendants()) do
                local n = d.Name:lower()
                if n:find("muzzle") or n:find("flash") or n:find("smoke") then
                    safe(function() d.Transparency = 1 end)
                end
            end
        else
            for _, d in ipairs(model:GetDescendants()) do
                local n = d.Name:lower()
                if (n:find("muzzle") or n:find("flash") or n:find("smoke")) and WV.snapshots[d] then
                    safe(function() d.Transparency = WV.snapshots[d].transparency end)
                end
            end
        end
    elseif WV.applied then
        restore(WV.model)
    end
end

-- 弹道拖尾：每次射击记两个端点，屏幕空间画 2D 线并淡出
Tracers = { list = {}, pool = {} }

local function tracerLine()
    local l = Tracers.pool[#Tracers.pool]
    if l then
        Tracers.pool[#Tracers.pool] = nil
        return l
    end
    return Draw.newLine()
end

function Tracers.add(fromWorld, toWorld)
    if not C.wv.tracers or not HasDrawing then return end
    local c = cam()
    if not c then return end
    local a = c:WorldToViewportPoint(fromWorld)
    local b = c:WorldToViewportPoint(toWorld)
    if a.Z <= 0 or b.Z <= 0 then return end
    Tracers.list[#Tracers.list + 1] = {
        from = v2(a.X, a.Y), to = v2(b.X, b.Y), life = 0.45,
    }
end

function Tracers.step(dt)
    for i = #Tracers.list, 1, -1 do
        local t = Tracers.list[i]
        t.life = t.life - dt
        if t.life <= 0 then
            table.remove(Tracers.list, i)
        end
    end
    -- 用一个共用 pool 画
    local i = 1
    for _, t in ipairs(Tracers.list) do
        local l = Tracers.pool[i]
        if not l then
            l = Draw.newLine()
            Tracers.pool[i] = l
        end
        Draw.setLine(l, t.from, t.to, C.wv.tracerColor, 1, true)
        if l and l.obj then l.obj.Transparency = math.clamp(t.life / 0.45, 0, 1) end
        i = i + 1
    end
    for j = i, #Tracers.pool do
        Draw.hide(Tracers.pool[j])
    end
end

--=========================  迷 你 菜 单  =========================--
local Menu = { gui = nil, frame = nil, pages = {}, current = nil, open = false }

local function mkButton(parent, text, onClick, height)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, height or 26)
    b.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.fromRGB(235, 238, 245)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 13
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = parent
    b.MouseButton1Click:Connect(function()
        safe(onClick)
    end)
    return b
end

local function mkToggle(parent, label, getter, setter)
    local b = mkButton(parent, label .. ": " .. (getter() and "ON" or "OFF"), function()
        setter(not getter())
        b.Text = label .. ": " .. (getter() and "ON" or "OFF")
        b.BackgroundColor3 = getter() and Color3.fromRGB(30, 90, 60) or Color3.fromRGB(32, 34, 40)
    end)
    b.BackgroundColor3 = getter() and Color3.fromRGB(30, 90, 60) or Color3.fromRGB(32, 34, 40)
    return b
end

local function mkCycle(parent, label, values, getter, setter)
    local idx = 1
    for i, v in ipairs(values) do
        if v == getter() then idx = i end
    end
    local b = mkButton(parent, label .. ": " .. tostring(values[idx]), function()
        idx = idx % #values + 1
        setter(values[idx])
        b.Text = label .. ": " .. tostring(values[idx])
    end)
    return b
end

local function mkKeybind(parent, label, getter, setter)
    local capturing = false
    local b = mkButton(parent, label .. ": " .. getter().Name, function()
        capturing = true
        b.Text = "按一个键…"
    end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if capturing and not processed then
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                setter(input.KeyCode)
                b.Text = label .. ": " .. input.KeyCode.Name
            end
            capturing = false
        end
    end)
    return b
end

local function page(name)
    local p = Menu.pages[name]
    if not p then
        p = Instance.new("ScrollingFrame")
        p.Size = UDim2.new(1, -8, 1, -34)
        p.Position = UDim2.new(0, 4, 0, 30)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.ScrollBarThickness = 3
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.Visible = false
        p.Parent = Menu.frame
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = p
        Menu.pages[name] = p
    end
    return p
end

local function buildMenu()
    local gui = Instance.new("ScreenGui")
    gui.Name = "OreoLite"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

    local vw, vh = viewport().X, viewport().Y
    local uiScale = math.clamp(math.min(vw, vh) / 820, 0.9, 1.35)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, math.floor(260), 0, math.floor(430))
    frame.Position = UDim2.new(0, 20, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Visible = false
    frame.Parent = gui

    local scaleObj = Instance.new("UIScale")
    scaleObj.Scale = uiScale
    scaleObj.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 28)
    title.BackgroundColor3 = Color3.fromRGB(26, 28, 34)
    title.BorderSizePixel = 0
    title.Text = "  OREO LITE v" .. VERSION
    title.TextColor3 = Color3.fromRGB(150, 220, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 32)
    bar.Position = UDim2.new(0, 0, 0, 28)
    bar.BackgroundTransparency = 1
    bar.Parent = frame

    local names = { "AIM", "VIS", "WPN" }
    local tabs = {}
    for i, n in ipairs(names) do
        local t = Instance.new("TextButton")
        t.Size = UDim2.new(1 / #names, -4, 0, 26)
        t.Position = UDim2.new((i - 1) / #names, 2, 0, 3)
        t.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
        t.BorderSizePixel = 0
        t.Text = n
        t.TextColor3 = Color3.fromRGB(200, 205, 215)
        t.Font = Enum.Font.GothamMedium
        t.TextSize = 12
        t.Parent = bar
        t.MouseButton1Click:Connect(function()
            for _, p in pairs(Menu.pages) do p.Visible = false end
            page(n).Visible = true
            Menu.current = n
        end)
        tabs[i] = t
    end

    Menu.gui = gui
    Menu.frame = frame
    page("AIM").Visible = true
    Menu.current = "AIM"

    -- AIM 页
    local aim = page("AIM")
    mkToggle(aim, "Aimbot", function() return C.aimbot.enabled end, function(v) C.aimbot.enabled = v end)
    mkKeybind(aim, "Aim key", function() return C.aimbot.key end, function(v) C.aimbot.key = v end)
    mkCycle(aim, "Aim FOV", { 60, 100, 150, 220, 320, 450 }, function() return C.aimbot.fov end,
        function(v) C.aimbot.fov = v end)
    mkCycle(aim, "Smooth", { 0.08, 0.15, 0.28, 0.45, 0.7 }, function() return C.aimbot.smooth end,
        function(v) C.aimbot.smooth = v end)
    mkToggle(aim, "Wall check", function() return C.aimbot.wallcheck end,
        function(v) C.aimbot.wallcheck = v end)
    mkToggle(aim, "FOV circle", function() return C.aimbot.circle end,
        function(v) C.aimbot.circle = v end)
    mkToggle(aim, "Silent Aim", function() return C.silent.enabled end,
        function(v) C.silent.enabled = v end)
    mkCycle(aim, "Silent FOV", { 80, 140, 260, 400, 600 }, function() return C.silent.fov end,
        function(v) C.silent.fov = v end)
    mkCycle(aim, "Silent chance", { 25, 50, 75, 100 }, function() return C.silent.chance end,
        function(v) C.silent.chance = v end)
    mkToggle(aim, "Fire Assist", function() return C.fireassist.enabled end,
        function(v) C.fireassist.enabled = v end)
    mkKeybind(aim, "FA key", function() return C.fireassist.key end,
        function(v) C.fireassist.key = v end)
    mkCycle(aim, "FA fov", { 60, 90, 130, 200 }, function() return C.fireassist.fov end,
        function(v) C.fireassist.fov = v end)

    -- VIS 页
    local vis = page("VIS")
    mkToggle(vis, "Player ESP", function() return C.esp.enabled end, function(v) C.esp.enabled = v end)
    mkToggle(vis, "Box", function() return C.esp.box end, function(v) C.esp.box = v end)
    mkToggle(vis, "Name", function() return C.esp.name end, function(v) C.esp.name = v end)
    mkToggle(vis, "Health", function() return C.esp.health end, function(v) C.esp.health = v end)
    mkToggle(vis, "Distance", function() return C.esp.distance end, function(v) C.esp.distance = v end)
    mkCycle(vis, "Max dist", { 300, 600, 1200, 2500 }, function() return C.esp.maxdist end,
        function(v) C.esp.maxdist = v end)

    -- WPN 页
    local wpn = page("WPN")
    mkToggle(wpn, "Item Chams", function() return C.wv.chams end, function(v) C.wv.chams = v end)
    mkCycle(wpn, "Transparency", { 0.2, 0.35, 0.5, 0.65, 0.8, 0.95 }, function()
        return C.wv.transparency
    end, function(v) C.wv.transparency = v end)
    mkCycle(wpn, "Material", { "Original", "Glass", "ForceField", "Neon", "SmoothPlastic" },
        function() return C.wv.material end,
        function(v) C.wv.material = v end)
    mkToggle(wpn, "Hide muzzle", function() return C.wv.nomuzzle end, function(v) C.wv.nomuzzle = v end)
    mkToggle(wpn, "Tracers", function() return C.wv.tracers end, function(v) C.wv.tracers = v end)
    mkButton(wpn, "关闭菜单", function() Menu.frame.Visible = false; Menu.open = false end)

    return gui
end

--=========================  主 循 环  =========================--
local conns = {}
local function push(c) conns[#conns + 1] = c return c end

local function start()
    preloadUtility()
    buildMenu()
    if OreoLite_buildTouch then safe(OreoLite_buildTouch) end

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            Menu.open = not Menu.open
            if Menu.frame then Menu.frame.Visible = Menu.open end
        end
    end)

    push(RunService.RenderStepped:Connect(function(dt)
        updateFovCircle(C.aimbot)
        safe(Aimbot.step, dt)
        safe(FA.step, dt)
        safe(Silent.step)
        safe(ESP.step)
        safe(WV.step)
        safe(Tracers.step, dt)
    end))
end

local API = {}
API.Version = VERSION
API.Config = C
API.Unload = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    C.silent.enabled = false
    C.aimbot.enabled = false
    C.fireassist.enabled = false
    C.esp.enabled = false
    C.wv.chams = false
    pcall(function() ESP.clear() end)
    pcall(function() if WV.model then restore(WV.model) end end)
    pcall(function() if fovCircle then fovCircle:Remove() end end)
    pcall(function() if Menu.gui then Menu.gui:Destroy() end end)
    pcall(function()
        local g = getgenv().OreoLiteTouchGui
        if g then g:Destroy() end
        getgenv().OreoLiteTouchGui = nil
    end)
    pcall(function() if ESP.fallbackGui then ESP.fallbackGui:Destroy() end end)
    getgenv().OreoLite = nil
end
API.Set = function(section, key, value)
    if C[section] then C[section][key] = value end
end
getgenv().OreoLite = API

--=========================  触 屏 控 制（手机）  =========================--
local Touch = { gui = nil }

local function mkTouchButton(parent, text, size, pos, color, onDown, onUp)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, size, 0, size)
    b.Position = pos
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.45
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.AutoButtonColor = false
    b.Active = true
    b.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = b
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if onDown then safe(onDown) end
        end
    end)
    b.InputEnded:Connect(function()
        if onUp then safe(onUp) end
    end)
    return b
end

function OreoLite_buildTouch()
    if not IS_MOBILE then return end
    local parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "OreoLiteTouch"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 998
    gui.Parent = parent
    Touch.gui = gui
    getgenv().OreoLiteTouchGui = gui

    mkTouchButton(gui, "≡", 44, UDim2.new(0, 10, 0, 120), Color3.fromRGB(38, 42, 54), function()
        Menu.open = not Menu.open
        if Menu.frame then Menu.frame.Visible = Menu.open end
    end)

    mkTouchButton(gui, "AIM", 62, UDim2.new(1, -84, 0.5, 48), Color3.fromRGB(58, 118, 205), function()
        C.aimbot.enabled = true
        C.aimbot.touchHeld = true
    end, function()
        C.aimbot.touchHeld = false
    end)

    mkTouchButton(gui, "FA", 62, UDim2.new(1, -84, 0.5, 120), Color3.fromRGB(200, 116, 58), function()
        C.fireassist.enabled = true
        C.fireassist.touchHeld = true
    end, function()
        C.fireassist.touchHeld = false
    end)

    mkTouchButton(gui, "SIL", 48, UDim2.new(1, -70, 0.5, -40), Color3.fromRGB(150, 70, 160), function()
        C.silent.enabled = not C.silent.enabled
    end)
end

--=========================  E S P  ·  ScreenGui 回退  =========================--
local FB = { entries = {} }

ESP.fallbackStep = function()
    local cfg = C.esp
    local parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
    if not FB.gui then
        local gui = Instance.new("ScreenGui")
        gui.Name = "OreoLiteESP"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 997
        gui.IgnoreGuiInset = true
        gui.Parent = parent
        FB.gui = gui
        ESP.fallbackGui = gui
    end
    FB.gui.Enabled = cfg.enabled and true or false
    if not cfg.enabled then return end

    local c = cam()
    if not c then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeamMate(plr, nil) then
            local part, char = partOf(plr, "Head")
            if part and char then
                local pos, onScreen = c:WorldToViewportPoint(part.Position)
                local dist = (c.CFrame.Position - part.Position).Magnitude
                local e = FB.entries[plr]
                if not e then
                    local box = Instance.new("Frame")
                    box.BackgroundTransparency = 1
                    box.BorderSizePixel = 0
                    box.Parent = FB.gui
                    local stroke = Instance.new("UIStroke")
                    stroke.Thickness = 1
                    stroke.Color = cfg.color
                    stroke.Parent = box
                    local label = Instance.new("TextLabel")
                    label.BackgroundTransparency = 1
                    label.TextColor3 = cfg.color
                    label.Font = Enum.Font.GothamMedium
                    label.TextSize = 13
                    label.Parent = FB.gui
                    e = { box = box, stroke = stroke, label = label }
                    FB.entries[plr] = e
                end
                if onScreen and dist <= cfg.maxdist then
                    local hrp = char:FindFirstChild("HumanoidRootPart") or part
                    local topP = c:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                    local botP = c:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local top = math.min(topP.Y, botP.Y)
                    local bot = math.max(topP.Y, botP.Y)
                    local h = math.max(bot - top, 1)
                    local w = h * 0.55
                    e.box.Visible = cfg.box
                    e.box.Position = UDim2.new(0, math.floor(pos.X - w / 2), 0, math.floor(top))
                    e.box.Size = UDim2.new(0, math.floor(w), 0, math.floor(h))
                    e.stroke.Color = cfg.color
                    e.label.Visible = cfg.name or cfg.distance
                    e.label.Text = (cfg.name and (plr.DisplayName or plr.Name) or "")
                        .. (cfg.distance and string.format("  %dm", math.floor(dist)) or "")
                    e.label.Position = UDim2.new(0, math.floor(pos.X - 80), 0, math.floor(top) - 20)
                    e.label.Size = UDim2.new(0, 160, 0, 16)
                else
                    e.box.Visible = false
                    e.label.Visible = false
                end
            end
        end
    end
end

start()
print(string.format("[OREO LITE] loaded v%s  |  RightShift = menu", VERSION))
