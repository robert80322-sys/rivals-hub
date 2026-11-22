--[[
════════════════════════════════════════════════════════════
  KICIA PRESET · 从自己仓库加载完整 Kicia，并给出调好的清单
 
  仓库里 vendor/kicia.lua 就是原作者那份完整克隆（2.17 MB），
  这里只是加载它 + 把该调的项列出来。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/kicia_preset.lua?t=" .. os.time()))()
════════════════════════════════════════════════════════════
]]

local BASE = "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/"
local MIRRORS = {
    BASE .. "vendor/kicia.lua",
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/vendor/kicia.lua",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/vendor/kicia.lua",
}

print("[PRESET] 开始加载 Kicia（2.1MB，第一次要十几秒）")

local code, from
for _, url in ipairs(MIRRORS) do
    local ok, res = pcall(function() return game:HttpGet(url .. "?t=" .. tostring(os.time()), true) end)
    if not ok then ok, res = pcall(function() return game:HttpGet(url .. "?t=" .. tostring(os.time())) end) end
    if ok and type(res) == "string" and #res > 100000 then
        code, from = res, url
        break
    end
end

if not code then
    warn("[PRESET] 三个源都拉不到，检查网络")
    return
end

print(string.format("[PRESET] 拉到 %d 字节", #code))

local fn, err = loadstring(code)
if not fn then
    warn("[PRESET] 编译失败：" .. tostring(err))
    return
end

local ok, err2 = pcall(fn)
if not ok then
    warn("[PRESET] 运行出错：" .. tostring(err2))
    return
end

-- 等它初始化完
task.spawn(function()
    task.wait(4)
    local K = getgenv().KiciaRebuild
    if not K then
        warn("[PRESET] KiciaRebuild 没出现，可能加载失败")
        return
    end
    print("================ 已加载 Kicia ================")
    print("build: " .. tostring(K.Build))
    print("菜单：屏幕上的悬浮按钮（不需要键盘）")
    print("------------------------ 调这几个 ------------------------")
    print("Combat 页")
    print("  · Enable Aimbot            → Always（常开）")
    print("  · Aim Mode                 → Spring（最顺手）")
    print("  · Enable Silent Aim        → Always")
    print("  · Activation Chance (%)    → 100      ← 命中率的关键")
    print("  · Enable Triggerbot        → Always   ← 准星压到人就自动开枪")
    print("  · Reaction Delay           → 0")
    print("  · Target Filters           → 只留 Head / 视野内")
    print("Visuals 页")
    print("  · Player ESP               → 开，Box + Name + Health + Distance")
    print("  · Target Conditions        → Visible（只画看得见的）或全开")
    print("Ragebot 页（想要贴脸打法再开）")
    print("  · Ragebot Style            → KH")
    print("  · 只勾 Primary/Secondary 武器，别勾近战")
    print("==============================================")
end)

print("[PRESET] Kicia 已启动，等 4 秒会打印调参清单看 F9")
