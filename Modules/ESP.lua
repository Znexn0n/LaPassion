-- ESP (enemy-only) • toggles corecte, auto-update players, respawn safe
-- API: Init(cfg, lib, tab) / Destroy()

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

local LocalPlayer  = Players.LocalPlayer
local Camera       = Workspace.CurrentCamera

local M = {
    Drawings = {},        -- [player] = {Box,Name,Dist,Tracer}
    RenderConn = nil,     -- connection la RenderStepped
    PAdded = nil,         -- Players.PlayerAdded conn
    PRemoving = nil,      -- Players.PlayerRemoving conn
    CharConns = {},       -- [player] = RBXScriptConnection
    Inited = false
}

local Config, Library, Tab

-- ============ Helpers ============

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

local function IsHBorProxy(part)
    if not part or not part:IsA("BasePart") then return true end
    local n = string.lower(part.Name)
    if (part.Transparency or 0) >= 0.9 then
        if n == "humanoidrootpart" or n:find("hb") or n:find("hitbox") or n:find("box") then
            return true
        end
    end
    return false
end

local R6  = { "Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg" }
local R15 = {
    "Head","UpperTorso","LowerTorso",
    "LeftUpperArm","LeftLowerArm","LeftHand",
    "RightUpperArm","RightLowerArm","RightHand",
    "LeftUpperLeg","LeftLowerLeg","LeftFoot",
    "RightUpperLeg","RightLowerLeg","RightFoot"
}

local function CollectRigParts(char)
    local t = {}
    if not char or not char:IsDescendantOf(workspace) then return t end
    local isR15 = char:FindFirstChild("UpperTorso") or char:FindFirstChild("LowerTorso")
    local list  = isR15 and R15 or R6
    for _,name in ipairs(list) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") and (p.Transparency or 0) < 0.9 and not IsHBorProxy(p) then
            t[#t+1] = p
        end
    end
    return t
end

local function ComputeRigBox(char)
    local parts = CollectRigParts(char)
    local pad   = Config.ESP.Padding
    if #parts == 0 then
        local head = char and char:FindFirstChild("Head")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if head and hrp then
            local head2D = Camera:WorldToViewportPoint(head.Position)
            local root2D = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
            local h = math.abs(head2D.Y - root2D.Y) * 1.5
            local w = h/2
            return head2D.X - w/2 - pad, head2D.Y - h - pad, w + 2*pad, h + 2*pad
        end
        return nil
    end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false

    for _,part in ipairs(parts) do
        local cf, sz = part.CFrame, part.Size * 0.5
        local corners = {
            Vector3.new(-sz.X,-sz.Y,-sz.Z), Vector3.new( sz.X,-sz.Y,-sz.Z),
            Vector3.new(-sz.X, sz.Y,-sz.Z), Vector3.new( sz.X, sz.Y,-sz.Z),
            Vector3.new(-sz.X,-sz.Y, sz.Z), Vector3.new( sz.X,-sz.Y, sz.Z),
            Vector3.new(-sz.X, sz.Y, sz.Z), Vector3.new( sz.X, sz.Y, sz.Z),
        }
        for i=1,8 do
            local v,on = Camera:WorldToViewportPoint((cf * CFrame.new(corners[i])).Position)
            if on then
                any = true
                if v.X < minX then minX = v.X end
                if v.Y < minY then minY = v.Y end
                if v.X > maxX then maxX = v.X end
                if v.Y > maxY then maxY = v.Y end
            end
        end
    end

    if not any then return nil end
    minX, minY = minX - pad, minY - pad
    maxX, maxY = maxX + pad, maxY + pad
    return minX, minY, maxX-minX, maxY-minY
end

-- ============ Drawings per player ============

local function HidePack(g)
    if not g then return end
    g.Box.Visible = false
    g.Name.Visible = false
    g.Dist.Visible = false
    g.Tracer.Visible = false
end

local function NewESPFor(plr)
    if M.Drawings[plr] then return end

    local pack = {}
    pack.Box    = Drawing.new("Square"); pack.Box.Filled=false; pack.Box.Thickness=2
    pack.Name   = Drawing.new("Text");   pack.Name.Center=true; pack.Name.Size=16; pack.Name.Outline=true
    pack.Dist   = Drawing.new("Text");   pack.Dist.Center=true; pack.Dist.Size=14; pack.Dist.Outline=true
    pack.Tracer = Drawing.new("Line")

    HidePack(pack)
    M.Drawings[plr] = pack

    -- Re-apply la respawn
    if M.CharConns[plr] then M.CharConns[plr]:Disconnect() end
    M.CharConns[plr] = plr.CharacterAdded:Connect(function()
        -- nimic special aici, loopul va prinde noul Character
    end)
end

local function RemoveESPFor(plr)
    local pack = M.Drawings[plr]; if not pack then return end
    HidePack(pack)
    for _,d in pairs(pack) do pcall(function() d:Remove() end) end
    M.Drawings[plr] = nil
    if M.CharConns[plr] then pcall(function() M.CharConns[plr]:Disconnect() end); M.CharConns[plr] = nil end
end

local function EnsureHooks()
    if not M.PAdded then
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then NewESPFor(p) end
        end
        M.PAdded   = Players.PlayerAdded:Connect(function(p) if p ~= LocalPlayer then NewESPFor(p) end end)
        M.PRemoving= Players.PlayerRemoving:Connect(function(p) RemoveESPFor(p) end)
    end
end

-- ============ Loop management ============

local function SomethingOn()
    local E = Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function StartLoop()
    if M.RenderConn then return end
    M.RenderConn = RunService.RenderStepped:Connect(function()
        if not SomethingOn() then return end

        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local camPos     = Camera.CFrame.Position
        local E          = Config.ESP

        for plr, g in pairs(M.Drawings) do
            local char = plr.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")

            local ok   = char and hum and hum.Health > 0 and hrp and char:IsDescendantOf(workspace) and IsEnemy(plr, E.TeamCheck)

            if not ok then
                HidePack(g)
            else
                local x,y,w,h = ComputeRigBox(char)
                if not x or w < E.MinBoxW or h < E.MinBoxH then
                    HidePack(g)
                else
                    -- Box
                    if E.EnabledBox then
                        g.Box.Position = Vector2.new(x, y)
                        g.Box.Size     = Vector2.new(w, h)
                        g.Box.Color    = E.BoxColor
                        g.Box.Visible  = true
                    else
                        g.Box.Visible  = false
                    end

                    -- Name
                    if E.ShowName then
                        g.Name.Text     = plr.Name
                        g.Name.Position = Vector2.new(x + w/2, y - 18)
                        g.Name.Color    = Color3.new(1,1,1)
                        g.Name.Visible  = true
                    else
                        g.Name.Visible  = false
                    end

                    -- Distance
                    if E.ShowDistance then
                        local d = (camPos - hrp.Position).Magnitude
                        g.Dist.Text     = ("[%dm]"):format(d < 999 and math.floor(d) or 999)
                        g.Dist.Position = Vector2.new(x + w/2, y + h + 15)
                        g.Dist.Color    = Color3.fromRGB(150,200,255)
                        g.Dist.Visible  = true
                    else
                        g.Dist.Visible  = false
                    end

                    -- Tracer
                    if E.ShowTracers then
                        local rootV = Camera:WorldToViewportPoint(hrp.Position)
                        local fx = scrW * 0.5
                        local fy = (E.TracerOrigin == "Bottom" and scrH)
                               or (E.TracerOrigin == "Center" and scrH * 0.5)
                               or (scrH * 0.5) -- Crosshair ~ center
                        g.Tracer.From      = Vector2.new(fx, fy)
                        g.Tracer.To        = Vector2.new(rootV.X, rootV.Y)
                        g.Tracer.Thickness = E.TracerThickness
                        g.Tracer.Color     = E.TracerColor
                        g.Tracer.Visible   = true
                    else
                        g.Tracer.Visible   = false
                    end
                end
            end
        end
    end)
end

local function StopLoopAndHide()
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn = nil end
    for _,g in pairs(M.Drawings) do HidePack(g) end
    if M.PAdded then pcall(function() M.PAdded:Disconnect() end); M.PAdded=nil end
    if M.PRemoving then pcall(function() M.PRemoving:Disconnect() end); M.PRemoving=nil end
end

local function RecalcLoopState()
    if SomethingOn() then
        EnsureHooks()
        StartLoop()
    else
        StopLoopAndHide()
    end
end

-- ============ Public API ============

function M.Destroy()
    StopLoopAndHide()
    for plr in pairs(M.Drawings) do RemoveESPFor(plr) end
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited, Config, Library, Tab = true, cfg, lib, tab

    local G = Tab:AddLeftGroupbox("ESP")

    G:AddToggle("EnemyESP", {
        Text = "Enemy ESP", Default = false,
        Callback = function(v) Config.ESP.EnabledBox = v; RecalcLoopState() end
    })
    G:AddToggle("NameESP", {
        Text = "Show Names", Default = false,
        Callback = function(v) Config.ESP.ShowName = v; RecalcLoopState() end
    })
    G:AddToggle("DistanceESP", {
        Text = "Show Distance", Default = false,
        Callback = function(v) Config.ESP.ShowDistance = v; RecalcLoopState() end
    })
    G:AddToggle("TracerESP", {
        Text = "Show Tracers", Default = false,
        Callback = function(v) Config.ESP.ShowTracers = v; RecalcLoopState() end
    })
    G:AddToggle("TeamCheck", {
        Text = "Team Check", Default = Config.ESP.TeamCheck,
        Callback = function(v) Config.ESP.TeamCheck = v end
    })
    G:AddSlider("TracerThickness", {
        Text = "Tracer Thickness", Min = 1, Max = 5, Rounding = 0,
        Default = Config.ESP.TracerThickness,
        Callback = function(v) Config.ESP.TracerThickness = math.clamp(v, 1, 5) end
    })
    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"},
        Default = Config.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback = function(v) Config.ESP.TracerOrigin = v end
    })
end

return M
