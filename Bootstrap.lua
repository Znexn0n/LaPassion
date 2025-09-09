-- Bootstrapper: încarcă remote toate fișierele din repo și pornește aplicația
local BASE = "https://raw.githubusercontent.com/Znexn0n/LaPassion/main/"

local function Fetch(path) return game:HttpGet(BASE .. path) end

-- Loader cu cache (ca un "require" pentru fișiere remote)
local __cache = {}
local function Import(path, inject)
    if __cache[path] then return __cache[path] end
    local src = Fetch(path)
    local chunk, err = loadstring(src, "@"..path)
    if not chunk then error("Import load error "..path.." • "..tostring(err)) end
    local env = setmetatable(inject or {}, { __index = getfenv() }); setfenv(chunk, env)
    local ret = chunk()
    __cache[path] = (ret ~= nil) and ret or true
    return __cache[path]
end

local Inject = { Import = Import, Fetch = Fetch }

local App = Import("Main.lua", Inject)
if type(App) == "table" and App.Init then
    App.Init()
    if App.Run then App.Run() end
end
