--[[  PROBE 2 · 找 FighterController 到底在哪
  上一版探针的结论：Remotes 和 Modules 都在，EncodeCFrame 也正常，
  但 findModule("FighterController") = false —— 所以拿不到武器、也就没发过一个包。
  这个只做扫描，不 hook、不改游戏。
    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/probe2.lua"))()
]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer

local LOG, last = {}, 0
local function flush(force)
    local now = os.clock()
    if not force and now - last < 1 then return end
    last = now
    local t = table.concat(LOG, "\n")
    pcall(function() if writefile then writefile("probe2_out.txt", t) end end)
end
local function line(m)
    LOG[#LOG + 1] = tostring(m)
    print("[P2] " .. tostring(m))
    flush(false)
end

line("PlaceId=" .. tostring(game.PlaceId))

--────────── 1. 全盘找 FighterController 及同类模块 ──────────
local roots = {
    { name = "ReplicatedStorage", inst = RS },
    { name = "PlayerScripts",     inst = LP:FindFirstChild("PlayerScripts") },
    { name = "StarterPlayer",     inst = game:GetService("StarterPlayer") },
}

local KEYWORDS = { "Fighter", "Item", "Weapon", "Loadout" }

for _, r in ipairs(roots) do
    if r.inst then
        local hits = {}
        for _, d in ipairs(r.inst:GetDescendants()) do
            if d:IsA("ModuleScript") then
                for _, kw in ipairs(KEYWORDS) do
                    if string.find(d.Name, kw, 1, true) then
                        table.insert(hits, d:GetFullName())
                        break
                    end
                end
            end
        end
        line(string.format("[%s] 命中 %d 个模块", r.name, #hits))
        for i = 1, math.min(#hits, 60) do line("   " .. hits[i]) end
    else
        line("[" .. r.name .. "] 不存在")
    end
end

--────────── 2. ToEnum 的返回值到底是什么 ──────────
local mods = RS:FindFirstChild("Modules")
local enumLib
if mods and mods:FindFirstChild("EnumLibrary") then
    pcall(function() enumLib = require(mods.EnumLibrary) end)
end
if enumLib then
    for _, name in ipairs({ "StartShooting", "StartAiming", "Attack", "StartReloading" }) do
        local ok, v = pcall(function() return enumLib:ToEnum(name) end)
        line(string.format("ToEnum(%s) ok=%s type=%s typeof=%s val=%q",
            name, tostring(ok), type(v), typeof(v), tostring(v)))
    end
    -- 看看还有没有别的入口
    local keys = {}
    for k, v in pairs(enumLib) do
        if type(k) == "string" then
            table.insert(keys, k .. ":" .. typeof(v))
        end
    end
    table.sort(keys)
    line("EnumLibrary 字段: " .. table.concat(keys, ", "))
end

--────────── 3. 角色身上有什么可以用来找武器 ──────────
local ch = LP.Character
if ch then
    local tools, tagged = {}, {}
    for _, d in ipairs(ch:GetDescendants()) do
        if d:IsA("Tool") then table.insert(tools, d.Name) end
        if d:IsA("Model") and d ~= ch then table.insert(tagged, "Model:" .. d.Name) end
    end
    line("角色里的 Tool: " .. (#tools > 0 and table.concat(tools, ", ") or "无"))
    line("角色里的子 Model: " .. (#tagged > 0 and table.concat(tagged, ", ") or "无"))
else
    line("角色为 nil")
end

--────────── 4. 玩家对象上有没有物品相关的属性 ──────────
local attrs = {}
for k, v in pairs(LP:GetAttributes()) do
    table.insert(attrs, k .. "=" .. tostring(v))
end
line("LocalPlayer 属性: " .. (#attrs > 0 and table.concat(attrs, ", ") or "无"))

--────────── 5. 背包里有什么 ──────────
local bp = LP:FindFirstChildOfClass("Backpack")
if bp then
    local names = {}
    for _, t in ipairs(bp:GetChildren()) do table.insert(names, t.Name .. "(" .. t.ClassName .. ")") end
    line("背包: " .. (#names > 0 and table.concat(names, ", ") or "空"))
else
    line("没有 Backpack")
end

line("扫描结束")
flush(true)
