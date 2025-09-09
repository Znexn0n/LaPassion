return {
    Camera = { DefaultFOV = 70 },
    Visuals = { Saturation = 100, Brightness = 1 },

    -- In Config.lua, în tabela ESP:
ESP = {
    EnabledBox     = false,
    ShowName       = false,
    ShowDistance   = false,
    ShowTracers    = false,
    -- TeamCheck    = true,   <-- SCOATE linia asta!
    TracerThickness= 1,
    TracerOrigin   = "Bottom",
    MinBoxW = 6, MinBoxH = 6, Padding = 2,
    BoxColor    = Color3.fromRGB(255,165,0),
    TracerColor = Color3.fromRGB(255,165,0)
},


    HitboxExtender = {
        Enabled  = false,
        BodySize = Vector3.new(13,13,13),
        HeadSize = Vector3.new(10,10,10)
    },

    Watermark = { Enabled = false }
}
