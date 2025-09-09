-- ESP (Drawing API) • enemy-only • toggles corecte • auto-update players
-- API expus: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local M = {
    Inited = false,
    RenderConn = nil,
    PlayerAddedConn = nil,
    PlayerRemovingConn = nil,
    CharConns = {},              -- [player] = RBXScriptConnection (CharacterAdded)
    Draw = {}                    -- [player] = { Box, Name, Dist, Tracer }
}

local Config, Library, Tab

-- ====== Safety: verificăm Drawing API ======
local function DrawingAvailable()
    return (typeof(Drawing) == "table" and type(Drawing.new) == "function")
end

-- ====== Utils ======
local function SameTeam(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if a.Team and b.Team then return a.Team == b.Team end
    if a.TeamColor and b.TeamColor then return a.TeamColor == b.TeamColor end
    return false
end

local function IsEnemy(plr, teamCheck)
    if plr == LocalPlayer then return false end
    if not teamCheck then return true end
    return not SameTeam(LocalPlayer, plr)
end

local function HidePack(pack)
    if not pack then return end
    pack.Box.Visible   = false
    pack.Name.Visible  = false
    pack.Dist.Visible  = false
    pack.Tracer.Visible= false
end

local function RemovePack(plr)
    local p = M.Draw[plr]; if not p then return end
    HidePack(p)
    for _,d in pairs(p) do pcall(function() d:Remove() end) end
    M.Draw[plr] = nil
    if M.CharConns[plr] then pcall(function() M.CharConns[plr]:Disconnect() end); M.CharConns[plr]=nil end
end

local function CreatePack(plr)
    if M.Draw[plr] then return end
    local box    = Drawing.new("Square"); box.Filled=false; box.Thickness=2; box.Visible=false; box.Color=Config.ESP.BoxColor
    local name   = Drawing.new("Text");   name.Center=true; name.Size=16; name.Outline=true; name.Visible=false; name.Color=Color3.new(1,1,1)
    local dist   = Drawing.new("Text");   dist.Center=true; dist.Size=14; dist.Outline=true; dist.Visible=false; dist.Color=Color3.fromRGB(150,200,255)
    local tracer = Drawing.new("Line");   tracer.Visible=false; tracer.Thickness=Config.ESP.TracerThickness; tracer.Color=Config.ESP.TracerColor

    M.Draw[plr] = { Box=box, Name=name, Dist=dist, Tracer=tracer }

    -- Re-hook la respawn (loop-ul va repoziționa)
    if M.CharConns[plr] then M.CharConns[plr]:Disconnect() end
    M.CharConns[plr] = plr.CharacterAdded:Connect(function() end)
end

-- Aproximăm box-ul 2D din Head/HRP (replică a logicii tale)
local function ComputeBoxFromHeadRoot(char)
    local head = char:FindFirstChild("Head")
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    if not (head and hrp) then return end

    local head2D, on1 = Camera:WorldToViewportPoint(head.Position)
    local root2D, on2 = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
    if not (on1 and on2) then return end

    local height = (head2D.Y - root2D.Y) * 1.5
    if height < 0 then height = -height end
    local width  = height / 2

    local pos2D, onS = Camera:WorldToViewportPoint(hrp.Position)
    if not onS then return end

    local x = pos2D.X - width/2
    local y = pos2D.Y - height/2
    return x, y, width, height, Vector2.new(pos2D.X, pos2D.Y)
end

-- ====== Loop logic ======
local function AnyToggleOn()
    local E = Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function StartLoop()
    if M.RenderConn then return end
    M.RenderConn = RunService.RenderStepped:Connect(function()
        if not AnyToggleOn() then return end

        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local E = Config.ESP
        local originY = (E.TracerOrigin == "Bottom" and scrH)
                     or (E.TracerOrigin == "Center" and scrH*0.5)
                     or (scrH*0.5) -- Crosshair ≈ center
        local origin = Vector2.new(scrW*0.5, originY)
        local camPos = Camera.CFrame.Position

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local ok = char and hum and hrp and hum.Health > 0 and IsEnemy(plr, E.TeamCheck)

                local pack = M.Draw[plr]
                if not pack then CreatePack(plr); pack = M.Draw[plr] end

                if not ok then
                    HidePack(pack)
                else
                    local x,y,w,h,center = ComputeBoxFromHeadRoot(char)
                    if not x then
                        HidePack(pack)
                    else
                        -- BOX
                        if E.EnabledBox then
                            pack.Box.Position = Vector2.new(x, y)
                            pack.Box.Size     = Vector2.new(w, h)
                            pack.Box.Color    = E.BoxColor
                            pack.Box.Visible  = true
                        else
                            pack.Box.Visible  = false
                        end

                        -- NAME
                        if E.ShowName then
                            pack.Name.Position = Vector2.new(x + w/2, y - 18)
                            pack.Name.Text     = plr.Name
                            pack.Name.Visible  = true
                        else
                            pack.Name.Visible  = false
                        end

                        -- DISTANCE
                        if E.ShowDistance then
                            local d = (camPos - hrp.Position).Magnitude
                            pack.Dist.Text     = ("[%dm]"):format(d < 999 and math.floor(d) or 999)
                            pack.Dist.Position = Vector2.new(x + w/2, y + h + 15)
                            pack.Dist.Visible  = true
                        else
                            pack.Dist.Visible  = false
                        end

                        -- TRACER
                        if E.ShowTracers then
                            pack.Tracer.From      = origin
                            pack.Tracer.To        = center
                            pack.Tracer.Thickness = E.TracerThickness
                            pack.Tracer.Color     = E.TracerColor
                            pack.Tracer.Visible   = true
                        else
                            pack.Tracer.Visible   = false
                        end
                    end
                end
            end
        end
    end)
end

local function StopLoopAndCleanupIfIdle()
    if AnyToggleOn() then return end
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    for _,p in pairs(M.Draw) do HidePack(p) end
    if M.PlayerAddedConn then M.PlayerAddedConn:Disconnect(); M.PlayerAddedConn=nil end
    if M.PlayerRemovingConn then M.PlayerRemovingConn:Disconnect(); M.PlayerRemovingConn=nil end
    for plr in pairs(M.CharConns) do pcall(function() M.CharConns[plr]:Disconnect() end); M.CharConns[plr]=nil end
end

local function EnsurePlayerHooks()
    if M.PlayerAddedConn then return end
    -- inițializează pentru cei existenți
    for _,p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then CreatePack(p) end end

    M.PlayerAddedConn = Players.PlayerAdded:Connect(function(p)
        if p ~= LocalPlayer then CreatePack(p) end
    end)
    M.PlayerRemovingConn = Players.PlayerRemoving:Connect(function(p)
        RemovePack(p)
    end)
end

-- ====== Public API ======
function M.Destroy()
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    if M.PlayerAddedConn then pcall(function() M.PlayerAddedConn:Disconnect() end); M.PlayerAddedConn=nil end
    if M.PlayerRemovingConn then pcall(function() M.PlayerRemovingConn:Disconnect() end); M.PlayerRemovingConn=nil end
    for plr in pairs(M.CharConns) do pcall(function() M.CharConns[plr]:Disconnect() end) end
    M.CharConns = {}
    for plr in pairs(M.Draw) do RemovePack(plr) end
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited, Config, Library, Tab = true, cfg, lib, tab

    -- dacă executorul nu are Drawing, arătăm un mesaj simplu și ieșim (UI rămâne)
    if not DrawingAvailable() then
        warn("[La Passion][ESP] Drawing API indisponibil în acest executor.")
        local G = tab:AddLeftGroupbox("ESP (Drawing)")
        G:AddLabel("Drawing API indisponibil.")
        return
    end

    local G = Tab:AddLeftGroupbox("ESP (Drawing)")

    G:AddToggle("EnemyESP", {
        Text="Enemy ESP (Box)", Default=false,
        Callback=function(v) Config.ESP.EnabledBox = v; if v then EnsurePlayerHooks(); StartLoop() else StopLoopAndCleanupIfIdle() end end
    })

    G:AddToggle("NameESP", {
        Text="Show Names", Default=false,
        Callback=function(v) Config.ESP.ShowName = v; if v then EnsurePlayerHooks(); StartLoop() else StopLoopAndCleanupIfIdle() end end
    })

    G:AddToggle("DistanceESP", {
        Text="Show Distance", Default=false,
        Callback=function(v) Config.ESP.ShowDistance = v; if v then EnsurePlayerHooks(); StartLoop() else StopLoopAndCleanupIfIdle() end end
    })

    G:AddToggle("TracerESP", {
        Text="Show Tracers", Default=false,
        Callback=function(v) Config.ESP.ShowTracers = v; if v then EnsurePlayerHooks(); StartLoop() else StopLoopAndCleanupIfIdle() end end
    })

    G:AddToggle("TeamCheck", {
        Text="Team Check", Default=Config.ESP.TeamCheck,
        Callback=function(v) Config.ESP.TeamCheck = v end
    })

    G:AddSlider("TracerThickness", {
        Text="Tracer Thickness", Min=1, Max=5, Rounding=0, Default=Config.ESP.TracerThickness,
        Callback=function(v) Config.ESP.TracerThickness = math.clamp(v,1,5) end
    })

    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"}, Default=Config.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) Config.ESP.TracerOrigin = v end
    })
end

return M
