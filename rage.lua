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

local SCRIPT_VER = "9"   -- 状态栏左上角会显示，确认加载到的是不是新版

local CFG = {
    tpRange   = 1.0,     -- 贴到敌人身上的距离（米）
    tpRate    = 0.12,    -- TP 刷新间隔
    aimPart   = "HitboxHead",
    rageDelay = 0.03,    -- ragebot 每次发包间隔（越接近每帧越准）
    maxDist   = 1200,
    tpMaxDist = 1000,    -- 传送距离上限（studs）
    repRoot   = true,    -- 挂物理复制根（真穿墙）
    repRootMaxDist = 200,-- 穿墙/desync 的最大距离
    repRootHoldDisp = 80,  -- 复制根挂多久再摘（毫秒）
    flashTP   = false,   -- 闪身：先过去再打。默认关，之前它会把人送到地图外
    flashRange = 150,    -- 闪身最大距离
    teleportReach = 1.0, -- 站位到目标的水平距离
    attackHeight  = 1.75,-- 包的起点高度（腰高）
    bone      = true,    -- AIM 优先打头，被挡则打身体
    -- 三个键的位置：X = 距右边缘像素，Y = 相对屏幕垂直中心
    teamFilter = true,   -- true = 不打队友 / false = 连队友一起打
    allyIds    = {},     -- 手动标记为队友的 UserId
    _cfgVer    = 0,      -- 配置结构版本，用来做迁移
    esp        = true,   -- ESP 透视
    wallbangMode = "desync", -- desync=闪过去打(能中但像TP) / stand=原地不发位移(真穿墙,靠服务端信 part)
    autoFire   = false,  -- 自动开火（无按钮，保留配置）
    fireWindow = 70,     -- 准星多少像素内有目标才开火
    fireX = 12, fireY = -168, fireSize = 92,
    silentOn   = false,  -- 静默：视角不动，服务端按我方视角判定
    spreadOn   = false,  -- 无扩散：把武器的 spread 字段清零
    spreadX = 12, spreadY = -84, spreadSize = 64,
    silentX = 12, silentY = 0,   silentSize = 64,
    teamX = 26,  teamY = -228, teamSize = 84,
    tpX   = 26,  tpY   = -112, tpSize   = 84,
    aimX  = 26,  aimY  = 0,    aimSize  = 92,
    rageX = 26,  rageY = 118,  rageSize = 92,
}

local RAGE_CFG_FILE = "RivalsRageCfg.json"

-- 轻量诊断：只往文件写日志，不 hook、不改游戏，出问题能查到卡在哪一步
local DBG = {}
local function dbg(msg)
    DBG[#DBG + 1] = os.date("%H:%M:%S") .. "  " .. tostring(msg)
    if #DBG > 300 then table.remove(DBG, 1) end
end
task.spawn(function()
    while task.wait(2) do
        local text = table.concat(DBG, "\n")
        pcall(function() if writefile then writefile("rage_debug.txt", text) end end)
        pcall(function() if writefile then writefile("/sdcard/Download/DSH-Go/rage_debug.txt", text) end end)
    end
end)
local HttpService = game:GetService("HttpService")

local function saveCfg()
    pcall(function()
        if writefile then
            writefile(RAGE_CFG_FILE, HttpService:JSONEncode(CFG))
        end
    end)
end

local function loadCfg()

-- 旧存档会把新版默认值盖回去（比如 tpMaxDist=120、FIRE 键被挤到屏幕外），
-- 这里按版本号做一次迁移，只做一次。
local CFG_VER = 9
do
    local ver = tonumber(CFG._cfgVer) or 0
    if ver < CFG_VER then
        CFG.tpMaxDist = 1000
        CFG.repRoot = true
        CFG.repRootMaxDist = 200
        CFG.esp = true
        CFG.wallbangMode = "desync"
        CFG.rageDelay = 0.03
        CFG.repRootHoldDisp = 80
        CFG.flashTP = false
        CFG.fireX,  CFG.fireY,  CFG.fireSize  = 12, -168, 92
        CFG.silentX, CFG.silentY, CFG.silentSize = 12, -84, 64
        CFG.spreadX, CFG.spreadY, CFG.spreadSize = 12, 0, 64
        CFG.teamX,  CFG.teamY,  CFG.teamSize  = 26, -228, 84
        CFG.tpX,    CFG.tpY,    CFG.tpSize    = 26, -114, 84
        CFG.aimX,   CFG.aimY,   CFG.aimSize   = 26, 0, 92
        CFG.rageX,  CFG.rageY,  CFG.rageSize  = 26, 114, 92
        CFG._cfgVer = CFG_VER
        saveCfg()
    end
end
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

-- FighterController 实际在 PlayerScripts.Controllers 下（不是 Modules），
-- 之前的搜索路径漏掉了这一层，所以永远返回 nil、RAGE 一个包都没发出去过。
local moduleCache = {}
local function findModule(name)
    if moduleCache[name] then return moduleCache[name] end
    local ps = LP:FindFirstChild("PlayerScripts")

    -- 1) 常见直接路径
    local direct = {
        ps and ps:FindFirstChild("Controllers") and ps.Controllers:FindFirstChild(name),
        ps and ps:FindFirstChild("Modules") and ps.Modules:FindFirstChild(name),
        RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild(name),
    }
    for _, m in ipairs(direct) do
        if m and m:IsA("ModuleScript") then
            moduleCache[name] = m
            return m
        end
    end

    -- 2) 全量兜底搜索
    for _, root in ipairs({ ps, RS }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ModuleScript") and d.Name == name then
                    moduleCache[name] = d
                    return d
                end
            end
        end
    end
    return nil
end

-- ToEnum 的返回值 print 出来是空（控制字符），保险起见退化去查 EnumLibrary._to_enum
local function toEnum(name)
    local v
    pcall(function() v = RIVALS.enums:ToEnum(name) end)
    if v == nil or v == "" then
        pcall(function()
            local tbl = RIVALS.enums and RIVALS.enums._to_enum
            if type(tbl) == "table" then v = tbl[name] end
        end)
    end
    return v
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
CFG.allyIds = CFG.allyIds or {}   -- 手动标记的队友：[tostring(UserId)] = true


local function isAlly(p)
    if p == LP then return true end
    if CFG.teamFilter == false then return false end   -- 识别关了：谁都打
    if CFG.allyIds[tostring(p.UserId)] then return true end

    -- 只信 Team 对象和属性。
    -- 之前还比了 TeamColor —— FFA 里所有人的 TeamColor 都是默认白色、Neutral 也不是 true，
    -- 结果整个房间都被判成队友，nearestEnemy 永远返回 nil。
    if p.Team ~= nil and LP.Team ~= nil then
        if p.Team == LP.Team then return true end
        if p.Team.Name == LP.Team.Name then return true end
    end
    local pt, lt = p:GetAttribute("TeamID"), LP:GetAttribute("TeamID")
    if pt ~= nil and lt ~= nil then return pt == lt end
    local a, b = p:GetAttribute("Team"), LP:GetAttribute("Team")
    if a ~= nil and b ~= nil and a == b then return true end
    local na, nb = p:GetAttribute("TeamName"), LP:GetAttribute("TeamName")
    if type(na) == "string" and na ~= "" and na == nb then return true end
    local pa, pb = p:GetAttribute("PartyId"), LP:GetAttribute("PartyId")
    if pa ~= nil and pb ~= nil and pa == pb then return true end
    return false
end

-- 找最近的一个玩家，不管队伍（用来手动标记队友）
local function nearestPlayerAny(maxD)
    maxD = maxD or CFG.maxDist
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local hum, ch = humOf(p)
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local d = (hrp.Position - root.Position).Magnitude
                if d <= maxD and d < bd then bd = d; best = p end
            end
        end
    end
    return best
end

-- 给面板/状态栏用：看看自己到底有没有队伍信息
local function teamInfo()
    local t = LP.Team
    local nm = t and t.Name or tostring(LP:GetAttribute("Team") or LP:GetAttribute("TeamName") or "无")
    return tostring(nm)
end

getgenv().RageLiteAlly = function(userId, on)
    if on == false then
        CFG.allyIds[tostring(userId)] = nil
    else
        CFG.allyIds[tostring(userId)] = true
    end
    saveCfg()
end

-- 大厅里 TeamID / EnvironmentID 都是空串，只有进了对局才有值。
-- 大厅里跑 RAGE 会把角色 desync 到大厅边界外，而且拉不回来。
local function inMatch()
    local env  = LP:GetAttribute("EnvironmentID")
    local team = LP:GetAttribute("TeamID")
    return (type(env) == "string" and env ~= "") or (type(team) == "string" and team ~= "")
end

local function nearestEnemy(maxD, farthest)
    maxD = maxD or CFG.maxDist
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, (farthest and -1 or math.huge)
    local seen, skipped = 0, 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            seen = seen + 1
            local hum, ch = humOf(p)
            local ally = isAlly(p)
            if ally then skipped = skipped + 1 end
            if hum and not ally then
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d <= maxD then
                        if farthest then
                            if d > bd then bd = d; best = p end
                        elseif d < bd then
                            bd = d; best = p
                        end
                    end
                end
            end
        end
    end
    return best
end

--═══════════ TP ═══════════
local tpHold = false
local tpStatus = "待命"

local function doTP()
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local p = nearestEnemy(CFG.tpMaxDist, true)   -- TP 优先挑最远的那个
    if not p then
        if nearestEnemy(CFG.maxDist) then
            tpStatus = string.format("目标超出 TP 距离（%d）", math.floor(CFG.tpMaxDist))
        end
        return false
    end
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
        if tpHold then
            if doTP() then tpStatus = "贴过去中" end
        else
            tpStatus = "待命"
        end
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
local repRootActive = false
local homeCF = nil
local rageBack   = true     -- 松手回原位

local function equippedItem()
    local ident
    pcall(function() if getthreadidentity then ident = getthreadidentity() end end)
    local ok, item = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 2) end
        local mod = findModule("FighterController")
        if not mod then return nil end
        local FC = require(mod)
        local fighter = FC and FC.LocalFighter
        if not fighter and FC and FC.GetFighter then
            fighter = FC:GetFighter(LP)
        end
        if not fighter then
            local CFmod = findModule("ClientFighter")
            if CFmod then
                local okCF, CF = pcall(require, CFmod)
                if okCF and type(CF) == "table" and CF.GetFighter then
                    fighter = CF:GetFighter(LP)
                end
            end
        end
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

-- 提升权限后写 CFrame（PivotTo 会被墙体碰撞拦，直接写 CFrame 不会）
local function setCF(inst, cf)
    if not inst then return false end
    local id
    if getthreadidentity and setthreadidentity then
        pcall(function() id = getthreadidentity() end)
        pcall(setthreadidentity, 8)
    end
    local ok = pcall(function() inst.CFrame = cf end)
    if id and setthreadidentity then pcall(setthreadidentity, id) end
    return ok
end

-- 穿墙的核心：把角色的「物理复制根」指到目标命中盒上。
-- 角色本身一步不动，但服务端算射线和距离时用的是这个根 —— 所以墙后的目标也能打到。
-- 名字用 PhysicsRepRootRef（新），失败再退回 PhysicsRepRootPart（旧）。
local function setRepRoot(root, part)
    if not root then return false end
    local hide = sethiddenproperty or set_hidden_property or set_hidden_prop
    local target = part or root
    local value = target
    local handle = getgenv and getgenv().InstanceHandle
    if type(handle) == "table" and type(handle.new) == "function" then
        local okH, made = pcall(handle.new, target)
        if okH and made ~= nil then value = made end
    end
    local id
    if getthreadidentity and setthreadidentity then
        pcall(function() id = getthreadidentity() end)
        pcall(setthreadidentity, 8)
    end
    local ok = false
    if type(hide) == "function" then
        ok = pcall(hide, root, "PhysicsRepRootRef", value)
        if not ok then ok = pcall(hide, root, "PhysicsRepRootPart", part) end
    end
    -- 执行器没有 sethiddenproperty 时，用 identity 8 直接赋值（RobloxScript 权限能写受保护属性）
    if not ok and setthreadidentity then
        local prev
        pcall(function() prev = getthreadidentity and getthreadidentity() end)
        pcall(setthreadidentity, 8)
        ok = pcall(function() root.PhysicsRepRootRef = value end)
        if not ok then ok = pcall(function() root.PhysicsRepRootPart = part end) end
        if prev then pcall(setthreadidentity, prev) end
    end
    if id and setthreadidentity then pcall(setthreadidentity, id) end
    return ok
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
    if not RIVALS.ready then
        rageStatus = "缺游戏模块"
        dbg("abort: 模块缺失")
        return false
    end
    local now = os.clock()
    if now < rageNext then return false end

    if not inMatch() then
        rageStatus = "大厅里不干活（没进对局）"
        return false
    end

    local p = nearestEnemy(CFG.maxDist)
    if not p then
        local total, allies = 0, 0
        for _, q in ipairs(Players:GetPlayers()) do
            if q ~= LP then
                total = total + 1
                if isAlly(q) then allies = allies + 1 end
            end
        end
        dbg(string.format("abort: 没有目标 其他人=%d 队友=%d", total, allies))
        return false
    end

    local _, ch = humOf(p)
    if not ch then return false end
    -- 开源实现打的是 Head，不是 HitboxHead
    local head = ch:FindFirstChild("Head")
    local root = ch:FindFirstChild("HumanoidRootPart")
    if not head or not root then rageStatus = "目标缺 Head" return false end

    local item = equippedItem()
    if not item then rageStatus = "拿不到武器" dbg("abort: equippedItem nil") return false end
    local objId = item.Get and item:Get("ObjectID")
    if not objId then rageStatus = "没有 ObjectID" dbg("abort: ObjectID nil") return false end

    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false end

    local myPos  = myRoot.Position
    local tPos   = root.Position
    local dist   = (tPos - myPos).Magnitude

    if CFG.wallbangMode ~= "stand" and dist > CFG.repRootMaxDist then
        rageStatus = string.format("太远(%.0f>%d)", dist, CFG.repRootMaxDist)
        return false
    end

    rageNext = now + math.max(CFG.rageDelay, 0.02)

    --════ desync：把身体在 Heartbeat 里挪到目标旁边，同一帧末尾立刻挪回来 ════
    -- 服务端看到的是目标旁边的位置，客户端一帧内就复原，物理不会乱，
    -- 也不会像 PhysicsRepRootRef 那样把人甩出地图。
    local angle  = math.random() * math.pi * 2
    local radius = math.random(30, 80) / 10
    local height = math.random(-10, 30) / 10
    local offset = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
    local standPos = tPos + offset
    if standPos.Y < 0 or standPos.Y > 200 then standPos = tPos + Vector3.new(0, 2, 2) end

    local desyncCF = CFrame.lookAt(standPos, head.Position) * CFrame.Angles(math.rad(180), 0, 0)

    local oldCF   = myRoot.CFrame
    local oldVel  = myRoot.Velocity
    local oldRot  = myRoot.RotVelocity

    local standMode = (CFG.wallbangMode == "stand")
    if standMode then
        -- 原地穿墙：人一步不动，只把包里的射线写成"从枪口指向目标头"。
        -- 服务端如果信 shot 里的 part 就直接判中；如果它自己重新算射线，那这发就丢。
        desyncCF = CFrame.lookAt(myRoot.Position + Vector3.new(0, 1.5, 0), head.Position)
        dbg(string.format("  stand模式：原地打 (%.0f,%.0f,%.0f) → %s 距离%.0f",
            myRoot.Position.X, myRoot.Position.Y, myRoot.Position.Z, p.Name, dist))
    end

    myRoot.CFrame = desyncCF
    -- 之前用 BindToRenderStep("__rage_restore") 恢复，30ms 发一次会同名覆盖，
    -- 被覆盖掉的那次永远不会恢复 → 人就留在天上。改成 delay(0) 下一帧无条件执行。
    if not standMode then
        task.delay(0.04, function()
            if not (myRoot and myRoot.Parent) then return end
            pcall(function()
                myRoot.CFrame = oldCF
                myRoot.Velocity = oldVel
                myRoot.RotVelocity = oldRot
                dbg("desync 已回原位")
            end)
        end)
    end

    --════ 包结构（照开源实现，和之前猜的不一样）════
    local aimCF = CFrame.lookAt(desyncCF.Position, head.Position)
    -- 提前量：按目标当前速度预判 ~60ms，打移动靶准很多
    local lead = Vector3.zero
    pcall(function()
        lead = root.AssemblyLinearVelocity * 0.06
        if lead.Magnitude > 25 then lead = lead.Unit * 25 end
    end)
    local aimedPos = head.Position + lead
        + Vector3.new((math.random()-0.5)*0.15, (math.random()-0.5)*0.15, (math.random()-0.5)*0.15)
    local objSpaceHeadOffset = head.CFrame:ToObjectSpace(CFrame.new(aimedPos))

    local C1, C0, C2, C3 = string.char(1), string.char(0), string.char(2), string.char(3)
    local cameradata = {}
    cameradata[C1] = {
        [C0] = RIVALS.util:EncodeCFrame(aimCF),
        [C1] = RIVALS.util:EncodeCFrame(head.CFrame),        -- 目标的 CFrame，不是 aim
        [C2] = head,
        [C3] = RIVALS.util:EncodeCFrame(objSpaceHeadOffset), -- 目标局部空间偏移
    }

    local enumVal = toEnum("StartShooting")
    local ok, err = pcall(function()
        RIVALS.use:FireServer(objId, enumVal, cameradata, nil)
    end)
    if not ok then
        dbg("  FireServer 抛错: " .. tostring(err))
    end
    dbg(string.format("  packet: objId=%s(%s,len=%d) enum=%s(%s,len=%d) item=%s",
        tostring(objId), typeof(objId), (type(objId)=="string" and #objId or 0),
        tostring(enumVal), typeof(enumVal), (type(enumVal)=="string" and #enumVal or 0),
        tostring(item and item.Name)))

    if ok then
        rageStatus = string.format("desync打 → %s (%.0f)", p.Name, dist)
        dbg(string.format("fire → %s dist=%.0f objId=%s part=Head desync=(%.0f,%.0f,%.0f)",
            p.Name, dist, tostring(objId), standPos.X, standPos.Y, standPos.Z))
        return true
    end
    rageStatus = "发包失败: " .. tostring(err)
    dbg("  FireServer 失败: " .. tostring(err))
    return false
end

-- RAGE = 完整 ragebot：挂复制根（穿墙）+ 自己连续开火
task.spawn(function()
    while true do
        if rageOn then
            rageFire()
            task.wait(CFG.rageDelay)
        else
            if repRootActive and LP.Character then
                local r0 = LP.Character:FindFirstChild("HumanoidRootPart")
                if r0 then setRepRoot(r0, nil) end
                repRootActive = false
            end
            -- 关掉之后如果人卡在空中/离安全点太远，直接拉回来
            local r0 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if r0 and safeCF then
                local d = (r0.Position - safeCF.Position).Magnitude
                local airborne = r0.Position.Y > safeCF.Position.Y + 15
                if d > 60 or airborne then
                    pcall(function()
                        r0.CFrame = safeCF
                        r0.Velocity = Vector3.zero
                        r0.RotVelocity = Vector3.zero
                    end)
                    dbg(string.format("关 RAGE：人卡在外面(%.0fm) 已拉回", d))
                end
            end
            rageStatus = "待命"
            task.wait(0.2)
        end
    end
end)

--═══════════ ESP 透视 ═══════════
-- 两层：Highlight 给角色本体描边（AlwaysOnTop，墙也挡不住 → 真透视）
--       2D 框 + 名字距离（辅助定位）
local espPool = {}
local highlights = {}

local function killHighlight(p)
    local h = highlights[p]
    if h then
        pcall(function() h:Destroy() end)
        highlights[p] = nil
    end
end

local function ensureHighlight(p, ch, isTarget)
    local h = highlights[p]
    if not h or h.Parent == nil then
        h = Instance.new("Highlight")
        h.Name = "RageLiteHL"
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.OutlineTransparency = 0
        h.FillTransparency = 0.55
        h.Parent = ch
        highlights[p] = h
    end
    h.Adornee = ch
    if isTarget then
        h.FillColor = Color3.fromRGB(255, 160, 40)    -- 当前 RAGE 目标
        h.OutlineColor = Color3.fromRGB(255, 220, 120)
    else
        h.FillColor = Color3.fromRGB(255, 40, 40)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
end

local function getEsp(p)
    local e = espPool[p]
    if e then return e end
    e = {}
    for i = 1, 4 do
        local f = Instance.new("Frame")
        f.BackgroundColor3 = Color3.fromRGB(90, 255, 140)
        f.BorderSizePixel = 0
        f.Visible = false
        f.ZIndex = 900
        f.Parent = gui
        e[i] = f
    end
    e.name = Instance.new("TextLabel")
    e.name.BackgroundTransparency = 1
    e.name.Font = Enum.Font.GothamBold
    e.name.TextSize = 12
    e.name.TextColor3 = Color3.fromRGB(120, 255, 160)
    e.name.TextStrokeTransparency = 0.3
    e.name.TextXAlignment = Enum.TextXAlignment.Center
    e.name.Visible = false
    e.name.ZIndex = 901
    e.name.Parent = gui
    espPool[p] = e
    return e
end

local function hideEsp(e)
    if not e then return end
    for i = 1, 4 do e[i].Visible = false end
    e.name.Visible = false
end

RunService.RenderStepped:Connect(function()
    if not CFG.esp then
        for _, e in pairs(espPool) do hideEsp(e) end
        for p in pairs(highlights) do killHighlight(p) end
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position

    for _, p in ipairs(Players:GetPlayers()) do
        local drawn = false
        if p ~= LP and not isAlly(p) and p.Character then
            local ch = p.Character
            local rageTarget = (rageOn and nearestEnemy(CFG.maxDist) == p)
            ensureHighlight(p, ch, rageTarget)
            local head = ch:FindFirstChild("Head")
            local hrp  = ch:FindFirstChild("HumanoidRootPart")
            local hum  = ch:FindFirstChildOfClass("Humanoid")
            if head and hrp and hum and hum.Health > 0 then
                local a, onA = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                local b, onB = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                if onA and onB then
                    local h = math.abs(b.Y - a.Y)
                    if h > 8 and h < 900 then
                        local w  = h * 0.55
                        local x0 = a.X - w / 2
                        local y0 = a.Y
                        local e = getEsp(p)
                        e[1].Visible = true; e[1].Position = UDim2.fromOffset(x0, y0);     e[1].Size = UDim2.fromOffset(w, 1)
                        e[2].Visible = true; e[2].Position = UDim2.fromOffset(x0, y0 + h); e[2].Size = UDim2.fromOffset(w, 1)
                        e[3].Visible = true; e[3].Position = UDim2.fromOffset(x0, y0);     e[3].Size = UDim2.fromOffset(1, h)
                        e[4].Visible = true; e[4].Position = UDim2.fromOffset(x0 + w, y0); e[4].Size = UDim2.fromOffset(1, h)
                        e.name.Visible = true
                        e.name.Text = string.format("%s  %dm", p.Name, math.floor((hrp.Position - camPos).Magnitude))
                        e.name.Size = UDim2.fromOffset(w + 90, 14)
                        e.name.Position = UDim2.fromOffset(x0 - 45, y0 - 16)
                        drawn = true
                    end
                end
            end
        end
        if not drawn then
            hideEsp(espPool[p])
            killHighlight(p)
        end
    end
end)

--═══════════ 掉图保护（desync 万一还是把物理带歪，这里兜底） ═══════════
-- 记最近一个"合理"的位置；一旦掉出去/被甩飞，直接把人拉回那儿，
-- 比固定 Y=50 靠谱（大厅、不同地图坐标系都不一样）。
local safeCF = nil

RunService.Heartbeat:Connect(function()
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local pos = root.Position
    if pos.X ~= pos.X then return end

    local ok = (pos.Y > -20 and pos.Y < 1200 and pos.Magnitude < 5000)
    if ok then
        safeCF = root.CFrame
    elseif safeCF then
        pcall(function()
            root.CFrame = safeCF
            root.Velocity = Vector3.zero
            root.RotVelocity = Vector3.zero
        end)
        dbg(string.format("掉图保护：从 (%.0f,%.0f,%.0f) 拉回安全点", pos.X, pos.Y, pos.Z))
    end
end)

--═══════════ 死亡自动关 RAGE ═══════════
local function watchDeath(ch)
    local hum = ch and ch:WaitForChild("Humanoid", 10)
    if hum then
        hum.Died:Connect(function()
            if rageOn then
                rageOn = false
                rageStatus = "死后自动关（避免连送）"
                dbg("RAGE 自动关闭：角色死亡")
                if btnRage then
                    btnRage.BackgroundTransparency = 0.72
                    btnRage.Text = "RAGE"
                end
            end
        end)
    end
end
if LP.Character then pcall(watchDeath, LP.Character) end
LP.CharacterAdded:Connect(function(ch) pcall(watchDeath, ch) end)

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

local function makeBtn(key, text, color, side)
    side = side or "right"
    local b = Instance.new("TextButton")
    if side == "left" then
        b.AnchorPoint = Vector2.new(0, 0.5)
        b.Position = UDim2.new(0, CFG[key .. "X"], 0.5, CFG[key .. "Y"])
    else
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -CFG[key .. "X"], 0.5, CFG[key .. "Y"])
    end
    b.Size = UDim2.fromOffset(CFG[key .. "Size"], CFG[key .. "Size"])
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

local btnTeam = makeBtn("team", "TEAM", Color3.fromRGB(80, 220, 120))
local btnTp   = makeBtn("tp",   "TP",   Color3.fromRGB(40, 210, 235))
local btnAim  = makeBtn("aim",  "AIM",  Color3.fromRGB(255, 70, 70))
local btnRage = makeBtn("rage", "RAGE", Color3.fromRGB(255, 175, 40))
local btnEsp = makeBtn("fire", "ESP", Color3.fromRGB(120, 255, 160), "left")
local btnSpread = makeBtn("spread", "SPREAD", Color3.fromRGB(120, 200, 255), "left")
local btnSilent = makeBtn("silent", "SILENT", Color3.fromRGB(200, 130, 255), "left")

local function applyLayout()
    local function set(btn, key, side)
        if not btn then return end
        btn.Size = UDim2.fromOffset(CFG[key .. "Size"], CFG[key .. "Size"])
        if side == "left" then
            btn.Position = UDim2.new(0, CFG[key .. "X"], 0.5, CFG[key .. "Y"])
        else
            btn.Position = UDim2.new(1, -CFG[key .. "X"], 0.5, CFG[key .. "Y"])
        end
    end
    set(btnTeam, "team")
    set(btnTp, "tp")
    set(btnAim, "aim")
    set(btnRage, "rage")
    set(btnEsp, "fire", "left")
    set(btnSpread, "spread", "left")
    set(btnSilent, "silent", "left")
end

local function paint(btn, on, base)
    btn.BackgroundTransparency = on and 0.22 or 0.72
    btn.Text = on and (base .. " ●") or base
end

-- TEAM：亮 = 排掉队友；暗（ALL）= 连队友一起打
local function paintTeam()
    if not btnTeam then return end
    btnTeam.BackgroundTransparency = CFG.teamFilter and 0.22 or 0.72
    btnTeam.Text = CFG.teamFilter and "TEAM" or "ALL"
end

--═══════════ 自动开火（准星贴人就替玩家扣扳机） ═══════════
local fireNext = 0
local fireStatus = "待命"

local function autoFireTick()
    if not RIVALS.ready then fireStatus = "缺游戏模块" return false end
    local now = os.clock()
    if now < fireNext then return false end

    local cam = workspace.CurrentCamera
    if not cam then return false end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

    -- RAGE 开着 = 复制根已经挂到目标身上，这时不看准星，直接打最近的那个
    local best, bestD = nil, CFG.fireWindow
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and not isAlly(p) then
            local hum, ch = humOf(p)
            if hum then
                local head, body = partsOf(ch)
                local part = head or body
                if part then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d < bestD then bestD = d; best = { p = p, part = part } end
                    end
                end
            end
        end
    end
    if not best then fireStatus = "准星附近没人" return false end

    local item = equippedItem()
    if not item then fireStatus = "拿不到武器" return false end
    local objId = item.Get and item:Get("ObjectID")
    if not objId then fireStatus = "武器没有 ObjectID" return false end

    -- 按武器自己的射速来，不刷包
    local cd = 0.12
    local info = item.Info
    if type(info) == "table" then
        local raw = info.FireCooldown or info.ShootCooldown or info.AttackCooldown
        if type(raw) == "number" and raw > 0 then cd = raw end
    end
    fireNext = now + math.max(cd, 0.05)

    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local origin = myRoot and myRoot.Position or cam.CFrame.Position
    local aim = CFrame.new(origin, best.part.Position)
    local shot = {
        [utf8.char(0)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(1)] = RIVALS.util:EncodeCFrame(aim),
        [utf8.char(2)] = best.part,
        [utf8.char(3)] = RIVALS.util:EncodeCFrame(CFrame.Angles(0, math.pi / 2, 0)),
    }
    local ok = pcall(function()
        RIVALS.use:FireServer(
            objId,
            toEnum("StartShooting"),
            { [utf8.char(1)] = shot, [utf8.char(2)] = true },
            nil
        )
    end)
    fireStatus = ok and ("开火 → " .. best.p.Name) or "发包失败"
    return ok
end

task.spawn(function()
    while true do
        if CFG.autoFire then
            autoFireTick()
            task.wait(0.03)
        else
            task.wait(0.12)
        end
    end
end)

--═══════════ 静默瞄准（视角不动，发包骗服务端） ═══════════
local lastYawAt = 0
local function sendYaw(pos)
    if not (RIVALS.cam and RIVALS.util and pos) then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local delta = pos - cam.CFrame.Position
    if delta.Magnitude < 0.8 then return end
    local now = os.clock()
    if now - lastYawAt < 0.02 then return end
    lastYawAt = now
    pcall(function()
        local cf = CFrame.lookAt(cam.CFrame.Position, pos)
        local _, yaw = cf:ToOrientation()
        RIVALS.cam:FireServer(RIVALS.util:EncodeCameraRotation(Vector2.new(0, yaw)), nil)
    end)
end

RunService:BindToRenderStep("RageLiteSilent", Enum.RenderPriority.Camera.Value + 2, function()
    if not CFG.silentOn then return end
    local p = nearestEnemy(CFG.maxDist)
    if not p then return end
    local _, ch = humOf(p)
    if not ch then return end
    local head, body = partsOf(ch)
    local part = head or body
    if part then sendYaw(part.Position) end
end)

--═══════════ 无扩散 ═══════════
-- 上一版每 0.2 秒对 6 个字段调一次 item:Set()，那个 Set 不是简单赋值，
-- 会触发武器重算/同步，把射速和弹道一起搞乱，所以打不中人。
-- 现在只在开关切换时动一次，只碰 Spread / AimSpread，直接改表，并在关掉时精确还原。
local spreadBackup = nil
local spreadState = "原值"

local function applySpread()
    local item = equippedItem()
    local info = item and item.Info
    if type(info) ~= "table" then
        spreadState = "拿不到武器 Info"
        return
    end
    -- 动态找：所有名字里带 spread / sway 的数值字段都清零（不同枪字段名不一样）
    local targets = {}
    for k, v in pairs(info) do
        if type(k) == "string" and type(v) == "number" then
            local lk = string.lower(k)
            if string.find(lk, "spread", 1, true) or string.find(lk, "sway", 1, true)
            or string.find(lk, "recoil", 1, true) then
                table.insert(targets, k)
            end
        end
    end
    if #targets == 0 then
        spreadState = "这把武器没有 spread 字段"
        return
    end
    if CFG.spreadOn then
        if spreadBackup == nil or spreadBackup.item ~= item then
            local bk = { item = item, vals = {} }
            for _, k in ipairs(targets) do bk.vals[k] = info[k] end
            spreadBackup = bk
        end
        for _, k in ipairs(targets) do info[k] = 0 end
        spreadState = "清零 " .. #targets .. " 项"
    else
        if spreadBackup and spreadBackup.item == item and type(spreadBackup.item.Info) == "table" then
            for k, v in pairs(spreadBackup.vals) do spreadBackup.item.Info[k] = v end
        end
        spreadBackup = nil
        spreadState = "原值"
    end
end

-- 换枪后重新套用（每把武器的 Info 是独立表）
task.spawn(function()
    local lastItem = nil
    while task.wait(0.5) do
        if CFG.spreadOn then
            local it = equippedItem()
            if it ~= lastItem then
                lastItem = it
                applySpread()
            end
        end
    end
end)

--═══════════ 两个开关按钮 ═══════════
btnEsp.MouseButton1Click:Connect(function()
    CFG.esp = not CFG.esp
    btnEsp.BackgroundTransparency = CFG.esp and 0.22 or 0.72
    btnEsp.Text = CFG.esp and "ESP ●" or "ESP"
    saveCfg()
end)
btnEsp.BackgroundTransparency = CFG.esp and 0.22 or 0.72
btnEsp.Text = CFG.esp and "ESP ●" or "ESP"

btnSilent.MouseButton1Click:Connect(function()
    CFG.silentOn = not CFG.silentOn
    btnSilent.BackgroundTransparency = CFG.silentOn and 0.22 or 0.72
    btnSilent.Text = CFG.silentOn and "SILENT ●" or "SILENT"
    saveCfg()
end)
btnSilent.BackgroundTransparency = CFG.silentOn and 0.22 or 0.72
btnSilent.Text = CFG.silentOn and "SILENT ●" or "SILENT"

-- 存档里是开着的，进游戏后也要真的套用一次（不然按钮亮着、状态却是"原值"）
task.delay(3, function()
    if CFG.spreadOn then applySpread() end
end)

btnSpread.MouseButton1Click:Connect(function()
    CFG.spreadOn = not CFG.spreadOn
    btnSpread.BackgroundTransparency = CFG.spreadOn and 0.22 or 0.72
    btnSpread.Text = CFG.spreadOn and "SPREAD ●" or "SPREAD"
    applySpread()
    saveCfg()
end)
btnSpread.BackgroundTransparency = CFG.spreadOn and 0.22 or 0.72
btnSpread.Text = CFG.spreadOn and "SPREAD ●" or "SPREAD"

local teamDownAt = 0
btnTeam.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        teamDownAt = os.clock()
    end
end)
btnTeam.MouseButton1Click:Connect(function()
    if os.clock() - teamDownAt > 0.6 then
        -- 长按：把最近的人手动记为队友
        local p = nearestPlayerAny()
        if p then
            CFG.allyIds[tostring(p.UserId)] = true
            saveCfg()
            rageStatus = "已把 " .. p.Name .. " 标为队友"
        end
    else
        CFG.teamFilter = not CFG.teamFilter
        paintTeam()
        saveCfg()
    end
end)
paintTeam()

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
        if repRootActive then
            local ch0 = LP.Character
            local r0 = ch0 and ch0:FindFirstChild("HumanoidRootPart")
            if r0 then setRepRoot(r0, nil) end
            repRootActive = false
        end
        -- 人没被移动过，不用回原位
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

local function makeButtonRow(parent, label, action, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = Color3.fromRGB(34, 40, 30)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.Text = "  " .. label
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextColor3 = Color3.fromRGB(255, 225, 120)
    b.LayoutOrder = order or 999
    b.ZIndex = 4002
    b.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(action)
        if not ok then warn("[RAGE] " .. tostring(err)) end
    end)
    return b
end

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

header("SILENT / SPREAD 键")
makeStepper(scroll, "SILENT 边距", "silentX", 6, 0, 400, nextOrd())
makeStepper(scroll, "SILENT 垂直", "silentY", 10, -700, 700, nextOrd())
makeStepper(scroll, "SILENT 大小", "silentSize", 6, 40, 160, nextOrd())
makeStepper(scroll, "SPREAD 边距", "spreadX", 6, 0, 400, nextOrd())
makeStepper(scroll, "SPREAD 垂直", "spreadY", 10, -700, 700, nextOrd())
makeStepper(scroll, "SPREAD 大小", "spreadSize", 6, 40, 160, nextOrd())
header("FIRE 键（自动开火）")
makeButtonRow(scroll, "打法：闪身 / 原地穿墙（点我切）", function()
    CFG.wallbangMode = (CFG.wallbangMode == "desync") and "stand" or "desync"
    saveCfg()
    rageStatus = CFG.wallbangMode == "stand" and "原地穿墙（人不动）" or "闪身（贴过去打）"
end, nextOrd())
makeButtonRow(scroll, "ESP：点我切换", function()
    CFG.esp = not CFG.esp
    btnEsp.BackgroundTransparency = CFG.esp and 0.22 or 0.72
    btnEsp.Text = CFG.esp and "ESP ●" or "ESP"
    saveCfg()
end, nextOrd())
makeStepper(scroll, "准星范围", "fireWindow", 10, 20, 300, nextOrd())
makeStepper(scroll, "左边距", "fireX", 6, 0, 400, nextOrd())
makeStepper(scroll, "垂直", "fireY", 10, -700, 700, nextOrd())
makeStepper(scroll, "大小", "fireSize", 6, 40, 160, nextOrd())
header("RAGE 键")
makeButtonRow(scroll, "穿墙开/关（默认关·会被拉走）", function()
    CFG.repRoot = not CFG.repRoot
    saveCfg()
    rageStatus = CFG.repRoot and "穿墙 开（目标 60 内才挂）" or "穿墙 关（只发包）"
end, nextOrd())
makeStepper(scroll, "穿墙最大距离", "repRootMaxDist", 10, 10, 500, nextOrd())
makeStepper(scroll, "穿墙挂载(毫秒)", "repRootHoldDisp", 20, 30, 600, nextOrd())
makeButtonRow(scroll, "闪身打/原地打（点我切）", function()
    CFG.flashTP = not CFG.flashTP
    saveCfg()
    rageStatus = CFG.flashTP and "闪身：先过去再打，打完回原位" or "原地：人不走，穿不动墙"
end, nextOrd())
header("TEAM 键（队友识别）")
makeStepper(scroll, "右边距", "teamX", 10, 0, 600, nextOrd())
makeStepper(scroll, "垂直",   "teamY", 10, -700, 700, nextOrd())
makeStepper(scroll, "大小",   "teamSize", 6, 50, 160, nextOrd())
header("TP 键")
makeStepper(scroll, "最大传送距离", "tpMaxDist", 100, 20, 99999, nextOrd())
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

--═══════════ 玩家列表（手动标队友） ═══════════
header("玩家 · 点一下切 队友/敌人")
local playerBox = Instance.new("Frame")
playerBox.Size = UDim2.new(1, 0, 0, 0)
playerBox.BackgroundTransparency = 1
playerBox.LayoutOrder = nextOrd()
playerBox.ZIndex = 4001
playerBox.Parent = scroll
pcall(function() playerBox.AutomaticSize = Enum.AutomaticSize.Y end)
local plLayout = Instance.new("UIListLayout")
plLayout.Padding = UDim.new(0, 2)
plLayout.SortOrder = Enum.SortOrder.LayoutOrder
plLayout.Parent = playerBox

function refreshPlayerList()
    if not playerBox then return end
    for _, ch in ipairs(playerBox:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            n = n + 1
            local ally = CFG.allyIds[tostring(p.UserId)] == true
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, 0, 0, 30)
            b.BackgroundColor3 = ally and Color3.fromRGB(36, 84, 48) or Color3.fromRGB(46, 34, 38)
            b.BorderSizePixel = 0
            b.Font = Enum.Font.Gotham
            b.TextSize = 12
            b.Text = "  " .. p.Name .. (ally and "   [队友]" or "   [敌人]")
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextColor3 = ally and Color3.fromRGB(140, 255, 170) or Color3.fromRGB(255, 150, 150)
            b.LayoutOrder = n
            b.ZIndex = 4002
            b.Parent = playerBox
            local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 5); cc.Parent = b
            b.MouseButton1Click:Connect(function()
                local key = tostring(p.UserId)
                if CFG.allyIds[key] then CFG.allyIds[key] = nil else CFG.allyIds[key] = true end
                saveCfg()
                refreshPlayerList()
            end)
        end
    end
    if n == 0 then
        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(1, 0, 0, 24)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Gotham
        lb.TextSize = 11
        lb.Text = "  房间里只有你自己"
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextColor3 = Color3.fromRGB(150, 150, 160)
        lb.Parent = playerBox
    end
end

task.spawn(function()
    while task.wait(1.5) do
        if layoutPanel and layoutPanel.Visible then pcall(refreshPlayerList) end
    end
end)

gear.MouseButton1Click:Connect(function()
    layoutPanel.Visible = not layoutPanel.Visible
    if layoutPanel.Visible then pcall(refreshPlayerList) end
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
        local hideFn = sethiddenproperty or set_hidden_property or set_hidden_prop
        local okTxt = (RIVALS.ready and "接口OK" or "接口缺")
            .. "/" .. (type(hideFn) == "function" and "穿墙OK" or "穿墙缺")
        local allies = 0
        if CFG.teamFilter then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and isAlly(p) then allies = allies + 1 end
            end
        end
        stat.Text = string.format(
            "  v" .. SCRIPT_VER .. "  TP %s AIM %s RAGE %s FIRE %s SIL %s SPL %s %s\n  %s · %s",
            tpHold and "●" or "○",
            aimOn and "●" or "○",
            rageOn and "●" or "○",
            CFG.esp and "●" or "○",
            CFG.silentOn and "●" or "○",
            (CFG.spreadOn and "●" or "○") .. "(" .. spreadState .. ")",
            (CFG.teamFilter and ("队友 " .. allies .. " [" .. teamInfo() .. "]") or "全打")
                .. " · 传送≤" .. math.floor(CFG.tpMaxDist),
            okTxt, tpHold and tpStatus
                or (CFG.autoFire and (fireStatus .. " | " .. rageStatus) or rageStatus))
    end
end)

getgenv().RageLiteUnload = function()
    rageOn, aimOn, tpHold = false, false, false
    pcall(function() gui:Destroy() end)
    pcall(function() RunService:UnbindFromRenderStep("RageLiteAim") end)
    getgenv().RageLiteUnload = nil
end

print("[RAGE LITE v" .. SCRIPT_VER .. "] 已加载")
