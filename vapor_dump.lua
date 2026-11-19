--[[  VAPOR 解包器
  VAPOR 的 Loader.lua 是 Luraph v15.1 混淆（2.7MB），静态拿不到源码。
  它最后一定得调 loadstring 去跑明文，所以在 loadstring 上挂个钩子把明文抄下来。
  loadstring 调用次数极少，不会像 __namecall 那样卡死。

    loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/rivals-hub/main/vapor_dump.lua"))()
]]

local LOG, last = {}, 0
local function flush(force)
    local now = os.clock()
    if not force and now - last < 1 then return end
    last = now
    local t = table.concat(LOG, "\n")
    pcall(function() if writefile then writefile("vapor_dump_log.txt", t) end end)
end

local n = 0
local realLoadstring = loadstring
local function hookedLoadstring(src, chunkname)
    if type(src) == "string" and #src > 500 then
        n = n + 1
        local name = string.format("vapor_payload_%02d.lua", n)
        pcall(function() if writefile then writefile(name, src) end end)
        local head = src:sub(1, 120):gsub("\n", " ")
        LOG[#LOG + 1] = string.format("捕获 #%d  %d 字节  %s", n, #src, head)
        print(string.format("[DUMP] 抓到 %d 字节 → %s", #src, name))
        flush(true)
    end
    return realLoadstring(src, chunkname)
end

-- 各种执行器可能把 loadstring 放在不同地方
pcall(function() loadstring = hookedLoadstring end)
pcall(function() getgenv().loadstring = hookedLoadstring end)
pcall(function() _G.loadstring = hookedLoadstring end)

-- 有的混淆器用 getfenv().loadstring
pcall(function()
    local env = getfenv and getfenv()
    if type(env) == "table" then env.loadstring = hookedLoadstring end
end)

LOG[#LOG + 1] = "loadstring 钩子已挂，开始加载 VAPOR"
print("[DUMP] 钩子已挂，现在加载 VAPOR…")

local ok, err = pcall(function()
    local loader = game:HttpGet("https://raw.githubusercontent.com/ProjectVaporScripts/Vapor/refs/heads/main/V1/Loader.lua", true)
    if type(loader) ~= "string" or #loader < 1000 then
        error("loader 拉取失败")
    end
    LOG[#LOG + 1] = "loader 已拉到 " .. #loader .. " 字节"
    local fn = realLoadstring(loader)
    if not fn then error("loader 编译失败") end
    fn()
end)

LOG[#LOG + 1] = "加载结果: " .. tostring(ok) .. " " .. tostring(err)
print("[DUMP] 加载结果: " .. tostring(ok) .. " " .. tostring(err))
flush(true)
