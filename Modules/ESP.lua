-- La Passion • ESP Module
-- Dual backend:
--   1) Drawing API (preferat): Square/Text/Line
--   2) Fallback Instances: Highlight + BillboardGui + tracer (Frame)
-- TeamCheck: ELIMINAT (OFF permanent) -> arată pe toți ceilalți jucători (nu pe tine)
-- API: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------

local function drawingAvailable()
    return (typeof(Drawing) == "table" and type(Drawing.new) == "function")
end

local function getUIRoot()
    local ok, ui = pcall(gethui)
    if ok and typeof(ui) == "Instance" and ui:IsA("Instance") then
        return ui
    end
    return CoreGui
end

local function isOther(plr) return plr ~= LocalPlayer end

-- 2D line cu Frame (pt. fallback Instances)
local function newLineFrame(parent, color, thickness)
    local f = Instance.new("Frame")
    f.Name = "LP_Tracer"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromOffset(-1000, -1000)
    f.Size = UDim2.fromOffset(0, thickness or 1)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = color or Color3.fromRGB(255,165,0)
    f.BackgroundTransparency = 0
    f.ZIndex = 99999
    f.Visible = false
    f.Parent = parent
    return f
end

local function setLineFrame(frame, fromV2, toV2, thickness, color)
    if color then frame.BackgroundColor3 = color end
    if thickness then frame.Size = UDim2.fromOffset(frame.Size.X.Offset, thickness) end
    local diff = toV2 - fromV2
    local len = diff.Magnitude
    if len < 1 then frame.Visible = false; return end
    frame.Visible = true
    frame.Size = UDim2.fromOffset(len, thickness or 1)
    frame.Position = UDim2.fromOffset(fromV2.X, fromV2.Y)
    frame.Rotation = math.deg(math.atan2(diff.Y, diff.X))
end

-- estimare box din Head+HRP (comportament clasic)
local function BoxFromHeadRoot(head, hrp, pad)
    pad = pad or 0
    local head2D, onH = Camera:WorldToViewportPoint(head.Position)
    local root2D, onR = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
    if not (onH and onR) then return end

    local h = (head2D.Y - root2D.Y) * 1.5
    if h < 0 then h = -h end
    local w = h / 2

    local pos2D = Camera:WorldToViewportPoint(hrp.Position)
    local x = pos2D.X - w/2 - pad
    local y = pos2D.Y - h/2 - pad
    return x, y, w + 2*pad, h + 2*pad, Vector2.new(pos2D.X, pos2D.Y)
end

----------------------------------------------------------------------
-- MODULE STATE
----------------------------------------------------------------------

local M = {
    Inited = false,
    Backend = "drawing",     -- "drawing" | "instance"
    RenderConn = nil,
    Conns = {},              -- diverse connections
    Packs = {},              -- [player] = pack
    Cache = {},              -- [player] = {char,hum,hrp,head}
    Buckets = { {}, {}, {}, {}},
    FrameIndex = 0,
    Accum = 0,
    ScreenGui = nil          -- doar pt. backend "instance" (tracere 2D)
}

local Config, Library, Tab

----------------------------------------------------------------------
-- PACKS (per-player) pentru ambele backend-uri
----------------------------------------------------------------------

local function hidePack(pack, backend)
    if backend == "drawing" then
        pack.Box.Visible    = false
        pack.Name.Visible   = false
        pack.Dist.Visible   = false
        pack.Tracer.Visible = false
    else
        if pack.Highlight then pack.Highlight.Enabled = false end
        if pack.BBG      then pack.BBG.Enabled      = false end
        if pack.Tracer   then pack.Tracer.Visible   = false end
    end
end

local function destroyPack(pack, backend)
    if not pack then return end
    if backend == "drawing" then
        for _,d in pairs(pack) do pcall(function() d:Remove() end) end
    else
        pcall(function() if pack.Highlight then pack.Highlight:Destroy() end end)
        pcall(function() if pack.BBG then pack.BBG:Destroy() end end)
        pcall(function() if pack.Tracer then pack.Tracer:Destroy() end end)
    end
end

local function ensurePack(plr)
    if M.Packs[plr] then return M.Packs[plr] end

    local backend = M.Backend
    local pack = {}

    if backend == "drawing" then
        -- Drawing objects
        pack.Box    = Drawing.new("Square"); pack.Box.Filled=false; pack.Box.Thickness=2; pack.Box.Visible=false; pack.Box.Color = Config.ESP.BoxColor
        pack.Name   = Drawing.new("Text");   pack.Name.Center=true; pack.Name.Size=16; pack.Name.Outline=true; pack.Name.Visible=false; pack.Name.Color=Color3.new(1,1,1)
        pack.Dist   = Drawing.new("Text");   pack.Dist.Center=true; pack.Dist.Size=14; pack.Dist.Outline=true; pack.Dist.Visible=false; pack.Dist.Color=Color3.fromRGB(150,200,255)
        pack.Tracer = Drawing.new("Line");   pack.Tracer.Visible=false; pack.Tracer.Thickness=Config.ESP.TracerThickness; pack.Tracer.Color=Config.ESP.TracerColor
    else
        -- Instances: Highlight + Billboard + Tracer Frame
        pack.Highlight = Instance.new("Highlight")
        pack.Highlight.Name = "LP_Highlight"
        pack.Highlight.Enabled = false
        pack.Highlight.FillTransparency = 1
        pack.Highlight.OutlineTransparency = 0.2
        pack.Highlight.OutlineColor = Config.ESP.BoxColor

        pack.BBG = Instance.new("BillboardGui")
        pack.BBG.Name = "LP_BBG"
        pack.BBG.Size = UDim2.new(0,200,0,40)
        pack.BBG.AlwaysOnTop = true
        pack.BBG.Enabled = false

        local lbl = Instance.new("TextLabel")
        lbl.Name = "LP_Label"
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.fromScale(1,1)
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextScaled = true
        lbl.TextColor3 = Color3.new(1,1,1)
        lbl.TextStrokeTransparency = 0.5
        lbl.Text = ""
        lbl.Parent = pack.BBG
        pack.Label = lbl

        if not M.ScreenGui then
            M.ScreenGui = Instance.new("ScreenGui")
            M.ScreenGui.Name = "LP_ESP_Screen"
            M.ScreenGui.IgnoreGuiInset = true
            M.ScreenGui.ResetOnSpawn = false
            M.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            M.ScreenGui.Parent = getUIRoot()
        end
        pack.Tracer = newLineFrame(M.ScreenGui, Config.ESP.TracerColor, Config.ESP.TracerThickness)
    end

    M.Packs[plr] = pack
    return pack
end

----------------------------------------------------------------------
-- CACHE / HOOKS
----------------------------------------------------------------------

local function cacheChar(plr)
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local head= ch and ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then
        M.Cache[plr] = {char=nil,hum=nil,hrp=nil,head=nil}
    else
        M.Cache[plr] = {char=ch,hum=hum,hrp=hrp,head=head}
    end
end

local function bucketIndexFor(plr) return (math.abs(plr.UserId) % 4) + 1 end

local function ensurePlayer(plr)
    if not isOther(plr) then return end
    ensurePack(plr)
    cacheChar(plr)
    local bi = bucketIndexFor(plr)
    table.insert(M.Buckets[bi], plr)

    -- respawn hook
    table.insert(M.Conns, plr.CharacterAdded:Connect(function()
        task.defer(function() cacheChar(plr) end)
    end))
end

local function untrackPlayer(plr)
    local pack = M.Packs[plr]
    if pack then destroyPack(pack, M.Backend) end
    M.Packs[plr] = nil
    M.Cache[plr] = nil
    -- scoate din buckets
    for b=1,4 do
        local t = M.Buckets[b]
        for i=#t,1,-1 do if t[i]==plr then table.remove(t,i) end end
    end
end

----------------------------------------------------------------------
-- LOOP
----------------------------------------------------------------------

local TARGET_DT = 1/60

local function anyToggleOn()
    local E = Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function startLoop()
    if M.RenderConn then return end
    M.RenderConn = RunService.RenderStepped:Connect(function(dt)
        if not anyToggleOn() then return end

        -- throttle global
        M.Accum += dt
        if M.Accum < TARGET_DT then return end
        M.Accum = 0

        -- context comun pentru cadru
        local E = Config.ESP
        M.FrameIndex = (M.FrameIndex % 4) + 1
        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local originY = (E.TracerOrigin=="Bottom" and scrH) or (E.TracerOrigin=="Center" and scrH*0.5) or (scrH*0.5)
        local origin = Vector2.new(scrW*0.5, originY)
        local camPos = Camera.CFrame.Position

        local bucket = M.Buckets[M.FrameIndex]
        for i=1,#bucket do
            local plr = bucket[i]
            local c = M.Cache[plr]
            if not c then ensurePlayer(plr); c = M.Cache[plr] end
            local pack = ensurePack(plr)

            local ch, hum, hrp, head = c.char, c.hum, c.hrp, c.head
            local alive = ch and hum and hrp and head and hum.Health > 0

            if not alive then
                hidePack(pack, M.Backend)
                -- recache ocazional
                if (tick() % 8) < 0.02 then cacheChar(plr) end
            else
                -- culling rapid: dacă HRP este off-screen, ascunde tot
                local _, onScr = Camera:WorldToViewportPoint(hrp.Position)
                if not onScr then
                    hidePack(pack, M.Backend)
                else
                    local x,y,w,h,center = BoxFromHeadRoot(head, hrp, Config.ESP.Padding)
                    if not x or w < Config.ESP.MinBoxW or h < Config.ESP.MinBoxH then
                        hidePack(pack, M.Backend)
                    else
                        if M.Backend == "drawing" then
                            -- BOX
                            if E.EnabledBox then
                                pack.Box.Position = Vector2.new(x, y)
                                pack.Box.Size     = Vector2.new(w, h)
                                pack.Box.Color    = E.BoxColor
                                pack.Box.Visible  = true
                            else pack.Box.Visible=false end
                            -- NAME
                            if E.ShowName then
                                pack.Name.Text     = plr.Name
                                pack.Name.Position = Vector2.new(x + w/2, y - 18)
                                pack.Name.Visible  = true
                            else pack.Name.Visible=false end
                            -- DIST
                            if E.ShowDistance then
                                local d = (camPos - hrp.Position).Magnitude
                                pack.Dist.Text     = ("[%dm]"):format(d < 999 and math.floor(d) or 999)
                                pack.Dist.Position = Vector2.new(x + w/2, y + h + 15)
                                pack.Dist.Visible  = true
                            else pack.Dist.Visible=false end
                            -- TRACER
                            if E.ShowTracers then
                                pack.Tracer.From      = origin
                                pack.Tracer.To        = center
                                pack.Tracer.Thickness = E.TracerThickness
                                pack.Tracer.Color     = E.TracerColor
                                pack.Tracer.Visible   = true
                            else pack.Tracer.Visible=false end
                        else
                            -- Instances
                            -- BOX -> Highlight
                            if E.EnabledBox then
                                pack.Highlight.Adornee = ch
                                pack.Highlight.OutlineColor = E.BoxColor
                                pack.Highlight.Enabled = true
                            else pack.Highlight.Enabled=false end
                            -- NAME/DIST -> Billboard
                            if E.ShowName or E.ShowDistance then
                                local d = (camPos - hrp.Position).Magnitude
                                local nameTxt = E.ShowName and plr.Name or ""
                                local distTxt = E.ShowDistance and (" ["..(d<999 and math.floor(d) or 999).."m]") or ""
                                pack.BBG.Adornee = head
                                pack.Label.Text  = nameTxt .. distTxt
                                pack.BBG.Enabled = true
                            else pack.BBG.Enabled=false end
                            -- TRACER -> Frame
                            if E.ShowTracers then
                                setLineFrame(pack.Tracer, origin, center, E.TracerThickness, E.TracerColor)
                            else pack.Tracer.Visible=false end
                        end
                    end
                end
            end
        end
    end)
end

local function stopLoopIfIdle()
    if anyToggleOn() then return end
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    for _,pack in pairs(M.Packs) do hidePack(pack, M.Backend) end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function M.Destroy()
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    for _,c in ipairs(M.Conns) do pcall(function() c:Disconnect() end) end
    M.Conns = {}
    for plr,pack in pairs(M.Packs) do destroyPack(pack, M.Backend) end
    M.Packs = {}
    M.Cache = {}
    M.Buckets = { {}, {}, {}, {} }
    if M.ScreenGui then pcall(function() M.ScreenGui:Destroy() end); M.ScreenGui=nil end
    M.FrameIndex = 0; M.Accum = 0
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited, Config, Library, Tab = true, cfg, lib, tab

    -- Alege backend
    M.Backend = drawingAvailable() and "drawing" or "instance"

    -- UI
    local G = Tab:AddLeftGroupbox("ESP (" .. M.Backend .. ")")

    G:AddToggle("EnemyESP", {
        Text="Enemy ESP (Box)", Default=false,
        Callback=function(v) Config.ESP.EnabledBox = v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("NameESP", {
        Text="Show Names", Default=false,
        Callback=function(v) Config.ESP.ShowName = v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("DistanceESP", {
        Text="Show Distance", Default=false,
        Callback=function(v) Config.ESP.ShowDistance = v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddToggle("TracerESP", {
        Text="Show Tracers", Default=false,
        Callback=function(v) Config.ESP.ShowTracers = v; if v then startLoop() else stopLoopIfIdle() end end
    })
    G:AddSlider("TracerThickness", {
        Text="Tracer Thickness", Min=1, Max=6, Rounding=0,
        Default=Config.ESP.TracerThickness,
        Callback=function(v) Config.ESP.TracerThickness = math.clamp(v,1,6) end
    })
    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"},
        Default=Config.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) Config.ESP.TracerOrigin = v end
    })

    -- global hooks: adaugă/șterge players
    for _,p in ipairs(Players:GetPlayers()) do if isOther(p) then ensurePlayer(p) end end
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(p) if isOther(p) then ensurePlayer(p) end end))
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) untrackPlayer(p) end))
end

return M
