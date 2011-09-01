if SERVER then
    AddCSLuaFile("includes/modules/photocopy.lua")
    AddCSLuaFile("includes/modules/photocopy.util.lua")
    AddCSLuaFile("autorun/formats.lua")
end

local list = file.FindInLua("photocopy/formats/*.lua")
for _, f in pairs(list) do
    if SERVER then
        AddCSLuaFile(f)
    end
    include("photocopy/formats/" .. f)
end