-- ESP pe Instances (compat executors): Highlight + BillboardGui + tracer Frame
-- API: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")
local LocalPlayer= Players.LocalPlayer
local Camera     = Workspace.CurrentCamera

local M = {
    Inited=false,
    Conns={},
    PerPlayer={}, -- [plr] = { Highlight=..., BBG=..., NameLabel=..., Tracer=Frame }
    ScreenGui=nil, -- container pentru tracere 2D
}

local Config, Library, Tab

-- ========== Helpers ==========
local function getUIRoot()
    -- Folosim gethui() dacă există, altfel CoreGui (cel mai stabil pentru executors)
    local ok, ui = pcall(gethui)
    if ok and typeof(ui)=="Instance" and ui:IsA("Instance") then return ui end
    return CoreGui
end

local function sameTeam(a,b)
    if not a or not b then return false end
    if a == b then return true end
    if a.Team and b.Team then return a.Team == b.Team end
    if a.TeamColor and b.TeamColor then return a.TeamColor == b.TeamColor end
    return false
end

local function isEnemy(plr, teamCheck)
    if plr == LocalPlayer then return false end
    if not teamCheck then return true end
    return not sameTeam(LocalPlayer, plr)
end

local function getCharBits(plr)
    local ch = plr.Character
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local head= ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then return end
    if hum.Health <= 0 then return end
    return ch, hum, hrp, head
end

-- creează o linie 2D cu Frame
local function newLine(parent)
    local f = Instance.new("Frame")
    f.Name = "LP_Tracer"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromOffset(-1000, -1000)
    f.Size = UDim2.fromOffset(0, 1)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = Config.ESP.TracerColor
    f.BackgroundTransparency = 0
    f.ZIndex = 99999
    f.Parent = parent
    return f
end

local function setLine(frame, fromV2, toV2, thickness)
    local diff = toV2 - fromV2
    local len = diff.Magnitude
    if len < 1 then
        frame.Visible = false
        return
    end
    local angle = math.deg(math.atan2(diff.Y, diff.X))
    frame.Visible = true
    frame.Size = UDim2.fromOffset(len, thickness)
    frame.Position = UDim2.fromOffset(fromV2.X, fromV2.Y)
    frame.Rotation = angle
end

-- ========== Per-player spawn/despawn ==========
local function ensurePerPlayer(plr)
    if M.PerPlayer[plr] then return M.PerPlayer[plr] end

    local pack = {}

    -- Highlight (contur pe model)
    local hl = Instance.new("Highlight")
    hl.Name = "LP_Highlight"
    hl.Enabled = false
    hl.FillTransparency = 1
    hl.OutlineTransparency = 0.2
    hl.OutlineColor = Config.ESP.BoxColor
    pack.Highlight = hl

    -- BillboardGui pentru name+distance
    local bbg = Instance.new("BillboardGui")
    bbg.Name = "LP_BBG"
    bbg.AlwaysOnTop = true
    bbg.Size = UDim2.new(0, 200, 0, 40)
    bbg.Enabled = false

    local txt = Instance.new("TextLabel")
    txt.Name = "LP_Label"
    txt.Size = UDim2.fromScale(1,1)
    txt.BackgroundTransparency = 1
    txt.TextColor3 = Color3.new(1,1,1)
    txt.TextStrokeTransparency = 0.5
    txt.Text = ""
    txt.Font = Enum.Font.GothamMedium
    txt.TextScaled = true
    txt.Parent = bbg

    pack.BBG = bbg
    pack.NameLabel = txt

    -- Tracer (Frame) în ScreenGui global
    if not M.ScreenGui then
        M.ScreenGui = Instance.new("ScreenGui")
        M.ScreenGui.Name = "LP_ESP_Screen"
        M.ScreenGui.IgnoreGuiInset = true
        M.ScreenGui.ResetOnSpawn = false
        M.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        M.ScreenGui.Parent = getUIRoot()
    end
    pack.Tracer = newLine(M.ScreenGui)

    M.PerPlayer[plr] = pack
    return pack
end

local function removePerPlayer(plr)
    local p = M.PerPlayer[plr]; if not p then return end
    pcall(function() p.Highlight:Destroy() end)
    pcall(function() p.BBG:Destroy() end)
    pcall(function() p.Tracer:Destroy() end)
    M.PerPlayer[plr] = nil
end

-- ========== Loop principal ==========
local function updateAll()
    local showBox   = Config.ESP.EnabledBox
    local showName  = Config.ESP.ShowName
    local showDist  = Config.ESP.ShowDistance
    local showTrace = Config.ESP.ShowTracers
    local teamCheck = Config.ESP.TeamCheck

    local viewW, viewH = Camera.ViewportSize.X, Camera.ViewportSize.Y
    local originY = (Config.ESP.TracerOrigin == "Bottom" and viewH)
                 or (Config.ESP.TracerOrigin == "Center" and viewH*0.5)
                 or (viewH*0.5) -- Crosshair ≈ center
    local origin = Vector2.new(viewW*0.5, originY)

    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local chk, hum, hrp, head = getCharBits(plr)
            local enemyOK = isEnemy(plr, teamCheck)
            local pack = ensurePerPlayer(plr)

            -- default hide
            if not (chk and enemyOK) then
                if pack.Highlight then pack.Highlight.Enabled = false end
                if pack.BBG then pack.BBG.Enabled = false end
                if pack.Tracer then pack.Tracer.Visible = false end
            else
                -- Highlight attach
                if showBox then
                    pack.Highlight.Adornee = chk
                    pack.Highlight.OutlineColor = Config.ESP.BoxColor
                    pack.Highlight.Enabled = true
                else
                    pack.Highlight.Enabled = false
                end

                -- Name + Distance
                if showName or showDist then
                    pack.BBG.Adornee = head
                    local d = (Camera.CFrame.Position - hrp.Position).Magnitude
                    local nameStr = showName and plr.Name or ""
                    local distStr = showDist and (" ["..(d<999 and math.floor(d) or 999).."m]") or ""
                    pack.NameLabel.Text = nameStr..distStr
                    pack.BBG.Enabled = true
                else
                    pack.BBG.Enabled = false
                end

                -- Tracer
                if showTrace then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                    if onScreen then
                        setLine(pack.Tracer, origin, Vector2.new(screenPos.X, screenPos.Y), Config.ESP.TracerThickness)
                        pack.Tracer.BackgroundColor3 = Config.ESP.TracerColor
                    else
                        pack.Tracer.Visible = false
                    end
                else
                    pack.Tracer.Visible = false
                end
            end
        end
    end
end

-- ========== Hooks ==========
local function ensureHooks()
    -- PlayerAdded
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(plr)
        ensurePerPlayer(plr)
    end))
    -- PlayerRemoving
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(plr)
        removePerPlayer(plr)
    end))
end

local function bindLoop()
    table.insert(M.Conns, RunService.RenderStepped:Connect(updateAll))
end

local function clearAll()
    for _,c in ipairs(M.Conns) do pcall(function() c:Disconnect() end) end
    M.Conns = {}
    for plr in pairs(M.PerPlayer) do removePerPlayer(plr) end
    if M.ScreenGui then pcall(function() M.ScreenGui:Destroy() end); M.ScreenGui=nil end
end

-- ========== Public API ==========
function M.Destroy()
    clearAll()
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited, Config, Library, Tab = true, cfg, lib, tab

    -- UI group
    local G = Tab:AddLeftGroupbox("ESP (Instance)")
    G:AddToggle("EnemyESP", {
        Text="Enemy ESP (Highlight)", Default=false,
        Callback=function(v) Config.ESP.EnabledBox = v end
    })
    G:AddToggle("NameESP", {
        Text="Show Names", Default=false,
        Callback=function(v) Config.ESP.ShowName = v end
    })
    G:AddToggle("DistanceESP", {
        Text="Show Distance", Default=false,
        Callback=function(v) Config.ESP.ShowDistance = v end
    })
    G:AddToggle("TracerESP", {
        Text="Show Tracers", Default=false,
        Callback=function(v) Config.ESP.ShowTracers = v end
    })
    G:AddToggle("TeamCheck", {
        Text="Team Check", Default=Config.ESP.TeamCheck,
        Callback=function(v) Config.ESP.TeamCheck = v end
    })
    G:AddSlider("TracerThickness", {
        Text="Tracer Thickness", Default=Config.ESP.TracerThickness, Min=1, Max=6, Rounding=0,
        Callback=function(v) Config.ESP.TracerThickness = math.clamp(v,1,6) end
    })
    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"}, Default=Config.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) Config.ESP.TracerOrigin = v end
    })

    -- pregătim entry pentru toți deja prezenți
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then ensurePerPlayer(p) end
    end
    ensureHooks()
    bindLoop()
end

return M
