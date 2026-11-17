--[[
════════════════════════════════════════════════════════════
  Rivals Hub · 全套入口
  先拉 Kicia/Rebuild 全套（ragebot、物品修改器、自动排队…），
  再拉我这边的手枪版 hub，两者并存。

  一行：
    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/all.lua"))()
════════════════════════════════════════════════════════════
]]

local BASE = "https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/"

local MIRRORS = {
    BASE,
    "https://cdn.jsdelivr.net/gh/robert80322-sys/rivals-hub@main/",
    "https://raw.gitmirror.com/robert80322-sys/rivals-hub/main/",
    "https://ghproxy.net/https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/",
}

local function pull(name)
    for _, b in ipairs(MIRRORS) do
        local ok, src = pcall(function() return game:HttpGet(b .. name, true) end)
        if not ok then
            ok, src = pcall(function() return game:HttpGet(b .. name) end)
        end
        if ok and type(src) == "string" and #src > 200 then
            return src, b .. name
        end
    end
    return nil
end

local function run(name)
    local src, from = pull(name)
    if not src then
        warn("[RivalsHub] 拉不到 " .. name)
        return false
    end
    local fn, err = loadstring(src)
    if not fn then
        warn("[RivalsHub] 编译失败 " .. name .. " : " .. tostring(err))
        return false
    end
    local ok, err2 = pcall(fn)
    if not ok then
        warn("[RivalsHub] 运行出错 " .. name .. " : " .. tostring(err2))
        return false
    end
    print(string.format("[RivalsHub] %s 已载入 (%d 字节)", name, #src))
    return true
end

-- 1) Kicia 全套（ragebot 在这里面）
local gotKicia = run("vendor/kicia.lua")
if gotKicia then
    getgenv().RivalsHubKiciaLoaded = true
end

task.wait(0.5)

-- 2) 我的 hub
run("main.lua")

print("[RivalsHub] 全套加载完成")
