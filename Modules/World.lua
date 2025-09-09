local Lighting, Workspace = game:GetService("Lighting"), game:GetService("Workspace")
local Camera = Workspace.CurrentCamera

local M, Config, Library, Tab = {}, nil, nil, nil
local CC

function M.Init(cfg, lib, tab)
    Config, Library, Tab = cfg, lib, tab
    local G = Tab:AddRightGroupbox("World")
    CC = Instance.new("ColorCorrectionEffect"); CC.Parent = Lighting
    CC.Saturation = Config.Visuals.Saturation/100; CC.Brightness = Config.Visuals.Brightness/35; CC.TintColor = Color3.new(1,1,1)
    G:AddSlider("CameraFOV", { Text="Camera Field Of View", Default=Config.Camera.DefaultFOV, Min=50, Max=120, Rounding=1, Callback=function(v) Camera.FieldOfView=v end })
end

function M.Destroy() pcall(function() if CC then CC:Destroy(); CC=nil end end); pcall(function() Camera.FieldOfView = Config.Camera.DefaultFOV end) end
return M
