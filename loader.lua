--[[
════════════════════════════════════════════════════════════
  Rivals Hub · Loader
  改下面三行 → 推到自己的 GitHub → 游戏里一行加载：

    loadstring(game:HttpGet("https://raw.githubusercontent.com/你的名字/rivals-hub/main/loader.lua"))()

  这个文件只干一件事：从几个镜像里抢最快的那个把 main.lua 拉下来执行，
  GitHub 直连抽风时会自动换 jsDelivr / gitmirror / ghproxy。
════════════════════════════════════════════════════════════
]]

local GITHUB_USER = "YOUR_NAME"     -- ← 改这里
local REPO        = "rivals-hub"    -- ← 仓库名
local BRANCH      = "main"
local FILE        = "main.lua"

local base = GITHUB_USER .. "/" .. REPO
local SOURCES = {
    "https://raw.githubusercontent.com/" .. base .. "/" .. BRANCH .. "/" .. FILE,
    "https://cdn.jsdelivr.net/gh/" .. base .. "@" .. BRANCH .. "/" .. FILE,
    "https://raw.gitmirror.com/" .. base .. "/" .. BRANCH .. "/" .. FILE,
    "https://ghproxy.net/https://raw.githubusercontent.com/" .. base .. "/" .. BRANCH .. "/" .. FILE,
    "https://gh-proxy.com/https://raw.githubusercontent.com/" .. base .. "/" .. BRANCH .. "/" .. FILE,
}

local function fetch(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then
        ok, res = pcall(function() return game:HttpGet(url) end)
    end
    if ok and type(res) == "string" and #res > 1000 then
        if res:find("Rivals Hub", 1, true) or res:find("RIVALS", 1, true) then
            return res
        end
        if res:find("404", 1, true) and #res < 3000 then
            return nil
        end
    end
    return nil
end

local code, used
for _, url in ipairs(SOURCES) do
    code = fetch(url)
    if code then
        used = url
        break
    end
end

if not code then
    warn("[RivalsHub] 所有源都拉不到 main.lua，检查用户名 / 仓库名 / 分支，或换个网络")
    return
end

local fn, err = loadstring(code)
if not fn then
    warn("[RivalsHub] 下载到了但编译失败：" .. tostring(err))
    return
end

print(string.format("[RivalsHub] %d 字节 · 来自 %s", #code, used))
fn()
