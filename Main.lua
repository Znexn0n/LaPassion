-- La Passion • Main (modular)

-- UI Obsidian
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local Options, Toggles = Library.Options, Library.Toggles

-- Inject din Bootstrap.lua
local Import, Fetch = Import, Fetch

-- Config central
local Config = Import("Config.lua")

-- Window + Tabs
local Window = Library:CreateWindow({ Title="La Passion", Icon=87113640778394, Footer="Private Test Build", Center=true, AutoShow=true })
local Tabs = {
    Training = Window:AddTab("Training"),
    Visual   = Window:AddTab({ Name="Visual", Description="ESP & World", Icon="eye" }),
    Tools    = Window:AddTab("Tools"),
    Config   = Window:AddTab("Config")
}
ThemeManager:SetLibrary(Library); ThemeManager:ApplyToWindow(Window)

-- Module
local ESP       = Import("Modules/ESP.lua")
local HBExt     = Import("Modules/HitboxExtender.lua")
local World     = Import("Modules/World.lua")
local Watermark = Import("Modules/Watermark.lua")

local function Init()
    ESP.Init(Config, Library, Tabs.Visual)
    HBExt.Init(Config, Library, Tabs.Training)
    World.Init(Config, Library, Tabs.Visual)
    Watermark.Init(Config, Library, Tabs.Tools)

    local G = Tabs.Config:AddLeftGroupbox("Settings")
    G:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default="RightShift", NoUI=true, Text="Menu keybind" })
    Library.ToggleKeybind = Options.MenuKeybind

    G:AddButton("Unload", function()
        pcall(function() ESP.Destroy() end)
        pcall(function() HBExt.Destroy() end)
        pcall(function() World.Destroy() end)
        pcall(function() Watermark.Destroy() end)
        pcall(function() if Library and type(Library.Unload)=="function" then Library:Unload() end end)
    end)

    Library:Notify("La Passion loaded successfully ツ", 4)
end

return { Init = Init, Run = function() end }
