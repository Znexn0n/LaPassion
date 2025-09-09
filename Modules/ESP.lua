-- ESP (enemy-only), auto-update players, fără Visible Check
local Players, RunService, Workspace = game:GetService("Players"), game:GetService("RunService"), game:GetService("Workspace")
local LocalPlayer, Camera = Players.LocalPlayer, Workspace.CurrentCamera

local M = { Drawings = {}, LoopBound = false }
local Config, Library, Tab
local playerAddedConn, playerRemovingConn

local function SameTeam(a,b)
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
        if n:find("hb") or n:find("hitbox") or n:find("box") or n=="humanoidrootpart" then return true end
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
    if #parts == 0 then
        local head = char and char:FindFirstChild("Head")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if head and hrp then
            local pad = Config.ESP.Padding
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
    local any=false; local pad=Config.ESP.Padding
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
                any=true
                if v.X<minX then minX=v.X end
                if v.Y<minY then minY=v.Y end
                if v.X>maxX then maxX=v.X end
                if v.Y>maxY then maxY=v.Y end
            end
        end
    end
    if not any then return nil end
    minX, minY = minX - pad, minY - pad
    maxX, maxY = maxX + pad, maxY + pad
    return minX, minY, maxX-minX, maxY-minY
end

local function NewESPFor(plr)
    if M.Drawings[plr] then return end
    local box = Drawing.new("Square"); box.Filled=false; box.Thickness=2; box.Color=Config.ESP.BoxColor; box.Visible=false
    local name= Drawing.new("Text");   name.Size=16; name.Center=true; name.Outline=true; name.Color=Color3.new(1,1,1); name.Visible=false
    local dist= Drawing.new("Text");   dist.Size=14; dist.Center=true; dist.Outline=true; dist.Color=Color3.fromRGB(150,200,255); dist.Visible=false
    local tracer=Drawing.new("Line");  tracer.Thickness=Config.ESP.TracerThickness; tracer.Color=Config.ESP.TracerColor; tracer.Visible=false
    M.Drawings[plr] = { Box=box, Name=name, Dist=dist, Tracer=tracer }
end
local function RemoveESPFor(plr)
    local g = M.Drawings[plr]; if not g then return end
    for _,d in pairs(g) do pcall(function() d.Visible=false; d:Remove() end) end
    M.Drawings[plr]=nil
end

local function EnsureHooks()
    if playerAddedConn then return end
    for _,p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then NewESPFor(p) end end
    playerAddedConn    = Players.PlayerAdded:Connect(function(p) if p ~= LocalPlayer then NewESPFor(p) end end)
    playerRemovingConn = Players.PlayerRemoving:Connect(function(p) RemoveESPFor(p) end)
end

local function SomethingOn()
    local E = Config.ESP
    return (E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers)
end

function M.Bind()
    if M.LoopBound then return end
    M.LoopBound = true
    RunService:BindToRenderStep("LP_ESP", Enum.RenderPriority.Last.Value, function()
        if not SomethingOn() then return end
        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local camPos = Camera.CFrame.Position
        local E = Config.ESP

        for plr, g in pairs(M.Drawings) do
            local char = plr.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local ok   = char and hum and hum.Health>0 and hrp and IsEnemy(plr, E.TeamCheck) and char:IsDescendantOf(workspace)

            if not ok then
                g.Box.Visible=false; g.Name.Visible=false; g.Dist.Visible=false; g.Tracer.Visible=false
            else
                local x,y,w,h = ComputeRigBox(char)
                if not x or w<E.MinBoxW or h<E.MinBoxH then
                    g.Box.Visible=false; g.Name.Visible=false; g.Dist.Visible=false; g.Tracer.Visible=false
                else
                    if E.EnabledBox then
                        g.Box.Position=Vector2.new(x,y); g.Box.Size=Vector2.new(w,h)
                        g.Box.Color=E.BoxColor; g.Box.Visible=true
                    else g.Box.Visible=false end
                    if E.ShowName then
                        g.Name.Position=Vector2.new(x+w/2, y-18); g.Name.Text=plr.Name; g.Name.Visible=true
                    else g.Name.Visible=false end
                    if E.ShowDistance then
                        local d=(camPos-hrp.Position).Magnitude
                        g.Dist.Text=("[%dm]"):format(d<999 and math.floor(d) or 999)
                        g.Dist.Position=Vector2.new(x+w/2, y+h+15); g.Dist.Visible=true
                    else g.Dist.Visible=false end
                    if E.ShowTracers then
                        local rootV=Camera:WorldToViewportPoint(hrp.Position)
                        local fx=scrW*0.5
                        local fy=(E.TracerOrigin=="Bottom" and scrH) or (E.TracerOrigin=="Center" and scrH*0.5) or (scrH*0.5)
                        g.Tracer.From=Vector2.new(fx,fy); g.Tracer.To=Vector2.new(rootV.X, rootV.Y)
                        g.Tracer.Thickness=E.TracerThickness; g.Tracer.Color=E.TracerColor; g.Tracer.Visible=true
                    else g.Tracer.Visible=false end
                end
            end
        end
    end)
end

function M.UnbindIfIdle()
    if SomethingOn() then return end
    if M.LoopBound then
        RunService:UnbindFromRenderStep("LP_ESP"); M.LoopBound=false
        for _,g in pairs(M.Drawings) do g.Box.Visible=false; g.Name.Visible=false; g.Dist.Visible=false; g.Tracer.Visible=false end
        if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn=nil end
        if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn=nil end
    end
end

function M.Destroy()
    pcall(function() RunService:UnbindFromRenderStep("LP_ESP") end)
    M.LoopBound=false
    if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn=nil end
    if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn=nil end
    for plr in pairs(M.Drawings) do RemoveESPFor(plr) end
end

function M.Init(cfg, lib, tab)
    Config, Library, Tab = cfg, lib, tab
    local G = Tab:AddLeftGroupbox("ESP")
    G:AddToggle("EnemyESP",     { Text="Enemy ESP",    Default=false, Callback=function(v) cfg.ESP.EnabledBox=v; if v then EnsureHooks(); M.Bind() else M.UnbindIfIdle() end end })
    G:AddToggle("NameESP",      { Text="Show Names",   Default=false, Callback=function(v) cfg.ESP.ShowName=v;   if v then EnsureHooks(); M.Bind() else M.UnbindIfIdle() end end })
    G:AddToggle("DistanceESP",  { Text="Show Distance",Default=false, Callback=function(v) cfg.ESP.ShowDistance=v;if v then EnsureHooks(); M.Bind() else M.UnbindIfIdle() end end })
    G:AddToggle("TracerESP",    { Text="Show Tracers", Default=false, Callback=function(v) cfg.ESP.ShowTracers=v; if v then EnsureHooks(); M.Bind() else M.UnbindIfIdle() end end })
    G:AddToggle("TeamCheck",    { Text="Team Check",   Default=cfg.ESP.TeamCheck, Callback=function(v) cfg.ESP.TeamCheck=v end })
    G:AddSlider("TracerThickness", { Text="Tracer Thickness", Default=cfg.ESP.TracerThickness, Min=1, Max=5, Rounding=0, Callback=function(v) cfg.ESP.TracerThickness = math.clamp(v,1,5) end })
    G:AddDropdown("TracerOrigin",  { Values={"Bottom","Center","Crosshair"}, Default=cfg.ESP.TracerOrigin, Multi=false, Text="Tracer Origin", Callback=function(v) cfg.ESP.TracerOrigin=v end })
end

return M
