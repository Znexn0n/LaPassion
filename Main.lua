-- La Passion • Main (modular) — FIX: ThemeManager fallback safe

-- 1) Obsidian UI (cu fallback dacă addon-ul nu are anumite metode)
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local okLib, Library = pcall(function() return loadstring(game:HttpGet(repo .. "Library.lua"))() end)
if not okLib or type(Library) ~= "table" then
    error("[La Passion] Obsidian Library.lua failed to load")
end

local okTheme, ThemeManager = pcall(function() return loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))() end)
if not okTheme then
    ThemeManager = nil -- continuăm fără addon, UI merge oricum
end

-- 2) Bootstrap inject: Import/Fetch din Bootstrap.lua
local Import, Fetch = Import, Fetch

-- 3) Config central
local Config = Import("Config.lua")

-- 4) Fereastră + Tabs
local Window = Library:CreateWindow({
    Title  = "La Passion",
    Icon   = 87113640778394,
    Footer = "Private Test Build",
    Center = true,
    AutoShow = true
})

local Tabs = {
    Training = Window:AddTab("Training"),
    Visual   = Window:AddTab({ Name="Visual", Description="ESP & World", Icon="eye" }),
    Tools    = Window:AddTab("Tools"),
    Config   = Window:AddTab("Config")
}

-- 5) ThemeManager – apelăm DOAR ce există (evită crash-ul ApplyToWindow)
if ThemeManager and type(ThemeManager) == "table" then
    if type(ThemeManager.SetLibrary) == "function" then
        pcall(function() ThemeManager:SetLibrary(Library) end)
    end
    -- unele versiuni nu au ApplyToWindow; îl chemăm doar dacă există
    if type(ThemeManager.ApplyToWindow) == "function" then
        pcall(function() ThemeManager:ApplyToWindow(Window) end)
    end
end

-- 6) Module
local ESP       = Import("Modules/ESP.lua")
local HBExt     = Import("Modules/HitboxExtender.lua")
local World     = Import("Modules/World.lua")
local Watermark = Import("Modules/Watermark.lua")

-- 7) Init module + wiring UI
local Options, Toggles = Library.Options, Library.Toggles

local function Init()
    -- Important: dacă vreun modul aruncă eroare, nu blocăm restul
    pcall(function() ESP.Init(Config, Library, Tabs.Visual) end)
    pcall(function() HBExt.Init(Config, Library, Tabs.Training) end)
    pcall(function() World.Init(Config, Library, Tabs.Visual) end)
    pcall(function() Watermark.Init(Config, Library, Tabs.Tools) end)

    -- Config tab (bind + unload)
    local G = Tabs.Config:AddLeftGroupbox("Settings")
    G:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default="RightShift", NoUI=true, Text="Menu keybind" })
    Library.ToggleKeybind = (Library.Options and Library.Options.MenuKeybind) or Options.MenuKeybind

    G:AddButton("Unload", function()
        pcall(function() ESP.Destroy() end)
        pcall(function() HBExt.Destroy() end)
        pcall(function() World.Destroy() end)
        pcall(function() Watermark.Destroy() end)
        pcall(function() if Library and type(Library.Unload) == "function" then Library:Unload() end end)
    end)

    Library:Notify("La Passion loaded successfully ツ", 4)
end

return { Init = Init, Run = function() end }
