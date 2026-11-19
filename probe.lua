--[[
════════════════════════════════════════════════════════════
  PROBE · 抓 Rivals 真实的开火包
  不是外挂，是量具：装上它，正常开一枪，控制台会把游戏
  自己发出去的 UseItem 包原样打出来 —— 我们已经猜了三版
  格式都不对，这次直接看真的。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/probe.lua"))()

  步骤：
    1. 执行本脚本（进对局之后）
    2. 随便开一枪
    3. 把控制台里 "真实开火包" 那几段整段发出来
════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer

local LOG = {}
local lastFlush = 0
local function flush(force)
    local now = os.clock()
    if not force and now - lastFlush < 1 then return end
    lastFlush = now
    local text = table.concat(LOG, "\n")
    pcall(function() if writefile then writefile("probe_out.txt", text) end end)
    pcall(function() if writefile then writefile("/sdcard/Download/DSH-Go/probe_out.txt", text) end end)
end
local function line(msg)
    local m = "[PROBE] " .. tostring(msg)
    table.insert(LOG, m)
    print(m)
    flush(false)
end

--────────── 0. 环境 ──────────
line("game.PlaceId = " .. tostring(game.PlaceId) .. "  jobId = " .. tostring(game.JobId))

local rem = RS:FindFirstChild("Remotes")
local rep = rem and rem:FindFirstChild("Replication")
local fighter = rep and rep:FindFirstChild("Fighter")
local useItem = fighter and fighter:FindFirstChild("UseItem")

if not useItem then
    line("❌ 找不到 Remotes.Replication.Fighter.UseItem，路径变了")
    return
end
line("✅ UseItem = " .. useItem:GetFullName() .. " (" .. useItem.ClassName .. ")")

local mods = RS:FindFirstChild("Modules")
local utility, enumLib
if mods then
    local u = mods:FindFirstChild("Utility")
    local e = mods:FindFirstChild("EnumLibrary")
    if u then pcall(function() utility = require(u) end) end
    if e then pcall(function() enumLib = require(e) end) end
end
line("Utility = " .. tostring(utility ~= nil) .. "   EnumLibrary = " .. tostring(enumLib ~= nil))
if utility then
    line("  Utility:EncodeCFrame = " .. tostring(type(utility.EncodeCFrame)))
    line("  Utility:EncodeCameraRotation = " .. tostring(type(utility.EncodeCameraRotation)))
    if type(utility.EncodeCFrame) == "function" then
        local ok, enc = pcall(function() return utility:EncodeCFrame(CFrame.new(1, 2, 3)) end)
        line("  编码一个 CFrame(1,2,3) 得到: " .. tostring(ok) .. " → " .. tostring(enc))
        if ok and type(enc) == "table" then
            for k, v in pairs(enc) do
                line("     key=" .. tostring(k) .. " (" .. typeof(k) .. ") value=" .. tostring(v))
            end
        end
    end
end
if enumLib then
    line("  ToEnum = " .. tostring(type(enumLib.ToEnum)))
    local ok, v = pcall(function() return enumLib:ToEnum("StartShooting") end)
    line("  ToEnum('StartShooting') = " .. tostring(ok) .. " → " .. tostring(v))
end

--────────── 1. 我们的武器对象能不能拿到 ──────────
local function findModule(name)
    local ps = LP:FindFirstChild("PlayerScripts")
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

local FCmod = findModule("FighterController")
line("FighterController 模块 = " .. tostring(FCmod ~= nil))
if FCmod then
    local ident
    pcall(function() if getthreadidentity then ident = getthreadidentity() end end)
    pcall(function()
        if setthreadidentity then setthreadidentity(2) end
        local FC = require(FCmod)
        local f = FC and FC:GetFighter(LP)
        line("  GetFighter = " .. tostring(f ~= nil))
        if f then
            line("  EquippedItem = " .. tostring(f.EquippedItem))
            local item = f.EquippedItem
            if item then
                local ok, id = pcall(function() return item:Get("ObjectID") end)
                line("  item:Get('ObjectID') = " .. tostring(ok) .. " → " .. tostring(id) .. " (" .. typeof(id) .. ")")
                local ok2, nm = pcall(function() return item:Get("Name") end)
                line("  item:Get('Name') = " .. tostring(nm))
                local ok3, info = pcall(function() return item.Info end)
                if ok3 and type(info) == "table" then
                    local keys = {}
                    for k in pairs(info) do table.insert(keys, tostring(k)) end
                    table.sort(keys)
                    line("  Info 字段: " .. table.concat(keys, ", "))
                end
            end
        end
    end)
    if setthreadidentity and ident then pcall(setthreadidentity, ident) end
end

--────────── 2. 抓真实包 ──────────
local function bytesOf(s)
    local t = {}
    for i = 1, #s do t[#t + 1] = string.byte(s, i) end
    return table.concat(t, ",")
end

local function dump(v, indent, depth)
    indent = indent or "    "
    depth = depth or 0
    if depth >= 3 then line(indent .. "...太深，停"); return end
    if type(v) ~= "table" then
        line(indent .. "= " .. typeof(v) .. " : " .. tostring(v))
        return
    end
    local n = 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 24 then line(indent .. "...还有更多，略"); break end
        local ks
        if type(k) == "string" then
            ks = string.format('str("%s" bytes=%s)', k, bytesOf(k))
            if #k == 1 then ks = string.format("byte %d", string.byte(k)) end
            ks = ks .. " (" .. #k .. " char)"
        else
            ks = tostring(k) .. " (" .. typeof(k) .. ")"
        end
        if type(val) == "table" then
            line(indent .. ks .. " → table")
            dump(val, indent .. "  ", depth + 1)
        else
            line(indent .. ks .. " → " .. typeof(val) .. " : " .. tostring(val))
        end
    end
    if n == 0 then line(indent .. "(空表)") end
end

line("安装 hook，请现在开一枪……")

-- 只用 hookfunction 精确 hook 这一个函数。
-- 之前用的 __namecall 会拦下游戏里所有方法调用（每帧上万次），手机上直接卡死 —— 不再用它。
local hooked = false
if hookfunction then
    local ok, err = pcall(function()
        local old = hookfunction(useItem.FireServer, function(self, ...)
            local argc = select("#", ...)
            print("========== 真实开火包 argc=" .. argc .. " ==========")
            for i = 1, argc do
                local a = select(i, ...)
                line(string.format("arg%d: %s : %s", i, typeof(a), tostring(a)))
                if type(a) == "table" then dump(a) end
            end
            print("==============================================")
            flush(true)
            return old(self, ...)
        end)
        hooked = true
    end)
    if not ok then line("hookfunction 失败: " .. tostring(err)) end
end

if not hooked then
    line("hookfunction 用不了，本机抓不到真实包")
    line("退路：把控制台里 UseItem 相关的报错、或者游戏里开火的准星截图发我，我换别的路子")
end

line("准备好了。开一枪，日志会写进 probe_out.txt")