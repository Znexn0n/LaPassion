local RunService, Stats = game:GetService("RunService"), game:GetService("Stats")
local M, Config, Library, Tab = { Conn=nil }, nil, nil, nil

function M.Init(cfg, lib, tab)
    Config, Library, Tab = cfg, lib, tab
    Library:SetWatermarkVisibility(false)
    local G = Tab:AddLeftGroupbox("Tools")
    G:AddToggle("Watermark", { Text="Watermark (FPS/Ping)", Default=false, Callback=function(v)
        if v then
            Library:SetWatermarkVisibility(true)
            local t=tick(); local c=0; local fps=60
            M.Conn = RunService.RenderStepped:Connect(function()
                c+=1; if (tick()-t)>=1 then fps=c; t=tick(); c=0 end
                Library:SetWatermark(("La Passion ツ | %s fps | %s ms"):format(math.floor(fps), math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())))
            end)
        else
            Library:SetWatermarkVisibility(false)
            if M.Conn then M.Conn:Disconnect(); M.Conn=nil end
        end
    end })
end

function M.Destroy() if M.Conn then pcall(function() M.Conn:Disconnect() end); M.Conn=nil end pcall(function() Library:SetWatermarkVisibility(false) end) end
return M
