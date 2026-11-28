--[[
  OREO · 入口（v9）· 只留 5 个页签的 Kicia + 云端参数
  loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/oreo_v9.lua"))()
]]

local MIRRORS = {
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/oreo-kicia-v9.lua",
    "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/oreo-kicia-v9.lua",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/oreo-kicia-v9.lua",
}

print("[OREO] 开始加载 v9（2.1 MB，第一次十几秒）")

local code, from
for _, url in ipairs(MIRRORS) do
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res > 1500000 then
        code, from = res, url
        break
    end
end

if not code then
    warn("[OREO] 三个源都拉不到，检查网络")
    return
end

print(string.format("[OREO] 拉到 %d 字节", #code))
local fn, err = loadstring(code)
if not fn then warn("[OREO] 编译失败：" .. tostring(err)) return end
local ok, err2 = pcall(fn)
if not ok then warn("[OREO] 运行出错：" .. tostring(err2)) return end
print("[OREO] 已加载 v9 · 悬浮按钮开菜单 · 云端默认 slot2")
