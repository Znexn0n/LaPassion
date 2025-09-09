-- ESP (Drawing API) • TeamCheck eliminat (OFF permanent) • FPS-stabil (throttle + stagger)
-- API: Init(cfg, lib, tab) / Destroy()

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
    Draw = {},                   -- [player] = { Box, Name, Dist, Tracer }
    Cache = {},                  -- [player] = { char, hum, hrp, head }
    Buckets = { {}, {}, {}, {}}, -- distribuim playerii pe 4 „bucket”-uri pt. update stagger
    FrameIndex = 0,
    Accum = 0
}

local Config, Library, Tab

-- ====== Safety ======
local function DrawingAvailable()
    return (typeof(Drawing) == "table" and type(Drawing.new) == "function")
end

-- ====== Utils ======
local function IsOtherPlayer(plr)
    return plr ~= LocalPlayer
end

local function HidePack(pack)
    if not pack then return end
    pack.Box.Visible    = false
    pack.Name.Visible   = false
    pack.Dist.Visible   = false
    pack.Tracer.Visible = false
end

local function RemovePack(plr)
    local p = M.Draw[plr]; if p then
        HidePack(p)
        for _,d in pairs(p) do pcall(function() d:Remove() end) end
        M.Draw[plr] = nil
    end
    if M.CharConns[plr] then pcall(function() M.CharConns[plr]:Disconnect() end); M.CharConns[plr]=nil end
    M.Cache[plr] = nil
    -- ștergem din bucket-uri
    for b=1,4 do
        local t = M.Buckets[b]
        for i=#t,1,-1 do if t[i] == plr then table.remove(t,i) end end
    end
end

local function CreatePack(plr)
    if M.Draw[plr] then return end
    local box    = Drawing.new("Square"); box.Filled=false; box.Thickness=2; box.Visible=false; box.Color=Config.ESP.BoxColor
    local name   = Drawing.new("Text");   name.Center=true; name.Size=16; name.Outline=true; name.Visible=false; name.Color=Color3.new(1,1,1)
    local dist   = Drawing.new("Text");   dist.Center=true; dist.Size=14; dist.Outline=true; dist.Visible=false; dist.Color=Color3.fromRGB(150,200,255)
    local tracer = Drawing.new("Line");   tracer.Visible=false; tracer.Thickness=Config.ESP.TracerThickness; tracer.Color=Config.ESP.TracerColor
    M.Draw[plr] = { Box=box, Name=name, Dist=dist, Tracer=tracer }
end

local function CacheChar(plr)
    local ch = plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local head= ch and ch:FindFirstChild("Head")
    if not (ch and hum and hrp and head) then
        M.Cache[plr] = { char=nil, hum=nil, hrp=nil, head=nil }
        return
    end
    M.Cache[plr] = { char=ch, hum=hum, hrp=hrp, head=head }
end

local function FastBoxFromHeadRoot(headPos3, rootPos3)
    -- primește deja poziții 3D; întoarce x,y,w,h și centrul pt. tracer
    local head2D, onH = Camera:WorldToViewportPoint(headPos3)
    local root2D, onR = Camera:WorldToViewportPoint(rootPos3)
    if not (onH and onR) then return end
    local height = (head2D.Y - root2D.Y) * 1.5
    if height < 0 then height = -height end
    local width  = height / 2

    local center2D = Vector2.new((head2D.X + root2D.X) * 0.5, (head2D.Y + root2D.Y) * 0.5 + height*0.15)
    local x = center2D.X - width/2
    local y = center2D.Y - height/2
    return x, y, width, height, center2D
end

-- ====== Bucketing ======
local function BucketIndexFor(plr)
    -- răspândim uniform (determinist) jucătorii în 4 bucket-uri
    return (math.abs(plr.UserId) % 4) + 1
end

local function EnsurePlayer(plr)
    if not IsOtherPlayer(plr) then return end
    CreatePack(plr)
    CacheChar(plr)
    local bi = BucketIndexFor(plr)
    table.insert(M.Buckets[bi], plr)

    if M.CharConns[plr] then M.CharConns[plr]:Disconnect() end
    M.CharConns[plr] = plr.CharacterAdded:Connect(function()
        task.defer(function()
            CacheChar(plr)
        end)
    end)
end

-- ====== Toggles ======
local function AnyToggleOn()
    local E = Config.ESP
    return E.EnabledBox or E.ShowName or E.ShowDistance or E.ShowTracers
end

-- ====== Loop (throttled, staggered) ======
local TARGET_DT = 1/60  -- ~60 Hz
local function StartLoop()
    if M.RenderConn then return end
    M.RenderConn = RunService.RenderStepped:Connect(function(dt)
        if not AnyToggleOn() then return end

        -- throttle global (dacă dt e foarte mic, nu actualizăm; reduce spike-urile)
        M.Accum += dt
        if M.Accum < TARGET_DT then return end
        M.Accum = 0

        -- setup comun pentru frame
        M.FrameIndex = (M.FrameIndex % 4) + 1
        local E = Config.ESP
        local scrW, scrH = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local originY = (E.TracerOrigin == "Bottom" and scrH)
                     or (E.TracerOrigin == "Center" and scrH*0.5)
                     or (scrH*0.5)
        local origin = Vector2.new(scrW*0.5, originY)
        local camPos = Camera.CFrame.Position

        -- actualizăm doar bucket-ul curent ⇒ sarcina e împărțită pe 4 cadre
        local bucket = M.Buckets[M.FrameIndex]
        for i = 1, #bucket do
            local plr = bucket[i]
            local pack = M.Draw[plr]
            local c = M.Cache[plr]
            if not (pack and c) then
                -- poate a intrat recent → re-ensure
                EnsurePlayer(plr)
                pack = M.Draw[plr]; c = M.Cache[plr]
            end

            local ch, hum, hrp, head = c.char, c.hum, c.hrp, c.head
            local ok = ch and hum and hrp and head and hum.Health > 0

            if not ok then
                HidePack(pack)
                -- încercăm recache ușor rar: la fiecare 8 update-uri pentru player
                if (tick() % 8) < 0.02 then CacheChar(plr) end
            else
                -- culling rapid: dacă HRP e offscreen, nu mai calculăm nimic
                local root2D, onScr = Camera:WorldToViewportPoint(hrp.Position)
                if not onScr then
                    HidePack(pack)
                else
                    local x,y,w,h,center = FastBoxFromHeadRoot(head.Position, hrp.Position - Vector3.new(0,3,0))
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

                        -- DIST
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

local function StopLoopIfIdle()
    if AnyToggleOn() then return end
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    for _,p in pairs(M.Draw) do HidePack(p) end
end

local function EnsureGlobalHooks()
    if M.PlayerAddedConn then return end
    -- inițializează toți existenții
    for _,p in ipairs(Players:GetPlayers()) do if IsOtherPlayer(p) then EnsurePlayer(p) end end
    M.PlayerAddedConn = Players.PlayerAdded:Connect(function(p) if IsOtherPlayer(p) then EnsurePlayer(p) end end)
    M.PlayerRemovingConn = Players.PlayerRemoving:Connect(function(p) RemovePack(p) end)
end

-- ====== Public ======
function M.Destroy()
    if M.RenderConn then pcall(function() M.RenderConn:Disconnect() end); M.RenderConn=nil end
    if M.PlayerAddedConn then pcall(function() M.PlayerAddedConn:Disconnect() end); M.PlayerAddedConn=nil end
    if M.PlayerRemovingConn then pcall(function() M.PlayerRemovingConn:Disconnect() end); M.PlayerRemovingConn=nil end
    for plr in pairs(M.CharConns) do pcall(function() M.CharConns[plr]:Disconnect() end) end
    M.CharConns = {}
    for plr in pairs(M.Draw) do RemovePack(plr) end
    M.Buckets = { {}, {}, {}, {} }
    M.Cache = {}
    M.FrameIndex = 0
    M.Accum = 0
end

function M.Init(cfg, lib, tab)
    if M.Inited then return end
    M.Inited, Config, Library, Tab = true, cfg, lib, tab

    if not DrawingAvailable() then
        warn("[La Passion][ESP] Drawing API indisponibil în acest executor.")
        local G = tab:AddLeftGroupbox("ESP (Drawing)")
        G:AddLabel("Drawing API indisponibil.")
        return
    end

    local G = Tab:AddLeftGroupbox("ESP (Drawing)")

    G:AddToggle("EnemyESP", {
        Text="Enemy ESP (Box)", Default=false,
        Callback=function(v)
            Config.ESP.EnabledBox = v
            if v then EnsureGlobalHooks(); StartLoop() else StopLoopIfIdle() end
        end
    })

    G:AddToggle("NameESP", {
        Text="Show Names", Default=false,
        Callback=function(v)
            Config.ESP.ShowName = v
            if v then EnsureGlobalHooks(); StartLoop() else StopLoopIfIdle() end
        end
    })

    G:AddToggle("DistanceESP", {
        Text="Show Distance", Default=false,
        Callback=function(v)
            Config.ESP.ShowDistance = v
            if v then EnsureGlobalHooks(); StartLoop() else StopLoopIfIdle() end
        end
    })

    G:AddToggle("TracerESP", {
        Text="Show Tracers", Default=false,
        Callback=function(v)
            Config.ESP.ShowTracers = v
            if v then EnsureGlobalHooks(); StartLoop() else StopLoopIfIdle() end
        end
    })

    -- ATENȚIE: TeamCheck a fost scos COMPLET la cererea ta (OFF permanent)

    G:AddSlider("TracerThickness", {
        Text="Tracer Thickness", Min=1, Max=5, Rounding=0,
        Default=Config.ESP.TracerThickness,
        Callback=function(v) Config.ESP.TracerThickness = math.clamp(v,1,5) end
    })

    G:AddDropdown("TracerOrigin", {
        Values={"Bottom","Center","Crosshair"},
        Default=Config.ESP.TracerOrigin, Multi=false, Text="Tracer Origin",
        Callback=function(v) Config.ESP.TracerOrigin = v end
    })
end

return M
