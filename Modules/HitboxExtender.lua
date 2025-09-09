local Players, RunService = game:GetService("Players"), game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local M = { Enabled=false, Conns={}, Maintain=nil, Originals=setmetatable({}, {__mode="k"}) }
local Config, Library, Tab

local function SameTeam(a,b)
    if not a or not b then return false end
    if a == b then return true end
    if a.Team and b.Team then return a.Team == b.Team end
    if a.TeamColor and b.TeamColor then return a.TeamColor == b.TeamColor end
    return false
end
local function IsEnemy(plr) return (plr ~= LocalPlayer) and (not SameTeam(LocalPlayer, plr)) end

local function remember(p) if M.Originals[p] then return end M.Originals[p] = { Size=p.Size, CanCollide=p.CanCollide, CastShadow=p.CastShadow, LocalTransparencyModifier=p.LocalTransparencyModifier } end
local function applySize(p, sz) remember(p); p.Size=sz; p.CanCollide=false; p.CastShadow=false end
local function resetPart(p) local o=M.Originals[p]; if not o then return end pcall(function() p.Size=o.Size; p.CanCollide=o.CanCollide; p.CastShadow=o.CastShadow; p.LocalTransparencyModifier=o.LocalTransparencyModifier end) M.Originals[p]=nil end
local function resetCharacter(char) if not char then return end for part,_ in pairs(M.Originals) do if part and part:IsDescendantOf(char) then resetPart(part) end end end
local function isInvisibleHB(part) if not part or not part:IsA("BasePart") then return false end if (part.Transparency or 0) < 0.9 then return false end local n=string.lower(part.Name); return n:find("hb") or n:find("hitbox") or n:find("box") end

local function applyToCharacter(plr, char)
    if not M.Enabled or not char then return end
    if not IsEnemy(plr) then resetCharacter(char); return end
    for _,part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and isInvisibleHB(part) then
            local sz = (string.lower(part.Name):find("head") and Config.HitboxExtender.HeadSize) or Config.HitboxExtender.BodySize
            applySize(part, sz)
        end
    end
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end
    table.insert(M.Conns, plr.CharacterAdded:Connect(function(ch) task.defer(function() applyToCharacter(plr, ch) end) end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("Team"):Connect(function() applyToCharacter(plr, plr.Character) end))
    table.insert(M.Conns, plr:GetPropertyChangedSignal("TeamColor"):Connect(function() applyToCharacter(plr, plr.Character) end))
    applyToCharacter(plr, plr.Character)
end
local function unhookAll() for _,c in ipairs(M.Conns) do pcall(function() c:Disconnect() end) end M.Conns={} end

function M.Init(cfg, lib, tab)
    Config, Library, Tab = cfg, lib, tab
    local G = Tab:AddRightGroupbox("Hitbox Extender")
    G:AddToggle("HBExt", { Text="Enable", Default=false, Callback=function(v)
        if v then
            if M.Enabled then return end
            M.Enabled=true
            for _,p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
            table.insert(M.Conns, Players.PlayerAdded:Connect(hookPlayer))
            table.insert(M.Conns, Players.PlayerRemoving:Connect(function(p) resetCharacter(p.Character) end))
            local t=0; M.Maintain = RunService.Heartbeat:Connect(function(dt) t+=dt; if t<0.2 then return end; t=0; for _,p in ipairs(Players:GetPlayers()) do local ch=p.Character; if ch then applyToCharacter(p,ch) end end end)
        else
            if not M.Enabled then return end
            M.Enabled=false
            if M.Maintain then pcall(function() M.Maintain:Disconnect() end); M.Maintain=nil end
            for prt,_ in pairs(M.Originals) do resetPart(prt) end
            unhookAll()
        end
    end })
end

function M.Destroy() if M.Maintain then pcall(function() M.Maintain:Disconnect() end); M.Maintain=nil end for prt,_ in pairs(M.Originals) do resetPart(prt) end unhookAll() end
return M
