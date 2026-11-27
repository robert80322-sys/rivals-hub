--[[
  OREO LITE · 入口（带镜像回退）
  loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/oreo_preset.lua?t=" .. os.time()))()
]]

local BASE = "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/"
local MIRRORS = {
    BASE .. "oreo-lite.lua",
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/oreo-lite.lua",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/oreo-lite.lua",
}

local code
for _, url in ipairs(MIRRORS) do
    local ok, res = pcall(function() return game:HttpGet(url .. "?t=" .. tostring(os.time())) end)
    if ok and type(res) == "string" and #res > 20000 then
        code = res
        break
    end
end

if not code then
    warn("[OREO LITE] 三个源都拉不到，检查网络")
    return
end

local fn, err = loadstring(code)
if not fn then
    warn("[OREO LITE] 编译失败：" .. tostring(err))
    return
end

local ok, err2 = pcall(fn)
if not ok then
    warn("[OREO LITE] 运行出错：" .. tostring(err2))
    return
end

print(string.format("[OREO LITE] 已加载（%d 字节），左侧 ≡ 或 RightShift 打开菜单", #code))
