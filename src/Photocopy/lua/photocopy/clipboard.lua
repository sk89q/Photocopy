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

photocopy.IgnoreClassKeys = {
    class = "Class",
    model = "Model",
    skin = "Skin",
    pos = "Pos",
    position = "Pos",
    ang = "Angle",
    angle = "Angle",
    physicsobjects = "PhysicsObjects",
}

------------------------------------------------------------
-- Clipboard
------------------------------------------------------------

local Clipboard = photocopy.CreateClass()
photocopy.Clipboard = Clipboard

--- Construct the clipboard.
-- @param offset Offset position
function Clipboard:__construct(offset)
    self.Offset = offset
    self.EntityData = {}
    self.ConstraintData = {}
    self.ConstraintIndex = {}
end

--- Creates an entity table to work on. This is very similar to
-- duplicator.CopyEntTable().
-- @param ent
-- @return Table
function Clipboard:CopyEntTable(ent)
    if ent.PreEntityCopy then ent:PreEntityCopy() end
    local entTable = table.Copy(ent:GetTable())
    if ent.PostEntityCopy then ent:PostEntityCopy() end
    
    -- Prepare the table like the duplicator library
    entTable.Pos = ent:GetPos()
    entTable.Angle = ent:GetAngles()
    entTable.Class = ent.ClassOverride or ent:GetClass()
    entTable.Model = ent:GetModel() or nil
    entTable.Skin = ent:GetSkin() or nil
    
    -- Prepare the physics objects
    entTable.PhysicsObjects = entTable.PhysicsObjects or {}
    
    for bone = 0, ent:GetPhysicsObjectCount() - 1 do
        local physObj = ent:GetPhysicsObjectNum(bone)
        
        if physObj:IsValid() then
            entTable.PhysicsObjects[bone] = entTable.PhysicsObjects[bone] or {}
            entTable.PhysicsObjects[bone].Pos = physObj:GetPos()
            entTable.PhysicsObjects[bone].Angle = physObj:GetAngle()
            entTable.PhysicsObjects[bone].Frozen = not physObj:IsMoveable()
        end
    end
    
    -- Flexes
    local num = ent:GetFlexNum()
    if num > 0 then
        entTable.Flex = entTable.Flex or {}
        for i = 0, num do
            entTable.Flex[i] = ent:GetFlexWeight(i)
        end
    end
    entTable.FlexScale = ent:GetFlexScale()
    
    if ent.OnEntityCopyTableFinish then
        ent:OnEntityCopyTableFinish(entTable)
    end
    
    return entTable
end

--- Prepare the table for an entity that will be saved.
-- @param ent Ent
-- @return Table
function Clipboard:PrepareEntityData(ent)
    local entTable = self:CopyEntTable(ent)
    
    -- This is what we will be saving
    local data = {
        Class = entTable.Class,
        Model = entTable.Model:gsub("\\+", "/"),
        Skin = entTable.Skin,
        PhysicsObjects = entTable.PhysicsObjects,
        EntityMods = entTable.EntityMods,
        BoneMods = entTable.BoneMods,
        LocalPos = entTable.Pos - self.Offset,
        LocalAngle = entTable.Angle,
        Flex = entTable.Flex,
    }
    
    -- Localize positions in the physics objects
    for _, physObj in pairs(data.PhysicsObjects) do
        physObj.LocalPos = physObj.Pos - self.Offset
        physObj.LocalAngle = physObj.Angle
        physObj.Pos = nil
        physObj.Angle = nil
    end
    
    -- Store parent
    if ValidEntity(ent:GetParent()) then
        data.SavedParentIdx = ent:GetParent():EntIndex()
    end
    
    local cls = duplicator.FindEntityClass(ent:GetClass())
    
    if cls then
        for _, argName in pairs(cls.Args) do
            -- Some keys are redundant; we are already automatically
            -- handling these (model, pos, ang) ourselves
            if not photocopy.IgnoreClassKeys[argName:lower()] then
                data[argName] = entTable[argName]
            end
        end
    end
    
    return data
end

--- Prepare a constraint data table for a constraint.
-- @param constr Constraint
-- @return Table
function Clipboard:PrepareConstraintData(constr)
    local constrData = {
        Type = constr.Type,
        length = constr.length, -- Fix
        CreateTime = constr.CreateTime, -- Order fix
        Entity = {}, -- Adv. Dupe compatible
    }
    
    local cls = duplicator.ConstraintType[constr.Type]
    
    if cls then
        for _, argName in pairs(cls.Args) do
            -- Entities and bones are handled later
            if not argName:match("Ent[0-9]?") and
                not argName:match("Bone[0-9]?") then
                constrData[argName] = constr[argName]
            end
        end
    end
    
    if constr.Ent and (constr.Ent:IsWorld() or constr.Ent:IsValid()) then
        constrData.Entity[1] = {
            Index = constr.Ent:EntIndex(),
            World = constr.Ent:IsWorld() or nil,
            Bone = constr.Bone,
        }
    else
        for i = 1, 6 do
            local id = "Ent" .. i
            local ent = constr[id]
            
            if ent and (ent:IsWorld() or ent:IsValid()) then
                local constrInfo = {
                    Index = ent:EntIndex(),
                    World = ent:IsWorld() or nil,
                    Bone = constr["Bone" .. i],
                    WPos = constr["WPos" .. i],
                    Length = constr["Length" .. i],
                }
                
                local lpos = constr["LPos" .. i]
                
                if ent:IsWorld() then
                    if lpos then
                        constrInfo.LPos = lpos - offset
                    else
                        constrInfo.LPos = offset
                    end
                else
                    constrInfo.LPos = lpos
                end
                
                constrData.Entity[i] = constrInfo
            end
        end
    end
    
    -- TODO: Arg clean up
    
    return constrData
end

--- Adds an entity (and its constrained entities) to this clipboard.
-- @param ent Entity
function Clipboard:Copy(ent)
    if not ValidEntity(ent) then return end
    if self.EntityData[ent:EntIndex()] then return end
    
    -- Build entity data from the entity
    self.EntityData[ent:EntIndex()] = self:PrepareEntityData(ent)
    
    if constraint.HasConstraints(ent) then
        local constraints = constraint.GetTable(ent)
        
        for k, constr in pairs(constraints) do
            local constrObj = constr.Constraint
            
            if not self.ConstraintIndex[constrObj] then
                self.ConstraintIndex[constrObj] = true
                
                table.insert(self.ConstraintData,
                    self:PrepareConstraintData(constr))
                
                -- Copy constrained entities
                for _, constrEnt in pairs(constr.Entity) do
                    self:Copy(constrEnt.Entity)
                end
            end
        end
    end
    
    table.SortByMember(self.ConstraintData, "CreateTime", function(a, b)
        return a > b
    end)
end

AccessorFunc(Clipboard, "EntityData", "EntityData")
AccessorFunc(Clipboard, "ConstraintData", "ConstraintData")
AccessorFunc(Clipboard, "Offset", "Offset")

local function MarkConstraint(ent)
    ent.CreateTime = CurTime()
end

hook.Add("OnEntityCreated", "PhotocopyConstraintMarker", function(ent)
    -- Is this a constraint?
    if ValidEntity(ent) and ent:GetClass():lower():match("^phys_") then
        timer.Simple(0, MarkConstraint, ent)
    end
end)