-- La Passion • ESP (Box 2D static, Instances-only, anti-lag)
-- - Box: Frame + UIStroke (dimensiune fixă, centrat pe HRP)
-- - Name/Distance: TextLabel
-- - Tracer: Frame rotit (optimizat)
-- - TeamCheck: PERMANENT ON (fără buton)
-- - FPS: write-guard pe UI + smoothing + culling + update rate separat pt. text/tracer

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")
local Teams      = game:GetService("Teams")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============= Helpers =============
local function getUIRoot()
    local ok, ui = pcall(gethui)
    if ok and typeof(ui)=="Instance" and ui:IsA("Instance") then return ui end
    return CoreGui
end

local function round(v) return (v + (v>=0 and 0.5 or -0.5)) // 1 end

local function newLine(parent, color, thickness)
    local f = Instance.new("Frame")
    f.Name = "LP_Tracer"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromOffset(-9999, -9999)
    f.Size = UDim2.fromOffset(0, thickness or 1)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = color or Color3.fromRGB(255,165,0)
    f.ZIndex = 99998
    f.Visible = false
    f.Parent = parent
    return f
end

local function setLineFast(f, fromV2, toV2, thickness, color, cache)
    -- scriu doar dacă s-au schimbat
    local dx, dy = toV2.X - fromV2.X, toV2.Y - fromV2.Y
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 1 then
        if cache.trVis ~= false then f.Visible=false; cache.trVis=false end
        return
    end
    local rot = math.deg(math.atan2(dy, dx))
    if thickness and cache.trTh ~= thickness then
        f.Size = UDim2.fromOffset(f.Size.X.Offset, thickness); cache.trTh = thickness
    end
    if color and (not cache.trCol or cache.trCol.R~=color.R or cache.trCol.G~=color.G or cache.trCol.B~=color.B) then
        f.BackgroundColor3 = color; cache.trCol = color
    end
    if cache.trLen ~= len then
        f.Size = UDim2.fromOffset(len, f.Size.Y.Offset); cache.trLen = len
    end
    if cache.trPosX ~= fromV2.X or cache.trPosY ~= fromV2.Y then
        f.Position = UDim2.fromOffset(fromV2.X, fromV2.Y); cache.trPosX, cache.trPosY = fromV2.X, fromV2.Y
    end
    if cache.trRot ~= rot then
        f.Rotation = rot; cache.trRot = rot
    end
    if cache.trVis ~= true then f.Visible=true; cache.trVis=true end
end

-- team-check robust
local TEAM_KEYS = {"Team","team","TeamId","TeamNum","Allegiance","Faction","Side"}
local function normalizeTeamValue(v)
    if typeof(v)=="Instance" then
        if v:IsA("Team") then return v end
        if v:IsA("ObjectValue") then
            local vv=v.Value; if vv and vv:IsA("Team") then return vv end; return vv
        end
        if v:IsA("StringValue") or v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("BoolValue") then
            return v.Value
        end
        return nil
    end
    if type(v)=="string" and Teams then return Teams:FindFirstChild(v) or v end
    return v
end
local function readCustomTeamQuick(plr)
    for _,k in ipairs(TEAM_KEYS) do
        local a = plr:GetAttribute(k); if a~=nil then return normalizeTeamValue(a) end
    end
    local ch=plr.Character
    if ch then
        for _,k in ipairs(TEAM_KEYS) do
            local a = ch:GetAttribute(k); if a~=nil then return normalizeTeamValue(a) end
        end
        for _,k in ipairs(TEAM_KEYS) do
            local o = ch:FindFirstChild(k); if o then return normalizeTeamValue(o) end
        end
    end
    for _,k in ipairs(TEAM_KEYS) do
        local o = plr:FindFirstChild(k); if o then return normalizeTeamValue(o) end
    end
    return nil
end
local function isEnemy(plr)
    if not plr or plr==LP then return false end
    local a,b = LP.Team, plr.Team
    if a~=nil and b~=nil then return a~=b end
    local ca,cb = LP.TeamColor, plr.TeamColor
    if ca~=nil and cb~=nil then return ca~=cb end
    local xa,xb = readCustomTeamQuick(LP), readCustomTeamQuick(plr)
    if xa~=nil and xb~=nil then return xa~=xb end
    local na,nb = LP.Neutral, plr.Neutral
    if na~=nil and nb~=nil then return true end
    return true
end

-- ============= State =============
local M = {
    Inited=false, Config=nil, Tab=nil,
    Gui=nil, Conns={}, Packs={}, Cache={}, List={},
    Loop=nil, Accum=0, Frame=0
}

-- ============= Cache/Track =============
local function cacheChar(plr)
    local ch   = plr.Character
    local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp  = ch and ch:FindFirstChild("HumanoidRootPart")
    local head = ch and ch:FindFirstChild("Head")
    M.Cache[plr] = (ch and hum and hrp and head) and {ch=ch, hum=hum, hrp=hrp, head=head} or {ch=nil}
end

local function ensureGUI()
    if M.Gui then return end
    M.Gui = Instance.new("ScreenGui")
    M.Gui.Name = "LP_ESP_Screen"
    M.Gui.IgnoreGuiInset = true
    M.Gui.ResetOnSpawn   = false
    M.Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    M.Gui.Parent = getUIRoot()
end

local function ensurePack(plr)
    local p = M.Packs[plr]; if p then return p end
    ensureGUI()
    local E = M.Config.ESP
    local orange = E.BoxColor or Color3.fromRGB(255,165,0)

    -- Box fix (Frame + UIStroke)
    local box = Instance.new("Frame")
    box.Name = "LP_Box"
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.Position = UDim2.fromOffset(-9999,-9999)
    box.BackgroundTransparency = 1
    box.Size = UDim2.fromOffset(E.BoxWidthPx or 48, E.BoxHeightPx or 78)
    box.Visible = false
    box.ZIndex = 99996
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = E.BoxThickness or 2
    stroke.Color = orange
    stroke.Parent = box
    box.Parent = M.Gui

    -- Label
    local lbl = Instance.new("TextLabel")
    lbl.Name = "LP_Label"
    lbl.AnchorPoint = Vector2.new(0.5, 1)
    lbl.Position = UDim2.fromOffset(-9999,-9999)
    lbl.Size = UDim2.fromOffset(160, 18)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextScaled = true
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextStrokeTransparency = 0.5
    lbl.Visible = false
    lbl.ZIndex = 99997
    lbl.Parent = M.Gui

    -- Tracer
    local tr = newLine(M.Gui, E.TracerColor or orange, E.TracerThickness or 1)

    p = {
        Box=box, Stroke=stroke, Label=lbl, Tracer=tr,
        -- cache UI (evităm scrieri identice)
        last={ vis=false, posX=nil, posY=nil, labVis=false, labText=nil,
               trVis=false, trTh=nil, trCol=nil, trLen=nil, trPosX=nil, trPosY=nil, trRot=nil },
        -- smoothing state
        smX=nil, smY=nil
    }
    M.Packs[plr] = p
    table.insert(M.List, plr)
    return p
end

local function untrack(plr)
    local p = M.Packs[plr]
    if p then
        pcall(function() p.Box:Destroy() end)
        pcall(function() p.Label:Destroy() end)
        pcall(function() p.Tracer:Destroy() end)
        M.Packs[plr]=nil
    end
    M.Cache[plr]=nil
    for i=#M.List,1,-1 do if M.List[i]==plr then table.remove(M.List,i) end end
end

local function track(plr)
    if plr==LP then return end
    ensurePack(plr)
    cacheChar(plr)
    table.insert(M.Conns, plr.CharacterAdded:Connect(function() task.defer(function() cacheChar(plr) end) end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("Team"):Connect(function() end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("TeamColor"):Connect(function() end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("Neutral"):Connect(function() end))
end

-- ============= Loop =============
local TARGET_DT = 1/60 -- 60Hz pentru poziții (smooth)
local function anyOn()
    local E = M.Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function hidePack(p)
    if p.last.vis then p.Box.Visible=false; p.last.vis=false end
    if p.last.labVis then p.Label.Visible=false; p.last.labVis=false end
    if p.last.trVis then p.Tracer.Visible=false; p.last.trVis=false end
end

local function startLoop()
    if M.Loop then return end
    M.Loop = RunService.RenderStepped:Connect(function(dt)
        if not anyOn() then return end

        M.Accum += dt
        if M.Accum < TARGET_DT then return end
        M.Accum = 0
        M.Frame = (M.Frame + 1) % 120 -- ciclu 2s

        local E = M.Config.ESP
        local camPos = Camera.CFrame.Position
        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local originY = (E.TracerOrigin=="Bottom" and scrH) or (E.TracerOrigin=="Center" and scrH*0.5) or (scrH*0.5)
        local origin = Vector2.new(scrW*0.5, originY)
        local maxDist = E.MaxDistance or 2000
        local alpha   = E.SmoothAlpha or 0.35       -- smoothing (0..1)

        for i=1,#M.List do
            local plr = M.List[i]
            local c   = M.Cache[plr]
            local p   = M.Packs[plr]
            if not (c and p) then
                -- re-track dacă e cazul
                track(plr); c=M.Cache[plr]; p=M.Packs[plr]
            end

            local ch = c.ch
            local alive = ch and c.hum and c.hrp and c.head and c.hum.Health>0
            local enemy = alive and isEnemy(plr)

            if not enemy then
                hidePack(p)
            else
                local hrp = c.hrp
                local v3, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if (not onScreen) then
                    hidePack(p)
                else
                    local dist = (camPos - hrp.Position).Magnitude
                    if dist > maxDist then
                        hidePack(p)
                    else
                        -- === POSITION & BOX (update la 60Hz, cu smoothing & write-guard) ===
                        local tx = round(v3.X)
                        local ty = round(v3.Y)

                        -- smoothing 2D (exponential) – reduce micro-jitter
                        if not p.smX then p.smX, p.smY = tx, ty
                        else
                            p.smX = p.smX + (tx - p.smX) * alpha
                            p.smY = p.smY + (ty - p.smY) * alpha
                        end
                        local px, py = round(p.smX), round(p.smY)

                        if E.EnabledBox then
                            if p.last.posX ~= px or p.last.posY ~= py then
                                p.Box.Position = UDim2.fromOffset(px, py)
                                p.last.posX, p.last.posY = px, py
                            end
                            if not p.last.vis then p.Box.Visible=true; p.last.vis=true end
                            local col = E.BoxColor or Color3.fromRGB(255,165,0)
                            if not p.last.boxCol or p.last.boxCol~=col then
                                p.Stroke.Color = col; p.last.boxCol = col
                            end
                            local th = E.BoxThickness or 2
                            if p.last.boxTh ~= th then p.Stroke.Thickness=th; p.last.boxTh=th end
                        else
                            if p.last.vis then p.Box.Visible=false; p.last.vis=false end
                        end

                        -- === LABEL (10Hz: o data la 6 frame-uri ≈ 10/s) ===
                        if (E.ShowName or E.ShowDistance) then
                            if (M.Frame % 6)==0 then
                                local t1 = E.ShowName and plr.Name or ""
                                local t2 = ""
                                if E.ShowDistance then
                                    local d = math.floor(dist+0.5); if d>999 then d=999 end
                                    t2 = " ["..d.."m]"
                                end
                                local text = t1..t2
                                if p.last.labText ~= text then
                                    p.Label.Text = text; p.last.labText = text
                                end
                            end
                            local yOff = -(p.Box.Size.Y.Offset/2) - 12
                            local lpx, lpy = px, py + yOff
                            if p.last.labX ~= lpx or p.last.labY ~= lpy then
                                p.Label.Position = UDim2.fromOffset(lpx, lpy)
                                p.last.labX, p.last.labY = lpx, lpy
                            end
                            if not p.last.labVis then p.Label.Visible=true; p.last.labVis=true end
                        else
                            if p.last.labVis then p.Label.Visible=false; p.last.labVis=false end
                        end

                        -- === TRACER (30Hz: o data la 2 frame-uri) ===
                        if E.ShowTracers then
                            if (M.Frame % 2)==0 then
                                setLineFast(p.Tracer, origin, Vector2.new(px, py), E.TracerThickness or 1, E.TracerColor or (E.BoxColor or Color3.fromRGB(255,165,0)), p.last)
                            end
                        else
                            if p.last.trVis then p.Tracer.Visible=false; p.last.trVis=false end
                        end
                    end
                end
            end
        end
    end)
end

local function stopLoopIfIdle()
    if anyOn() then return end
    if M.Loop then pcall(function() M.Loop:Disconnect() end); M.Loop=nil end
    for _,p in pairs(M.Packs) do hidePack(p) end
end

-- ============= Public API =============
function M.Destroy()
    if M.Loop then pcall(function() M.Loop:Disconnect() end); M.Loop=nil end
    for _,c in ipairs(M.Conns) do pcall(function() c:Disconnect() end) end
    M.Conns = {}
    for plr in pairs(M.Packs) do untrack(plr) end
    if M.Gui then pcall(function() M.Gui:Destroy() end); M.Gui=nil end
    M.Packs, M.Cache, M.List = {}, {}, {}
    M.Accum, M.Frame = 0, 0
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited=true; M.Config=cfg; M.Tab=tab

    -- UI
    local G = tab:AddLeftGroupbox("ESP (instance)")
    G:AddToggle("EnemyESP", {
        Text="Enemy ESP (Box)", Default=false,
        Callback=function(v) cfg.ESP.EnabledBox=v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("NameESP", {
        Text="Show Names", Default=false,
        Callback=function(v) cfg.ESP.ShowName=v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("DistanceESP", {
        Text="Show Distance", Default=false,
        Callback=function(v) cfg.ESP.ShowDistance=v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("TracerESP", {
        Text="Show Tracers", Default=false,
        Callback=function(v) cfg.ESP.ShowTracers=v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddSlider("TracerThickness", {
        Text="Tracer Thickness", Min=1, Max=6, Rounding=0, Default=cfg.ESP.TracerThickness,
        Callback=function(v) cfg.ESP.TracerThickness = math.clamp(v,1,6) end
    })
    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"}, Default=cfg.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) cfg.ESP.TracerOrigin = v end
    })

    -- Hook players
    for _,p in ipairs(Players:GetPlayers()) do if p~=LP then track(p) end end
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(p) if p~=LP then track(p) end end))
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) untrack(p) end))
    table.insert(M.Conns, LP:GetPropertyChangedSignal("Team"):Connect(function() end))
    table.insert(M.Conns, LP:GetPropertyChangedSignal("TeamColor"):Connect(function() end))
    table.insert(M.Conns, LP:GetPropertyChangedSignal("Neutral"):Connect(function() end))
end

return M
