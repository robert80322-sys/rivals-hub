--[[
════════════════════════════════════════════════════════════
  KNIFE · 长按 1 秒背刺
    只在手里拿刀的时候有用。按住按钮 1 秒 → 自动：
      ① 站到目标背后（朝向和目标一致 = 背对目标）
      ② 把「视角朝向」按目标方向发给服务端（背刺判定看的就是这个）
      ③ 出刀
      ④ 回原位
    手机触屏，一个键。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/knife.lua"))()
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

-- 诊断日志（不 hook、不改游戏，只写文件）
local DBG = {}
local function dbg(msg)
    DBG[#DBG + 1] = os.date("%H:%M:%S") .. "  " .. tostring(msg)
    if #DBG > 200 then table.remove(DBG, 1) end
    pcall(function() if writefile then writefile("knife_debug.txt", table.concat(DBG, "\n")) end end)
end

local CFG = {
    holdSec    = 1.0,    -- 长按多久触发
    behindDist = 2.2,    -- 站到目标背后多远
    maxDist    = 60,     -- 目标最远距离
    swings     = 1,      -- 只出一次重击（右键），不再连砍
    backHome   = true,   -- 砍完回原位
}

--═══════════ 游戏接口 ═══════════
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
                if d:IsA("ModuleScript") and d.Name == name then
                    moduleCache[name] = d
                    return d
                end
            end
        end
    end
    return nil
end

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

local function equippedItem()
    local ident
    pcall(function() if getthreadidentity then ident = getthreadidentity() end end)
    local ok, item = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 2) end
        local mod = findModule("FighterController")
        if not mod then return nil end
        local FC = require(mod)
        local f = FC and FC.LocalFighter
        if not f and FC and FC.GetFighter then f = FC:GetFighter(LP) end
        if not f then return nil end
        if f.EquippedItem then return f.EquippedItem end
        if f.Items then local _, it = next(f.Items) return it end
        return nil
    end)
    if setthreadidentity and ident then pcall(setthreadidentity, ident) end
    return ok and item or nil
end

local function itemName(item)
    if not item then return "" end
    local n
    pcall(function() n = item:Get("Name") end)
    if not n then pcall(function() n = item.Name end) end
    if not n and item.ViewModel then pcall(function() n = item.ViewModel.Name end) end
    return tostring(n or "")
end

local function isKnife(item)
    local n = string.lower(itemName(item))
    return string.find(n, "knife", 1, true) ~= nil
        or string.find(n, "dagger", 1, true) ~= nil
        or string.find(n, "blade", 1, true) ~= nil
end

local function humOf(p)
    local ch = p.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return hum, ch
end

local function nearestEnemy(maxD)
    local ch0 = LP.Character
    local root = ch0 and ch0:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, maxD or CFG.maxDist
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local hum, ch = humOf(p)
            if hum then
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d < bd then bd = d; best = p end
                end
            end
        end
    end
    return best
end

--═══════════ 背刺 ═══════════
local busy = false
local status = "待命"

local function backstab()
    dbg("=== 触发背刺 ===")
    if busy then dbg("  busy=true，跳过") return end
    if not RIVALS.ready then
        status = "缺游戏模块"
        dbg("  缺模块 use=" .. tostring(RIVALS.use ~= nil)
            .. " util=" .. tostring(RIVALS.util ~= nil)
            .. " enums=" .. tostring(RIVALS.enums ~= nil))
        return
    end

    local item = equippedItem()
    if not item then
        status = "拿不到武器"
        dbg("  equippedItem=nil（FighterController.LocalFighter 没取到）")
        return
    end
    dbg("  武器=" .. itemName(item) .. "  isKnife=" .. tostring(isKnife(item)))
    if not isKnife(item) then
        status = "手里不是刀：" .. itemName(item)
        return
    end

    local p = nearestEnemy(CFG.maxDist)
    if not p then
        status = "附近没人"
        dbg(string.format("  附近没人（范围 %d）", CFG.maxDist))
        return
    end

    local _, ch = humOf(p)
    if not ch then return end
    local tHRP = ch:FindFirstChild("HumanoidRootPart")
    local head = ch:FindFirstChild("Head")
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (tHRP and head and myRoot) then return end

    local objId = item.Get and item:Get("ObjectID")
    if not objId then status = "没有 ObjectID" dbg("  ObjectID=nil") return end
    dbg(string.format("  目标=%s 距离=%.0f objId=%s(%s)",
        p.Name, (tHRP.Position - myRoot.Position).Magnitude, tostring(objId), typeof(objId)))

    busy = true
    status = "重击背刺 " .. p.Name

    local homeCF = myRoot.CFrame
    local tLook = tHRP.CFrame.LookVector      -- 目标面朝的方向
    -- 站到目标背后：沿目标朝向的反方向退 behindDist
    local behindPos = tHRP.Position - tLook * CFG.behindDist + Vector3.new(0, 1.5, 0)
    -- 身体朝向和目标一致（= 从背后贴住他）
    local standCF = CFrame.lookAt(behindPos, behindPos + tLook)

    -- ① 先把"视角朝向"按目标方向发给服务端：背刺判定看的就是服务端最后收到的视角
    pcall(function()
        local _, yaw = standCF:ToOrientation()
        RIVALS.cam:FireServer(RIVALS.util:EncodeCameraRotation(Vector2.new(0, yaw)), nil)
    end)

    -- ② 闪到背后
    setCF(myRoot, standCF)

    -- ③ 出刀：一次重击（右键）。刀的 "StartAiming" 就是重击入口，
    --    轻击走的是 StartShooting，别搞混。
    local C1, C0, C2, C3 = string.char(1), string.char(0), string.char(2), string.char(3)
    local aimCF = CFrame.lookAt(behindPos, head.Position)
    local shot = {
        [C0] = RIVALS.util:EncodeCFrame(aimCF),
        [C1] = RIVALS.util:EncodeCFrame(head.CFrame),
        [C2] = head,
        [C3] = RIVALS.util:EncodeCFrame(CFrame.Angles(0, math.pi / 2, 0)),
    }
    local okSwing, errSwing = pcall(function()
        RIVALS.use:FireServer(
            objId,
            RIVALS.enums:ToEnum("StartAiming"),
            { [C1] = shot },
            nil
        )
    end)
    dbg("  重击发包结果 ok=" .. tostring(okSwing) .. " " .. tostring(errSwing))
    if not okSwing then status = "重击失败：" .. tostring(errSwing) end

    -- 重击有 ~1.25s 冷却，出完刀停留一小会儿让包发出去再回原位
    task.wait(0.12)

    dbg("  已回原位")
    -- ④ 回原位
    if CFG.backHome and LP.Character then
        local r = LP.Character:FindFirstChild("HumanoidRootPart")
        if r then
            pcall(function()
                r.CFrame = homeCF
                r.Velocity = Vector3.zero
            end)
        end
    end

    busy = false
end

--═══════════ UI：一个键，长按 1 秒 ═══════════
pcall(function()
    local host = (gethui and gethui()) or game:GetService("CoreGui")
    for _, v in ipairs(host:GetChildren()) do
        if v.Name == "KnifeUI" then v:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "KnifeUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483000
local okP = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not okP then gui.Parent = LP:WaitForChild("PlayerGui") end

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(96, 96)
btn.AnchorPoint = Vector2.new(1, 0.5)
btn.Position = UDim2.new(1, -26, 0.5, 60)
btn.BackgroundColor3 = Color3.fromRGB(220, 70, 90)
btn.BackgroundTransparency = 0.72
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.TextSize = 13
btn.Text = "刀\n背刺"
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.ZIndex = 3000
btn.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = btn
    local s2 = Instance.new("UIStroke"); s2.Color = Color3.fromRGB(255, 120, 140); s2.Transparency = 0.45; s2.Parent = btn
end

local stat = Instance.new("TextLabel")
stat.Size = UDim2.fromOffset(230, 40)
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
stat.Text = "  按住 1 秒：重击背刺"
stat.ZIndex = 3000
stat.Parent = gui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = stat
end

local pressedAt = 0     -- 0 = 没按着
local fired = false

btn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
        pressedAt = os.clock()
        fired = false
        btn.BackgroundTransparency = 0.42
        btn.Text = "按…"
        dbg("按下开始计时")
        task.spawn(function()
            task.wait(CFG.holdSec)
            if pressedAt > 0 and not fired and (os.clock() - pressedAt) >= CFG.holdSec - 0.06 then
                fired = true
                dbg("长按达成 → 执行")
                btn.Text = "放!"
                backstab()
                btn.Text = "刀\n背刺"
            else
                dbg(string.format("长按没成 按住%.2fs（可能中途松手/被取消）", os.clock() - pressedAt))
            end
        end)
    end
end)

btn.InputEnded:Connect(function()
    if pressedAt > 0 then dbg(string.format("松开 共%.2fs", os.clock() - pressedAt)) end
    pressedAt = 0
    btn.BackgroundTransparency = 0.72
    btn.Text = "刀\n背刺"
end)

task.spawn(function()
    while true do
        task.wait(0.3)
        local item = equippedItem()
        local knifeOK = item and isKnife(item)
        stat.Text = string.format("  %s\n  %s", busy and "背刺中…" or status,
            knifeOK and ("刀在手：" .. itemName(item)) or "手里不是刀")
    end
end)

getgenv().KnifeUnload = function()
    pcall(function() gui:Destroy() end)
    getgenv().KnifeUnload = nil
end

print("[KNIFE] 已加载 · 长按 1 秒：闪到背后出一次重击")
