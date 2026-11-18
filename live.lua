--[[
════════════════════════════════════════════════════════════
  LIVE · 永远拉最新的 rage.lua
    这个文件本身永远不用改，所以就算它被执行器缓存了也没关系 ——
    它拉正文时每次都带一个随机时间戳，CDN 和本地缓存都绕过去了。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/live.lua"))()
════════════════════════════════════════════════════════════
]]

local OWNER = "robert80322-sys"
local REPO  = "rivals-hub"
local FILE  = "rage.lua"

local stamp = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))

local SOURCES = {
    "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/main/" .. FILE .. "?t=" .. stamp,
    "https://cdn.jsdelivr.net/gh/" .. OWNER .. "/" .. REPO .. "@main/" .. FILE .. "?t=" .. stamp,
    "https://raw.gitmirror.com/" .. OWNER .. "/" .. REPO .. "/main/" .. FILE .. "?t=" .. stamp,
}

local code, used
for _, url in ipairs(SOURCES) do
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then
        ok, res = pcall(function() return game:HttpGet(url) end)
    end
    if ok and type(res) == "string" and #res > 1000
    and not res:find("404: Not Found", 1, true)
    and not res:find("<!DOCTYPE", 1, true) then
        code, used = res, url
        break
    end
end

if not code then
    warn("[LIVE] 三个源都拉不到 " .. FILE .. "，检查网络")
    return
end

local ver = code:match('SCRIPT_VER%s*=%s*"([%w%.]+)"')
print(string.format("[LIVE] 拉到 %s（%d 字节）%s", FILE, #code,
    ver and ("版本 " .. ver) or ""))

-- 先卸掉上一轮加载实例，避免两个面板叠在一起
if getgenv().RageLiteUnload then
    pcall(getgenv().RageLiteUnload)
end

local fn, err = loadstring(code)
if not fn then
    warn("[LIVE] 编译失败：" .. tostring(err))
    return
end

local ok, err2 = pcall(fn)
if not ok then
    warn("[LIVE] 运行出错：" .. tostring(err2))
end
