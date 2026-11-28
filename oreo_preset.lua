--[[
  OREO · Kicia 原版界面（只留 5 个模块）
  ============================================================
  界面上只有：
    Combat  → Aimbot / Silent Aim / Fire Assist
    Visuals → Player ESP / Weapon Visuals
    Player  → Character（Held Item Chams = 半透明武器）
    Settings→ General / Theme / Config Profiles
  其它页签（Ragebot、Automation、Cosmetics、Movement、World、Detection…）
  已在 UI 层被拦掉，不会出现，但底层不动。

  一次加载约 2.1 MB，第一次十几秒，正常。

  loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/oreo_preset.lua?t=" .. os.time()))()
]]

local BASE = "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/"
local MIRRORS = {
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/oreo-kicia-v7.lua",
    BASE .. "oreo-kicia-v7.lua",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/oreo-kicia-v7.lua",
}

print("[OREO] 开始加载（2.1 MB，第一次要十几秒）")

local code, from
for _, url in ipairs(MIRRORS) do
    local ok, res = pcall(function()
        return game:HttpGet(url .. "?t=" .. tostring(os.time()))
    end)
    if ok and type(res) == "string" and #res > 1500000 then
        code, from = res, url
        break
    end
end

if not code then
    warn("[OREO] 三个源都拉不到，检查网络")
    return
end

print(string.format("[OREO] 拉到 %d 字节：%s", #code, from))

local fn, err = loadstring(code)
if not fn then
    warn("[OREO] 编译失败：" .. tostring(err))
    return
end

local ok, err2 = pcall(fn)
if not ok then
    warn("[OREO] 运行出错：" .. tostring(err2))
    return
end

print("[OREO] 已加载：屏幕上的悬浮按钮打开菜单")
