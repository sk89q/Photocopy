-- Photocopy
-- Copyright (c) 2010 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

local photocopy = require("photocopy")

photocopy.RegisterEntityTableModifier("gmod_cameraprop", function(ply, ent, entTable, data)
    if ent:GetClass() == "gmod_cameraprop" then
        data.key = ent:GetKey()
    end
end)

local function CreateCamera(ply, pos, ang, key, locked, toggle, vel, avel, frozen, noCollide)
    local pid = ply:UniqueID()

    GAMEMODE.CameraList[pid] = GAMEMODE.CameraList[pid] or {}
    local cameraList = GAMEMODE.CameraList[ pid ]
    if ValidEntity(cameraList[key]) then
        cameraList[key]:Remove()
    end

    local camera = ents.Create("gmod_cameraprop")
    if not camera:IsValid() then return end

    camera:SetAngles(ply:EyeAngles())
    camera:SetPos(pos)
    camera:SetAngles(ang)
    camera:Spawn()
    camera:SetKey(key)
    camera:SetPlayer(ply)
    camera:SetLocked(locked)
    camera.toggle = toggle
    camera:SetTracking(NULL, Vector(0))
    
    if noCollide then
        local physObj = camera:GetPhysicsObject()
        if physObj:IsValid() then
            physObj:EnableCollisions(false)
        end
    end

    if toggle == 1 then
        numpad.OnDown(ply, key, "Camera_Toggle", camera)
    else
        numpad.OnDown(ply, key, "Camera_On", camera)
        numpad.OnUp(ply, key, "Camera_Off", camera)
    end

    cameraList[key] = camera
    
    return camera
end
duplicator.RegisterEntityClass("gmod_cameraprop", CreateCamera, "Pos", "Ang", "key", "locked", "toggle", "Vel", "aVel", "frozen", "nocollide")

photocopy.RegisterEntityTableModifier("CollisionGroupMod", function(ply, ent, entTable, data)
    -- The No Collide tool uses the CollisionGroup field right on the entity
    if entTable.CollisionGroup then
        data.EntityMods = data.EntityMods or {}
        data.EntityMods.CollisionGroupMod = entTable.CollisionGroup
    end
end)

photocopy.RegisterEntityModifier("CollisionGroupMod", function(ply, ent, group)
    if group == 19 or group == COLLISION_GROUP_WORLD then
        ent.CollisionGroup = COLLISION_GROUP_WORLD
    else
        ent.CollisionGroup = COLLISION_GROUP_NONE
    end
    
    -- The No Collide tool uses the CollisionGroup field right on the entity
    ent:SetCollisionGroup(ent.CollisionGroup)
end)


photocopy.RegisterEntityModifier("buoyancy", function(ply, ent, data)
    local ratio = data.Ratio
    
    local phys = ent:GetPhysicsObject()
    if phys:IsValid() then
        local ratio = math.Clamp(data.Ratio, -1000, 1000) / 100
        ent.BuoyancyRatio = ratio
        phys:SetBuoyancyRatio(ratio)
        phys:Wake()
        
        duplicator.StoreEntityModifier(ent, "buoyancy", data) 
    end
    
    return true
end)

photocopy.RegisterEntityModifier("mass", function(ply, ent, data)
    if data.Mass and data.Mass > 0 then
        local physObj = Entity:GetPhysicsObject()
        if physObj:IsValid() then
            physObj:SetMass(data.Mass)
        end
    end
    
    duplicator.StoreEntityModifier(ent, "mass", data)
end)

photocopy.RegisterEntityModifier("MassMod", function(ply, ent, data)
    if data.Mass and data.Mass > 0 then
        local physObj = Entity:GetPhysicsObject()
        if physObj:IsValid() then
            physObj:SetMass(data.Mass)
        end
    end

    duplicator.StoreEntityModifier(ent, "MassMod", data)
end)