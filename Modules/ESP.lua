-- La Passion • ESP (Instances-only) + TeamCheck permanent ON (fără buton)
-- Box: Highlight (AlwaysOnTop), Name/Dist: BillboardGui (CoreGui/gethui), Tracer: Frame 2D
-- API: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ========= Helpers =========
local function getUIRoot()
    local ok, ui = pcall(gethui)
    if ok and typeof(ui) == "Instance" and ui:IsA("Instance") then return ui end
    return CoreGui
end

local function newLine(parent, color, thickness)
    local f = Instance.new("Frame")
    f.Name = "LP_Tracer"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromOffset(-9999, -9999)
    f.Size = UDim2.fromOffset(0, thickness or 1)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = color or Color3.fromRGB(255,165,0)
    f.BackgroundTransparency = 0
    f.ZIndex = 99999
    f.Visible = false
    f.Parent = parent
    return f
end

local function setLine(f, fromV2, toV2, thickness, color)
    if color     then f.BackgroundColor3 = color     end
    if thickness then f.Size = UDim2.fromOffset(f.Size.X.Offset, thickness) end
    local diff = toV2 - fromV2
    local len  = diff.Magnitude
    if len < 1 then f.Visible = false; return end
    f.Visible  = true
    f.Size     = UDim2.fromOffset(len, thickness or 1)
    f.Position = UDim2.fromOffset(fromV2.X, fromV2.Y)
    f.Rotation = math.deg(math.atan2(diff.Y, diff.X))
end

local function center2DFromHRP(hrp)
    local v, on = Camera:WorldToViewportPoint(hrp.Position)
    if not on then return end
    return Vector2.new(v.X, v.Y)
end

-- TeamCheck permanent ON (fără UI)
local function isEnemy(plr)
    if not plr or plr == LocalPlayer then return false end

    -- 1) Team object (cel mai sigur)
    local a, b = LocalPlayer.Team, plr.Team
    if a ~= nil and b ~= nil then
        return a ~= b
    end

    -- 2) TeamColor (mai vechi / unele jocuri)
    local ca, cb = LocalPlayer.TeamColor, plr.TeamColor
    if ca ~= nil and cb ~= nil then
        return ca ~= cb
    end

    -- 3) Neutral (fallback: dacă unul e neutral, îl tratăm ca potențial inamic)
    local na, nb = LocalPlayer.Neutral, plr.Neutral
    if na ~= nil and nb ~= nil then
        if na and nb then return true end
        if na ~= nb then return true end
        return false
    end

    -- 4) Fallback final: consideră inamic dacă nu avem date
    return true
end

-- ========= State =========
local M = {
    Inited     = false,
    Config     = nil, Library=nil, Tab=nil,
    ScreenGui  = nil,
    Conns      = {},
    Packs      = {},   -- [player] = {Highlight, BBG, Label, Tracer}
    Cache      = {},   -- [player] = {ch, hum, hrp, head}
    Buckets    = { {}, {}, {}, {} },
    FrameIndex = 0, Accum = 0,
    Loop       = nil
}

-- ========= Cache / Track =========
local function cacheChar(plr)
    local ch   = plr.Character
    local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp  = ch and ch:FindFirstChild("HumanoidRootPart")
    local head = ch and ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then
        M.Cache[plr] = { ch=nil, hum=nil, hrp=nil, head=nil }
    else
        M.Cache[plr] = { ch=ch, hum=hum, hrp=hrp, head=head }
    end
end

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

    -- Highlight (parent: Workspace)
    local hl = Instance.new("Highlight")
    hl.Name = "LP_Highlight"
    hl.Enabled = false
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency   = 1
    hl.OutlineTransparency= 0
    hl.OutlineColor       = M.Config.ESP.BoxColor
    hl.Parent = Workspace
    pack.Highlight = hl

    -- Billboard (parent: CoreGui/gethui)
    local bbg = Instance.new("BillboardGui")
    bbg.Name = "LP_BBG"
    bbg.Size = UDim2.new(0, 220, 0, 36)
    bbg.AlwaysOnTop = true
    bbg.Enabled = false
    bbg.Parent  = getUIRoot()

    local lbl = Instance.new("TextLabel")
    lbl.Name = "LP_Label"
    lbl.Size = UDim2.fromScale(1,1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextScaled = true
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextStrokeTransparency = 0.5
    lbl.Text = ""
    lbl.Parent = bbg

    pack.BBG   = bbg
    pack.Label = lbl

    -- Tracer (Frame) în ScreenGui
    pack.Tracer = newLine(M.ScreenGui, M.Config.ESP.TracerColor, M.Config.ESP.TracerThickness)

    M.Packs[plr] = pack
    return pack
end

local function untrack(plr)
    local p = M.Packs[plr]
    if p then
        pcall(function() p.Highlight:Destroy() end)
        pcall(function() p.BBG:Destroy() end)
        pcall(function() p.Tracer:Destroy() end)
        M.Packs[plr] = nil
    end
    M.Cache[plr] = nil
    for b=1,4 do
        local t = M.Buckets[b]
        for i=#t,1,-1 do if t[i] == plr then table.remove(t,i) end end
    end
end

local function track(plr)
    if plr == LocalPlayer then return end
    ensurePack(plr)
    cacheChar(plr)
    table.insert(M.Buckets[(math.abs(plr.UserId)%4)+1], plr)
    table.insert(M.Conns, plr.CharacterAdded:Connect(function()
        task.defer(function() cacheChar(plr) end)
    end))
    -- reacționează la schimbări de echipă în jocurile care modifică dinamically
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
    p.Highlight.Enabled = false
    p.BBG.Enabled       = false
    p.Tracer.Visible    = false
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
            local c   = M.Cache[plr]
            if not c then track(plr); c = M.Cache[plr] end
            local p   = ensurePack(plr)

            local ch, hum, hrp, head = c.ch, c.hum, c.hrp, c.head
            local alive = ch and hum and hrp and head and hum.Health > 0
            local enemy = alive and isEnemy(plr)

            if not enemy then
                hidePack(p)
            else
                local center3D, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if not onScreen then
                    hidePack(p)
                else
                    -- BOX (Highlight) – enemy only
                    if E.EnabledBox then
                        p.Highlight.Adornee      = ch
                        p.Highlight.OutlineColor = E.BoxColor
                        p.Highlight.Enabled      = true
                    else
                        p.Highlight.Enabled      = false
                    end

                    -- NAME/DIST (Billboard) – enemy only
                    if E.ShowName or E.ShowDistance then
                        p.BBG.Adornee = head
                        local dist = (camPos - hrp.Position).Magnitude
                        local t1 = E.ShowName and plr.Name or ""
                        local t2 = E.ShowDistance and (" [".. (dist<999 and math.floor(dist) or 999) .."m]") or ""
                        p.Label.Text = t1 .. t2
                        p.BBG.Enabled = true
                    else
                        p.BBG.Enabled = false
                    end

                    -- TRACER (Frame) – enemy only
                    if E.ShowTracers then
                        setLine(p.Tracer, origin, Vector2.new(center3D.X, center3D.Y), E.TracerThickness, E.TracerColor)
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
    M.Inited=true; M.Config=cfg; M.Library=lib; M.Tab=tab

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

    -- hook players existenți + join/leave
    for _,p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then track(p) end end
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then track(p) end end))
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) untrack(p) end))

    -- reacționează când echipa ta se schimbă (ex: round swap)
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function() end))
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(function() end))
    table.insert(M.Conns, LocalPlayer:GetPropertyChangedSignal("Neutral"):Connect(function() end))
end

return M
