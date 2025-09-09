-- La Passion • ESP (Instances only)
-- Box: Highlight (AlwaysOnTop), Name/Dist: BillboardGui, Tracer: Frame 2D în ScreenGui
-- TeamCheck: SCOS COMPLET (OFF permanent) – arată pe toți ceilalți (nu pe tine)
-- API: Init(cfg, lib, tab) / Destroy()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local function getUIRoot()
    local ok, ui = pcall(gethui)
    if ok and typeof(ui)=="Instance" and ui:IsA("Instance") then return ui end
    return CoreGui
end

-- Linie 2D din Frame
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
    if color then f.BackgroundColor3 = color end
    if thickness then f.Size = UDim2.fromOffset(f.Size.X.Offset, thickness) end
    local diff = toV2 - fromV2
    local len  = diff.Magnitude
    if len < 1 then f.Visible=false; return end
    f.Visible  = true
    f.Size     = UDim2.fromOffset(len, thickness or 1)
    f.Position = UDim2.fromOffset(fromV2.X, fromV2.Y)
    f.Rotation = math.deg(math.atan2(diff.Y, diff.X))
end

-- Box 2D aproximat din Head+HRP (pt. label & tracer)
local function get2DBox(head, hrp)
    local head2D,on1 = Camera:WorldToViewportPoint(head.Position)
    local root2D,on2 = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
    if not (on1 and on2) then return end
    local h = math.abs(head2D.Y - root2D.Y) * 1.5
    local w = h/2
    local center = Camera:WorldToViewportPoint(hrp.Position)
    return Vector2.new(center.X, center.Y), w, h
end

-- ================= STATE =================
local M = {
    Inited=false, Config=nil, Library=nil, Tab=nil,
    ScreenGui=nil, Conns={}, Packs={}, Cache={},
    Buckets={{},{},{},{}}, FrameIndex=0, Accum=0, Loop=nil
}

-- [plr] = { ch, hum, hrp, head }
local function cacheChar(plr)
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local head= ch and ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then
        M.Cache[plr] = {ch=nil,hum=nil,hrp=nil,head=nil}
    else
        M.Cache[plr] = {ch=ch,hum=hum,hrp=hrp,head=head}
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

    -- Highlight (contur)
    local hl = Instance.new("Highlight")
    hl.Name = "LP_Highlight"
    hl.Enabled = false
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 1
    hl.OutlineTransparency = 0           -- contur clar
    hl.OutlineColor = Color3.fromRGB(255,165,0)
    pack.Highlight = hl

    -- Billboard (name + distance)
    local bbg = Instance.new("BillboardGui")
    bbg.Name = "LP_BBG"
    bbg.Size = UDim2.new(0, 220, 0, 36)
    bbg.AlwaysOnTop = true
    bbg.Enabled = false

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

    -- Tracer
    pack.Tracer = newLine(M.ScreenGui, Color3.fromRGB(255,165,0), 1)

    M.Packs[plr] = pack
    return pack
end

local function untrack(plr)
    local p = M.Packs[plr]; if p then
        pcall(function() p.Highlight:Destroy() end)
        pcall(function() p.BBG:Destroy() end)
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
    if plr == LocalPlayer then return end
    ensurePack(plr)
    cacheChar(plr)
    table.insert(M.Buckets[(math.abs(plr.UserId)%4)+1], plr)
    table.insert(M.Conns, plr.CharacterAdded:Connect(function() task.defer(function() cacheChar(plr) end) end))
end

-- ================= LOOP =================
local TARGET_DT = 1/60

local function anyOn()
    local E = M.Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

local function hidePack(pack)
    pack.Highlight.Enabled = false
    pack.BBG.Enabled = false
    pack.Tracer.Visible = false
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
            local pack = ensurePack(plr)

            local ch,hum,hrp,head = c.ch, c.hum, c.hrp, c.head
            local alive = ch and hum and hrp and head and hum.Health>0

            if not alive then
                hidePack(pack)
                if (tick()%8)<0.02 then cacheChar(plr) end
            else
                local _, onScr = Camera:WorldToViewportPoint(hrp.Position)
                if not onScr then
                    hidePack(pack)
                else
                    -- BOX (Highlight)
                    if E.EnabledBox then
                        pack.Highlight.Adornee = ch
                        pack.Highlight.OutlineColor = E.BoxColor
                        pack.Highlight.Enabled = true
                    else
                        pack.Highlight.Enabled = false
                    end

                    -- NAME/DIST (Billboard)
                    if E.ShowName or E.ShowDistance then
                        pack.BBG.Adornee = head
                        local d = (camPos - hrp.Position).Magnitude
                        local nameTxt = E.ShowName and plr.Name or ""
                        local distTxt = E.ShowDistance and (" ["..(d<999 and math.floor(d) or 999).."m]") or ""
                        pack.Label.Text  = nameTxt .. distTxt
                        pack.BBG.Enabled = true
                    else
                        pack.BBG.Enabled = false
                    end

                    -- TRACER (Frame)
                    if E.ShowTracers then
                        local center, w, h = get2DBox(head, hrp)
                        if center then
                            setLine(pack.Tracer, origin, center, E.TracerThickness, E.TracerColor)
                        else
                            pack.Tracer.Visible=false
                        end
                    else
                        pack.Tracer.Visible=false
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

-- ================= PUBLIC =================
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
        Callback=function(v) cfg.ESP.TracerThickness=math.clamp(v,1,6) end
    })
    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"}, Default=cfg.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) cfg.ESP.TracerOrigin=v end
    })

    -- hook-uri playeri existenți + join/leave
    for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then track(p) end end
    table.insert(M.Conns, Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then track(p) end end))
    table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) untrack(p) end))
end

return M
