-- La Passion • ESP (Box 2D static, Instances-only)
-- Box: Frame + UIStroke (în ScreenGui), mărime fixă, centrat pe HRP
-- Name/Distance: TextLabel (în ScreenGui)
-- Tracer: Frame 2D (în ScreenGui)
-- TeamCheck: PERMANENT ON (fără buton)
-- API: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")
local Teams      = game:GetService("Teams")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ========= Helpers =========
local function getUIRoot()
    local ok, ui = pcall(gethui)
    if ok and typeof(ui)=="Instance" and ui:IsA("Instance") then return ui end
    return CoreGui
end

-- linie 2D
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

local function setLine(f, fromV2, toV2, thickness, color)
    if color     then f.BackgroundColor3 = color end
    if thickness then f.Size = UDim2.fromOffset(f.Size.X.Offset, thickness) end
    local diff = toV2 - fromV2
    local len  = diff.Magnitude
    if len < 1 then f.Visible = false; return end
    f.Visible  = true
    f.Size     = UDim2.fromOffset(len, thickness or 1)
    f.Position = UDim2.fromOffset(fromV2.X, fromV2.Y)
    f.Rotation = math.deg(math.atan2(diff.Y, diff.X))
end

-- TeamCheck robust
local TEAM_KEYS = {"Team","team","TeamId","TeamNum","Allegiance","Faction","Side"}
local function normalizeTeamValue(v)
    if typeof(v)=="Instance" then
        if v:IsA("Team") then return v end
        if v:IsA("ObjectValue") then
            local vv=v.Value
            if vv and vv:IsA("Team") then return vv end
            return vv
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
    if not plr or plr==LocalPlayer then return false end
    local a,b = LocalPlayer.Team, plr.Team
    if a~=nil and b~=nil then return a~=b end
    local ca,cb = LocalPlayer.TeamColor, plr.TeamColor
    if ca~=nil and cb~=nil then return ca~=cb end
    local xa,xb = readCustomTeamQuick(LocalPlayer), readCustomTeamQuick(plr)
    if xa~=nil and xb~=nil then return xa~=xb end
    local na,nb = LocalPlayer.Neutral, plr.Neutral
    if na~=nil and nb~=nil then return true end
    return true
end

-- ========= State =========
local M = {
    Inited=false, Config=nil, Tab=nil,
    ScreenGui=nil, Conns={}, Packs={}, Cache={},
    Buckets={{},{},{},{}}, FrameIndex=0, Accum=0, Loop=nil
}

-- [plr] = {ch,hum,hrp,head}
local function cacheChar(plr)
    local ch   = plr.Character
    local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp  = ch and ch:FindFirstChild("HumanoidRootPart")
    local head = ch and ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then
        M.Cache[plr] = {ch=nil,hum=nil,hrp=nil,head=nil}
    else
        M.Cache[plr] = {ch=ch,hum=hum,hrp=hrp,head=head}
    end
end

-- creează box 2D static (Frame + UIStroke) + label + tracer, toate în ScreenGui
local function ensurePack(plr)
    if M.Packs[plr] then return M.Packs[plr] end

    if not M.ScreenGui then
        M.ScreenGui = Instance.new("ScreenGui")
        M.ScreenGui.Name = "LP_ESP_Screen"
        M.ScreenGui.IgnoreGuiInset = true
        M.ScreenGui.ResetOnSpawn   = false
        M.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        M.ScreenGui.Parent = getUIRoot()
    end

    local pack = {}

    -- Box
    local box = Instance.new("Frame")
    box.Name = "LP_Box"
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.BackgroundTransparency = 1
    -- mărime fixă (override din Config dacă există)
    local cfg = M.Config and M.Config.ESP or {}
    local BOX_W = cfg.BoxWidthPx  or 48
    local BOX_H = cfg.BoxHeightPx or 78
    box.Size = UDim2.fromOffset(BOX_W, BOX_H)
    box.Position = UDim2.fromOffset(-9999,-9999)
    box.Visible = false
    box.ZIndex = 99996

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = cfg.BoxThickness or 2
    stroke.Color = cfg.BoxColor or Color3.fromRGB(255,165,0)
    stroke.Parent = box

    box.Parent = M.ScreenGui
    pack.Box = box
    pack.Stroke = stroke

    -- Name/Distance label
    local label = Instance.new("TextLabel")
    label.Name = "LP_Label"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Size = UDim2.fromOffset(160, 18)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextScaled = true
    label.TextColor3 = Color3.new(1,1,1)
    label.TextStrokeTransparency = 0.5
    label.Text = ""
    label.Position = UDim2.fromOffset(-9999,-9999)
    label.Visible = false
    label.ZIndex = 99997
    label.Parent = M.ScreenGui
    pack.Label = label

    -- Tracer
    pack.Tracer = newLine(M.ScreenGui, cfg.TracerColor or Color3.fromRGB(255,165,0), cfg.TracerThickness or 1)

    M.Packs[plr] = pack
    return pack
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
    for b=1,4 do
        local t=M.Buckets[b]
        for i=#t,1,-1 do if t[i]==plr then table.remove(t,i) end end
    end
end

local function track(plr)
    if plr==LocalPlayer then return end
    ensurePack(plr)
    cacheChar(plr)
    table.insert(M.Buckets[(math.abs(plr.UserId)%4)+1], plr)
    table.insert(M.Conns, plr.CharacterAdded:Connect(function() task.defer(function() cacheChar(plr) end) end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("Team"):Connect(function() end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("TeamColor"):Connect(function() end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("Neutral"):Connect(function() end))
end

-- ========= Loop =========
local TARGET_DT = 1/60
local function anyOn()
    local E = M.Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function hidePack(p)
    p.Box.Visible   = false
    p.Label.Visible = false
    p.Tracer.Visible= false
end

local function startLoop()
    if M.Loop then return end
    M.Loop = RunService.RenderStepped:Connect(function(dt)
        if not anyOn() then return end
        M.Accum += dt
        if M.Accum < TARGET_DT then return end
        M.Accum = 0

        local E = M.Config.ESP
        M.FrameIndex = (M.FrameIndex % 4) + 1

        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local originY = (E.TracerOrigin=="Bottom" and scrH) or (E.TracerOrigin=="Center" and scrH*0.5) or (scrH*0.5)
        local origin = Vector2.new(scrW*0.5, originY)
        local camPos = Camera.CFrame.Position

        local bucket = M.Buckets[M.FrameIndex]
        for i=1,#bucket do
            local plr = bucket[i]
            local c = M.Cache[plr]
            if not c then track(plr); c=M.Cache[plr] end
            local p = ensurePack(plr)

            local ch,hum,hrp,head = c.ch, c.hum, c.hrp, c.head
            local alive = ch and hum and hrp and head and hum.Health>0
            local enemy = alive and isEnemy(plr)

            if not enemy then
                hidePack(p)
            else
                local v2, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if not onScreen then
                    hidePack(p)
                else
                    -- BOX 2D static (fix pe HRP)
                    if E.EnabledBox then
                        p.Box.Position = UDim2.fromOffset(v2.X, v2.Y)
                        p.Stroke.Color = E.BoxColor
                        p.Stroke.Thickness = E.BoxThickness or 2
                        p.Box.Visible = true
                    else
                        p.Box.Visible = false
                    end

                    -- NAME + DIST (TextLabel deasupra box-ului)
                    if E.ShowName or E.ShowDistance then
                        local d = (camPos - hrp.Position).Magnitude
                        local t1 = E.ShowName and plr.Name or ""
                        local t2 = E.ShowDistance and (" [".. (d<999 and math.floor(d) or 999) .."m]") or ""
                        p.Label.Text = t1 .. t2
                        -- poziționez puțin deasupra cutiei
                        local yOff = -(p.Box.Size.Y.Offset/2) - 12
                        p.Label.Position = UDim2.fromOffset(v2.X, v2.Y + yOff)
                        p.Label.Visible  = true
                    else
                        p.Label.Visible  = false
                    end

                    -- TRACER (origin -> HRP)
                    if E.ShowTracers then
                        setLine(p.Tracer, origin, Vector2.new(v2.X, v2.Y), E.TracerThickness, E.TracerColor)
                    else
                        p.Tracer.Visible = false
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

-- ========= Public =========
function M.Destroy()
    if M.Loop then pcall(function() M.Loop:Disconnect() end); M.Loop=nil end
    for _,c in ipairs(M.Conns) do pcall(function() c:Disconnect() end) end
    M.Conns = {}
    for plr in pairs(M.Packs) do untrack(plr) end
    if M.ScreenGui then pcall(function() M.ScreenGui:Destroy() end); M.ScreenGui=nil end
    M.Buckets={{},{},{},{}}
    M.Cache={}
    M.FrameIndex=0; M.Accum=0
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited=true; M.Config=cfg; M.Tab=tab

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

    -- hook players
    for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then track(p) end end
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then track(p) end end))
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) untrack(p) end))
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function() end))
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(function() end))
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("Neutral"):Connect(function() end))
end

return M
