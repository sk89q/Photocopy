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


local putil = require("photocopy.util")
local hook = hook

local CastVector = putil.CastVector
local CastAngle = putil.CastAngle
local CastTable = putil.CastTable
local IsValidModel = util.IsValidModel
local QuickTrace = util.QuickTrace
local CRC = util.CRC

local SERVER = SERVER
local CLIENT = CLIENT

module("photocopy",package.seeall )

EntityModifiers = {}
--BoneModifiers = {}
EntityTableModifiers = {}

IgnoreClassKeys = {
    class = "Class",
    model = "Model",
    skin = "Skin",
    pos = "Pos",
    position = "Pos",
    ang = "Angle",
    angle = "Angle",
    physicsobjects = "PhysicsObjects",
}

--- Function to get a registered Photocopy reader.
-- @param fmt Format
function GetReader(fmt)
    local fmtTable = list.Get("PhotocopyFormats")[fmt]
    if not fmtTable then return nil end
    return fmtTable.ReaderClass
end

--- Function to get a registered Photocopy writer.
-- @param fmt Format
function GetWriter(fmt)
    local fmtTable = list.Get("PhotocopyFormats")[fmt]
    if not fmtTable then return nil end
    return fmtTable.WriterClass
end

--- Register a format.
-- @param id ID of the format
-- @param readerClass Reader class, can be nil
-- @param writerClass Writer class, can be nil
function RegisterFormat(id, readerCls, writerClass)
    list.Set("PhotocopyFormats", id, {
        ReaderClass = readerCls,
        WriterClass = writerClass,
    })
end

-- Register an entity modifier. Entity modifiers registered with
-- Photocopy are lower priority than ones registered with
-- the duplicator. Entity modifiers registered directly with Photocopy
-- are for compatibility fixes.
function RegisterEntityModifier(id, func)
    EntityModifiers[id] = func
end

-- Register a bone modifier. Bone modifiers registered with
-- Photocopy are lower priority than ones registered with
-- the duplicator. Bone modifiers registered directly with Photocopy
-- are for compatibility fixes.
--[[
function RegisterBoneModifier(id, func)
    BoneModifiers[id] = func
end
]]--

-- Register a entity table modifier. These are called as the table for
-- each entity is built, allowing for compatibility fixes.
function RegisterEntityTableModifier(id, func)
    EntityTableModifiers[id] = func
end

------------------------------------------------------------
-- Clipboard
------------------------------------------------------------

Clipboard = putil.CreateClass()

--- Construct the clipboard.
-- @param offset Offset position
function Clipboard:__construct(offset)
    if not offset then
        error("Offset for copy is required" , 2)
    end
    self.Offset = offset
    self.EntityData = {}
    self.ConstraintData = {}
    self.ConstraintIndex = {}
    self.Filter = nil
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
    
    -- Toybox
    entTable.ToyboxID = ent:GetToyboxID()
	
    -- For entities that are a part of the map
    -- Ignoring this for now
    --[[
    if ent:CreatedByMap() then
		entTable.MapCreationID = ent:MapCreationID()
	end
    ]]--
    
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
        FlexScale = entTable.FlexScale,
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
            if not IgnoreClassKeys[argName:lower()] then
                data[argName] = entTable[argName]
            end
        end
    end
    
    self:ApplyEntityTableModifiers(ent, entTable, data)
    
    return data
end

--- Apply entity table modifiers. 
-- @param ent
function Clipboard:ApplyEntityTableModifiers(ent, entTable, data)
    for id, func in pairs(EntityTableModifiers) do
        local ret, err = pcall(func, self.Player, ent, entTable, data)
        
        if not ret then
            self:Warn("entity_table_modifier_error", id, ent:EntIndex(), err)
        end
    end
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
    if not ValidEntity(ent) then 
        error("Invalid entity given to copy")
    end
    if self.EntityData[ent:EntIndex()] then return end
    
    -- Check filter
    if self.Filter and not self.Filter:CanCopyEntity(ent) then return end
    
    -- Build entity data from the entity
    local data = self:PrepareEntityData(ent)
    if self.Filter and not self.Filter:CanCopyEntityData(data) then return end
    self.EntityData[ent:EntIndex()] = data
    
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
                    if ValidEntity(constrEnt.Entity) then
                        self:Copy(constrEnt.Entity)
                    end
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
AccessorFunc(Clipboard, "Filter", "Filter")

local function MarkConstraint(ent)
    ent.CreateTime = CurTime()
end

hook.Add("OnEntityCreated", "PhotocopyConstraintMarker", function(ent)
    -- Is this a constraint?
    if ValidEntity(ent) and ent:GetClass():lower():match("^phys_") then
        timer.Simple(0, MarkConstraint, ent)
    end
end)

--- Function to override duplication for prop_physics. This version has
-- no effect, which is the main advantage. This is largely copied from sandbox.
-- @param ply
-- @param pos
-- @param model
-- @param physObj
-- @param data Entity data

local function PropClassFunction(ply, pos, ang, model, physObjs, data)
    data.Pos = pos
    data.Angle = ang
    data.Model = model
    
    if not gamemode.Call("PlayerSpawnProp", ply, model) then return end
    
    local ent = ents.Create("prop_physics")
    duplicator.DoGeneric(ent, data)
    
    ent:Spawn()
    ent:Activate()
    
    duplicator.DoGenericPhysics(ent, ply, data)
    duplicator.DoFlex(ent, data.Flex, data.FlexScale)
    
    gamemode.Call("PlayerSpawnedProp", ply, model, ent)
    
    FixInvalidPhysicsObject(ent)
    
    return ent
end

------------------------------------------------------------
-- Paster
------------------------------------------------------------

CreateConVar("photocopy_paste_spawn_rate", "5", { FCVAR_ARCHIVE })
CreateConVar("photocopy_paste_setup_rate", "20", { FCVAR_ARCHIVE })
CreateConVar("photocopy_paste_constrain_rate", "10", { FCVAR_ARCHIVE })

Paster = putil.CreateClass(putil.IterativeProcessor)

--- Construct the Paster. Currently the angle to paste at cannot have a
-- non-zero pitch or roll, as some entities will spawn with an incorrect
-- orientation (the cause is not yet pinpointed).
-- @param clipboard Clipboard
-- @param ply Player
-- @param originPos Position to paste at
-- @param originAng Angle to paste at
function Paster:__construct(clipboard, ply, originPos, originAng)
    putil.IterativeProcessor.__construct(self)
    
    self.EntityData = table.Copy(clipboard.EntityData)
    self.ConstraintData = table.Copy(clipboard.ConstraintData)
    self.Player = ply
    self.Pos = originPos
    self.Ang = originAng
    
    self.SpawnFrozen = false
    self.NoConstraints = false
    self.Filter = nil
    self.SpawnRate = GetConVar("photocopy_paste_spawn_rate"):GetInt()
    self.PostSetupRate = GetConVar("photocopy_paste_setup_rate"):GetInt()
    self.ConstrainRate = GetConVar("photocopy_paste_constrain_rate"):GetInt()
    
    self.CreatedEntsMap = {}
    self.CreatedEnts = {}
    
    self.CurIndex = nil
    self:SetNext(0, self._Spawn)
    
    self:CreateHelperEnt()
end

--- Transform a position and angle according to the offsets. This function
-- converts all the local positions and angles to their actual new positions
-- and angles.
-- @param pos
-- @param ang
-- @return Transformed position
-- @return Transformed angle
function Paster:Transform(pos, ang)
    return LocalToWorld(pos, ang, self.Pos, self.Ang)
end

--- Check to make sure that this entity can be created. This function can
-- be overrided to control what can be created before the entity is actually
-- created. The passed table can also be modified safely.
-- @param entData
-- @return Boolean indicating whether the entity can be created
function Paster:CanCreateEntity(entData)
    if type(entData.Class) ~= 'string' then return false end
    if entData.Class == "" then return false end
    
    if not self.Filter then return true end
    //PrintTable(self.Filter)
    return self.Filter:CanCreateEntity(entData)
end

--- After the entity is created, this function can be used to undo the entity.
-- Return true if the entity should continue existing, otherwise return
-- false to have the entity removed.
-- @param ply
-- @param ent
-- @param entData entity table
-- @return Boolean indicating whether the entity can be created
function Paster:CanAllowEntity(ent, entData)
    if not self.Filter then return true end
    return self.Filter:CanAllowEntity(ent, entData)
end

--- Check to see whether this constraint can be created. Return false in
-- this function to disable. The constraint data table can also be modified.
function Paster:CanCreateConstraint(constrData)
    if not self.Filter then return true end
    return self.Filter:CanCreateConstraint(constrData)
end

--- Apply entity modifiers. The duplicator's ApplyEntityModifiers() will
-- fail on a bad entity modifier function, but this one will log
-- individual errors to the paster log.
-- @param ent
function Paster:ApplyEntityModifiers(ent)
    -- Lower priority modifiers of Photocopy
    for type, func in pairs(EntityModifiers) do
        -- Skip ones that are registered with the duplicator
        if not duplicator.EntityModifiers[type] and ent.EntityMods[type] then
            local ret, err = pcall(func, self.Player, ent, ent.EntityMods[type])
            
            if not ret then
                self:Warn("entity_photocopy_modifier_error", type, ent:EntIndex(), err)
            end
        end
    end
    
    for type, func in pairs(duplicator.EntityModifiers) do
        if ent.EntityMods[type] then
            local ret, err = pcall(func, self.Player, ent, ent.EntityMods[type])
            
            if not ret then
                self:Warn("entity_modifier_error", type, ent:EntIndex(), err)
            end
        end
    end
end

--- Apply bone modifiers. See ApplyEntityModifiers().
-- @param ent
function Paster:ApplyBoneModifiers(ent)
    for type, func in pairs(duplicator.BoneModifiers) do
        for bone, args in pairs(ent.PhysicsObjects) do
            if ent.BoneMods[bone] and ent.BoneMods[bone][type] then
                local physObj = ent:GetPhysicsObjectNum(bone)
                
                if ent.PhysicsObjects[bone] then
                    local ret, err = pcall(func, self.Player, ent, bone,
                                           physObj, ent.BoneMods[bone][type])
                    if not ret then
                        self:Warn("bone_modifier_error", type, ent:EntIndex(), err)
                    end
                end
            end
        end
    end
end

--- Restore the position and angle values of the entity data table. Because
-- this modifies the passed table, a copy of the table is advised (if
-- required). The Model and Skin keys are also casted to their respective types.
-- @param entData
function Paster:PrepareEntityData(entData)
    local pos, ang = self:Transform(CastVector(entData.LocalPos),
                                    CastAngle(entData.LocalAngle))
    entData.Pos = pos
    entData.Angle = ang
    -- Remove keys
    entData.LocalPos = nil
    entData.LocalAngle = nil
    
    -- Do the same for the physics objects
    if entData.PhysicsObjects then
        for index, physObj in pairs(entData.PhysicsObjects) do
            local pos, ang = self:Transform(CastVector(physObj.LocalPos),
                                            CastAngle(physObj.LocalAngle))
            physObj.Pos = pos
            physObj.Angle = ang
            physObj.LocalPos = nil
            physObj.LocalAngle = nil
        end
    end
    
    entData.Model = tostring(entData.Model)
    entData.Skin = tonumber(entData.Skin) or 0
end

--- Create an entity from entity data.
-- @param entData
-- @return Entity or nil
function Paster:CreateEntity(entData)
    local cls = duplicator.FindEntityClass(entData.Class)
    
    -- If the entity doesn't have a special saving routine, we can create
    -- it generically
    if not cls then
        return self:CreateGenericEntity(entData)
    end
    
    local factory = cls.Func
    local args = {}
    
    -- Using our own prop_physics factory function that doesn't have the effect
    if entData.Class == "prop_physics" then
        if not IsValidModel(entData.Model) then
            self:Warn("missing_model", entData.Model)
            return nil
        end
        
        factory = PropClassFunction
    end
    
    -- Get class arguments
    for _, argName in ipairs(cls.Args) do
        local lowerArgName = argName:lower()
        local newArgName = IgnoreClassKeys[lowerArgName] and IgnoreClassKeys[lowerArgName] or argName
        local val = nil
        
        if argName == "Data" then -- Duplicator has this special key
            val = entData
        elseif newArgName then
            val = entData[newArgName]
        else
            val = entData[argName]
        end
        
        -- Legacy duplicator compatibility
        if val == nil then
            val = false
        end
        
        table.insert(args, val)
    end
    
    local ret, res = pcall(factory, self.Player,
                           unpack(args, 1, table.maxn(args)))
    
    if ret then
        return res
    else
        self:Warn("entity_factory_error", entData.Class, res)
        return nil
    end
end 

--- Create a generic entity. This is called for entities that do not have
-- a registered class type. If the entity also doesn't exist on the server,
-- then CreateDummyEntity() will be called.
-- @param entData
function Paster:CreateGenericEntity(entData)
    local ent = ents.Create(entData.Class)
    
    if not ent:IsValid() then
        -- Allow people to write their own dummy entities
        return self:CreateDummyEntity(entData)
    end
    
    if not IsValidModel(entData.Model) then
        self:Warn("missing_model", entData.Model)
        return nil
    end
    
    -- Apply position and model
    duplicator.DoGeneric(ent, entData)
    
    ent:Spawn()
    ent:Activate()
    
    -- Apply physics object data
    duplicator.DoGenericPhysics(ent, self.Player, entData)
    
    return ent
end
 
--- Create a dummy entity (for entities that do not exist). This function
-- can be overrided if you want to handle this a bit differently.
-- @param entData Entity data
function Paster:CreateDummyEntity(entData)    
    if not IsValidModel(entData.Model) then
        self:Warn("missing_model", entData.Model)
        return nil
    else
        self:Warn("unknown_entity_type", entData.Class)
    end
    
    local ent = ents.Create("prop_physics")
    ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
    
    -- Apply position and model
    duplicator.DoGeneric(ent, entData)
    
    ent:Spawn()
    ent:Activate()
    
    -- Apply physics object data
    duplicator.DoGenericPhysics(ent, self.Player, entData)
    
    return ent
end

--- Set up the entity. Called right after the entity has been spawned and
-- before all entities have been spawned.
-- @param ent Entity
-- @param entData
function Paster:SetupEntity(ent, entData)
    -- We will need these later
    entData.BoneMods = CastTable(entData.BoneMods)
    entData.EntityMods = CastTable(entData.EntityMods)
    entData.PhysicsObjects = CastTable(entData.PhysicsObjects)
    
    ent.BoneMods = table.Copy(entData.BoneMods)
    ent.EntityMods = table.Copy(entData.EntityMods)
    ent.PhysicsObjects = table.Copy(entData.PhysicsObjects)
    
    self:ApplyEntityModifiers(ent)
    self:ApplyBoneModifiers(ent)
    
    -- Set skin manually
    if tonumber(entData.Skin) then
        ent:SetSkin(tonumber(entData.Skin))
    end
    
    -- Seat fix
    if ent:GetClass() == "prop_vehicle_prisoner_pod" and
        ent:GetModel() ~= "models/vehicles/prisoner_pod_inner.mdl" and
        not ent.HandleAnimation then
        
        ent.HandleAnimation = function(self, ply)
            return self:SelectWeightedSequence(ACT_GMOD_SIT_ROLLERCOASTER)
        end
    end
end

--- Called on each entity after all the entities have eben spawned.
-- @param ent Entity
-- @param entData
function Paster:PostSetupEntity(ent, entData)
    -- Duplicator hook
    if ent.PostEntityPaste then
        putil.ProtectedCall(ent.PostEntityPaste, ent, self.Player, ent, self.CreatedEntsMap)
    end
    
    -- Clean up
    if ent.EntityMods then
        ent.EntityMods.RDDupeInfo = nil
        ent.EntityMods.WireDupeInfo = nil
    end
end

--- Create a constraint from a constraint data table.
-- @param constrData
function Paster:CreateConstraint(constrData)
    if not constrData.Type then return end
    
    if not self:CanCreateConstraint(constrData) then
        self:Warn("constraint_create_disallowed", constrData.Type, constrData.Index or -1)
        return
    end
    
    local cls = duplicator.ConstraintType[constrData.Type]
    if not cls then return end
    
    local factory = cls.Func
    local args = {}
    
    -- Get class arguments
    for _, argName in ipairs(cls.Args) do
        local val = constrData[argName]
        
        if argName == "pl" then val = self.Player end
        
        local c, i = argName:match("([A-Za-z]+)([1-6]?)")
        local data = constrData.Entity[tonumber(i) or 1]
        
        -- Have to pull the data out of that Entity sub-table
        if c == "Ent" then
            if data.World then
                val = GetWorldEntity()
            else
                val = self.CreatedEntsMap[data.Index or -1]
                if not ValidEntity(val) then
                    self:Warn("constraint_invalid_reference", constrData.Type, data.Index or -1)
                    return
                end
            end
        elseif c == "Bone" then
            val = data.Bone
        elseif c == "LPos" then
            if data.World and type(data.LPos) == 'Vector' then
                val = data.LPos + self.Pos
            else
                val = data.LPos
            end
        elseif c == "WPos" then
            val = data.WPos
        elseif c == "Length" then
            val = data.Length
        end
        
        -- Legacy duplicator compatibility
        if val == nil then
            val = false
        end
        
        table.insert(args, val)
    end
    
    local ret, res = pcall(factory, unpack(args, 1, table.maxn(args)))
    
    if ret then
        -- Elastic fix
        if type(constrData.length) == 'number' then
            res:Fire("SetSpringLength", constrData.length, 0)
            res.length = constrData.length
        end
        
        return res
    else
        self:Warn("constraint_create_fail", constrData.Type, res)
        return nil
    end
end

--- Called at the very end, after all the entities and constraints have
-- been created.
function Paster:Finalize()
    undo.Create("photocopy")

    for entIndex, ent in pairs(self.CreatedEntsMap) do
        if ValidEntity(ent) then
            undo.AddEntity(ent)
            
            local entData = self.EntityData[entIndex]
            
            ent:SetNotSolid(false)
            ent:SetParent()
            
            -- Unfreeze physics objects
            if not self.SpawnFrozen then
                for bone = 0, ent:GetPhysicsObjectCount() - 1 do
                    local physObj = ent:GetPhysicsObjectNum(bone)
                    
                    if physObj:IsValid() then
                        local b = entData.PhysicsObjects[bone] or {}
                        local shouldBeFrozen = b.Frozen and true or false
                        physObj:EnableMotion(not shouldBeFrozen)
                    end
                end
            end
            
            -- RD2 compatibility
            if ent.RDbeamlibDrawer then
                ent.RDbeamlibDrawer:SetParent()
            end
            
            -- Parent
            if not self.NoConstraints then
                self:ApplyParenting(ent, entData)
            end
        end
    end
    
    undo.SetPlayer(self.Player)
    undo.Finish()
    
    local legacyPasteData = {
        [1] = {
            CreatedEntities = self.CreatedEntsMap,
        },
    }
    
    hook.Call("AdvDupe_FinishPasting", GAMEMODE, legacyPasteData, 1)
    hook.Call("DuplicationFinished", GAMEMODE, self.CreatedEntsMap)
end

--- Apply parenting.
-- @param ent
-- @param entData
function Paster:ApplyParenting(ent, entData)
    local parentID = entData.SavedParentIdx
    if not parentID then return end
    
    local ent2 = self.CreatedEntsMap[parentID]
    
    if ValidEntity(ent2) and ent != ent2 then
        ent:SetParent()
        -- Prevent circular parents
        if ent == ent2:GetParent() then
            ent2:SetParent()
        end
        ent:SetParent(ent2)
    end
end

--- Creates a helper entity that is essential to spawning some parented
-- contraptions. Without a helper entity, these contraptions may freeze the
-- server once unfrozen. The helper entity also allows the player to undo
-- the contraption while spawning.
-- @param ent
-- @param entData
function Paster:CreateHelperEnt()
    if ValidEntity(self.HelperEnt) then return end
    
    self.HelperEnt = ents.Create("base_anim")
    self.HelperEnt:SetNotSolid(true)
    self.HelperEnt:SetPos(self.Pos)
    putil.FreezeAllPhysObjs(self.HelperEnt)
    self.HelperEnt:SetNoDraw(true)
    self.HelperEnt:Spawn()
    self.HelperEnt:Activate()
    
    self.Player:AddCleanup("duplicates", self.HelperEnt)
    
    undo.Create("photocopy_paste")
    undo.AddEntity(self.HelperEnt)
    undo.SetPlayer(self.Player)
    undo.Finish()
end

--- Create the props.
function Paster:_Spawn()
    self:SetNext(0.1)
    
    for i = 1, self.SpawnRate do
        local entIndex, entData = next(self.EntityData, self.CurIndex)
        self.CurIndex = entIndex
        
        if not entIndex then
            self.CurIndex = nil
            self:SetNext(0.05, self._PostSetup)
            return
        end
        
        self:PrepareEntityData(entData)
        
        if self:CanCreateEntity(entData) then
            local ent = self:CreateEntity(entData)
            
            if not self:CanAllowEntity(ent, entData) then
                ent:Remove()
                self:Warn("entity_create_disallowed", entData.Class, entIndex)
            elseif ValidEntity(ent) then
                if ValidEntity(self.HelperEnt) then
                    ent:SetParent(self.HelperEnt)
                end
                
                self.Player:AddCleanup("duplicates", ent)
                
                self:SetupEntity(ent, entData)
                
                self.CreatedEntsMap[entIndex] = ent
                
                ent:SetNotSolid(true)
                putil.FreezeAllPhysObjs(ent)
            end
        else
            self:Warn("entity_create_disallowed", entData.Class, entIndex)
        end
    end
end

--- Do some post setup.
function Paster:_PostSetup()
    self:SetNext(0.01)
    
    for i = 1, self.PostSetupRate do
        local entIndex, entData = next(self.EntityData, self.CurIndex)
        self.CurIndex = entIndex
        
        if not entIndex then
            self.CurIndex = nil
            if self.NoConstraints then
                self:SetNext(0.05, self._Finalize)
            else
                self:SetNext(0.1, self._Constrain)
            end
            
            return
        end

        local ent = self.CreatedEntsMap[entIndex]
        
        if ValidEntity(ent) then -- Maybe something happened
            self:PostSetupEntity(ent, entData)
        end
    end
end

--- Do some post setup.
function Paster:_Constrain()
    self:SetNext(0.1)
    
    for i = 1, self.ConstrainRate do
        local k, constrData = next(self.ConstraintData, self.CurIndex)
        self.CurIndex = k
        
        if not k then
            self.CurIndex = nil
            self:SetNext(0.1, self._Finalize)
            return
        end
        
        self:CreateConstraint(constrData)
    end
end

--- Finalization.
function Paster:_Finalize()
    self:Finalize()
    if ValidEntity(self.HelperEnt) then
        self.HelperEnt:Remove()
    end
    self:SetNext(0, false)
end

AccessorFunc(Paster, "NoConstraints", "NoConstraints", FORCE_BOOL)
AccessorFunc(Paster, "SpawnFrozen", "SpawnFrozen", FORCE_BOOL)
AccessorFunc(Paster, "Filter", "Filter")

------------------------------------------------------------
-- Reader
------------------------------------------------------------

Reader = putil.CreateClass(putil.IterativeProcessor)

-- Constructor.
function Reader:__construct(data)
    putil.IterativeProcessor.__construct(self)
    
    if data == nil then
        error("Photocopy Reader got empty data")
    end
    
    self.Data = data
    self.Clipboard = nil
end

function Reader:GetName() return nil end
function Reader:GetDescription() return nil end
function Reader:GetCreatorName() return nil end
function Reader:GetSaveTime() return nil end
function Reader:GetOriginPos() return Vector(0, 0, 0) end
function Reader:GetOriginAngle() return Angle(0, 0, 0) end

AccessorFunc(Reader, "Clipboard", "Clipboard")

------------------------------------------------------------
-- Writer
------------------------------------------------------------

Writer = putil.CreateClass(putil.IterativeProcessor)

-- Constructor.
function Writer:__construct(clipboard)
    putil.IterativeProcessor.__construct(self)
    
    self.Clipboard = clipboard
    self.Output = ""
end

function Writer:SetName(name) end
function Writer:SetDescription(desc) end
function Writer:SetCreatorName(name) end
function Writer:SetSaveTime(t) end
function Writer:SetOriginPos(pos) end
function Writer:SetOriginAngle(pos) end

AccessorFunc(Writer, "Output", "Output")

------------------------------------------------------------
-- Filter
------------------------------------------------------------

Filter = putil.CreateClass()

--- Construct the filter.
function Filter:__construct(offset)
end

--- Check to make sure that this entity can be copied.
-- @param ent
-- @return Boolean indicating whether the entity can be created
function Filter:CanCopyEntity(ent)
    return true
end

--- Check to make sure that this entity can be copied. The passed table can
-- be modified safely.
-- @param entData
-- @return Boolean indicating whether the entity can be created
function Filter:CanCopyEntityData(entData)
    return true
end

--- Check to make sure that this entity can be pasted before actual
-- entity creation. The passed table can be modified safely.
-- @param entData
-- @return Boolean indicating whether the entity can be created
function Filter:CanCreateEntity(entData)
    return true
end

--- After the entity is created, this function can be used to undo the entity.
-- Return true if the entity should continue existing, otherwise return
-- false to have the entity removed.
-- @param ent
-- @param entData entity table
-- @return Boolean indicating whether the entity can be created
function Filter:CanAllowEntity(ent, entData)
    return true
end

--- Check to see whether this constraint can be created. Return false in
-- this function to disable. The constraint data table can also be modified.
-- @param constrData
-- @return Boolean indicating whether the entity can be created
function Filter:CanCreateConstraint(constrData)
    return true
end


------------------------------------------------------------
-- Networker
------------------------------------------------------------
if SERVER then
CreateConVar("photocopy_ghost_rate" , "50" , {FCVAR_ARCHIVE} ) // usermessages per second for ghost info

svGhoster = putil.CreateClass(putil.IterativeProcessor)

--the networker, will send things from the server to the client via usermessages
-- @param data
-- @param data override for files
function svGhoster:__construct( ply )
    putil.IterativeProcessor.__construct(self)
    self.ply = ply
end

-- the initialiser
-- @param clipboard, a clipboard object
function svGhoster:Initialize( clipboard , offset)
    //GetTime()
    self.EntityData = clipboard.EntityData

    self.Pos = clipboard:GetOffset()
    self.offset = offset or (clipboard:GetOffset() - QuickTrace( clipboard:GetOffset() , clipboard:GetOffset() - Vector(0,0,10000) , ents.GetAll() ).HitPos)

    self.SendRate = GetConVar("photocopy_ghost_rate"):GetInt() / 10
    
    self.CurIndex = nil

    self.GhostParent = self:GetGhostController()
    self:SetNext(0, self.SendInitializeInfo)
    //GetTime()
end

-- Creates the ghost entity a single player's ghost parent too, bound to that player
function svGhoster:CreateGhostEnt()
    local ent = ents.Create("base_anim")
    ent:SetColor(0,0,0,0)
    ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
    ent:SetNotSolid(true)
    ent:Spawn()
    ent:Activate()

    self.ply.GhostController = ent
    
    return ent
end
hook.Add("PlayerDisconnected" , "photocopy_remove_ghostent" , function( ply )
    SafeRemoveEntity(ply.GhostController)
end)
hook.Add("PlayerDeath" , "photocopy_remove_ghostent" , function( ply )
    //SafeRemoveEntity(ply.GhostController)
    //ply.GhostController = nil
end)
hook.Add("PlayerSpawn" , "photocopy_create_ghostent" , function( ply )
    if !ply.GhostController then
        local ent = ents.Create("base_anim")
        ent:SetColor(0,0,0,0)
        ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
        ent:SetNotSolid(true)
        ent:Spawn()
        ent:Activate()

        ply.GhostController = ent
    end
end)

-- Returns the player's GhostParet 
function svGhoster:GetGhostController()
    local ent 
    if IsValid(self.ply.GhostController) then
        ent = self.ply.GhostController
    else
        ent = self:CreateGhostEnt()
    end
    
    ent:SetPos(self.Pos)
    return ent
end

-- Sends the initializer info to start a new ghost
function svGhoster:SendInitializeInfo()
    //GetTime()
    umsg.Start("photocopy_ghost_init" , self.ply )
        umsg.Entity( self:GetGhostController() )
        umsg.Float( self.offset.x )
        umsg.Float( self.offset.y )
        umsg.Float( self.offset.z )
    umsg.End()
    self:SetNext(0 , self.SendGhostInfo)
    //GetTime()
end

--ghost info
function svGhoster:SendGhostInfo()
    //GetTime()
    local entIndex , entData
    local pos , ang
    for i = 1 , self.SendRate do        
        entIndex , entData = next(self.EntityData, self.CurIndex)
        self.CurIndex = entIndex

        if not entIndex then
            self.CurIndex = nil
            self:SetNext(0,false)
            return
        end

        umsg.Start("photocopy_ghost_info" , self.ply )
            umsg.String(entData.Model)
            -- postion
            pos = entData.LocalPos
                umsg.Float(pos.x)
                umsg.Float(pos.y)
                umsg.Float(pos.z)
            --angle
            ang = entData.LocalAngle
                umsg.Float(ang.p)
                umsg.Float(ang.y)
                umsg.Float(ang.r)
            
        umsg.End()
    end

    self:SetNext(0)
    //GetTime()
end

------------------------------------------------------------
-- svFileNetworker
------------------------------------------------------------
svFileNetworker = putil.CreateClass(putil.IterativeProcessor)

function svFileNetworker:__construct( ply )
    putil.IterativeProcessor.__construct(self)
    self.ply = ply

    datastream.Hook("photocopy_serverfiletransfer"..tostring(ply) , function( pl , handler , id , encoded , decoded ) self:ReceiveFile( pl , decoded) end)
    hook.Add("AcceptStream" , "photocopy_serverfiletransfer"..tostring(ply) , function(pl) return pl == ply end)
end


function svFileNetworker:SendToClient( data , filename , callback , ply )
    if self.Sending then return end
    self.ply = ply or self.ply
    self.data = data
    self.index = 0
    self.chunk = 0
    self.length = math.ceil( #data / 245 )
    self.Sending = true

    umsg.Start( "photocopy_clientfiletransfer_init" , self.ply )
        umsg.String( CRC( self.data ) )
        umsg.String( filename )
        umsg.Long( self.length )
    umsg.End()

    self:Start( function() self.Sending = false  if callback then callback() end end )
    self:SetNext(0.025 , self.SendData )
end

function svFileNetworker:SendData()
    for i = 1 , 5 do
        self.chunk = self.chunk + 1
        if self.chunk == self.length then self:SetNext( 0 , false ) end
        local str = string.sub( self.data , self.index , self.index +245 )

        umsg.Start( "photocopy_clientfiletransfer_data" , self.ply )
            umsg.String( str )
        umsg.End()

        self.index = self.index + 246
    end
    self:SetNext( 0 )
    
end

function svFileNetworker:SetCallbacks( OnSuccess , OnFailed )
    if OnSuccess then
        self.OnSuccess = OnSuccess
    else
        self.OnSuccess = function() end
    end
    if OnFailed then
        self.OnFailed = OnFailed
    else
        self.OnFailed = function() end
    end
end

function svFileNetworker:ReceiveFile( ply , tab )
    local filename = tab[1]
    local crc = tab[2]
    local data = tab[3]

    if crc == CRC( tab[3] ) then
        self.OnSuccess( filename , data )
    else
        self.OnFailed()
    end
end

end
if CLIENT then
------------------------------------------------------------
-- clFileNetworker
------------------------------------------------------------
clFileNetworker = putil.CreateClass(putil.IterativeProcessor)

-- constructer, there should only ever be one clFileNetworker class client side ever
function clFileNetworker:__construct()
    putil.IterativeProcessor.__construct(self)

    self.Length = 0
    self.Index = 0

    usermessage.Hook( "photocopy_clientfiletransfer_init" , function( um ) self:InitializeTransfer( um:ReadString() , um:ReadString() , um:ReadLong() ) end)

    usermessage.Hook( "photocopy_clientfiletransfer_data" , function( um ) self:ReceiveData( um:ReadString() ) end)

end

-- Called when the initializing usermessage is received.
-- @param crc a crc of the file
-- @param length of the file /250, amount of usermessages to be received.
function clFileNetworker:InitializeTransfer( crc , filename , length )
    self.CRC = crc
    self.Length = length
    self.FileName = filename
    self.ReceivingFile = true

    self.Index = 0
    self.Progress = 0
    self.Strings = {}
end

-- Called when part of the data is received
-- @param strchunk a string 250 chars in length, received by the usermessage
function clFileNetworker:ReceiveData( strchunk )
    self.Index = self.Index + 1

    self.Strings[ #self.Strings + 1 ] = strchunk

    if self.Index == self.Length then self:Finish() end
end

-- called when the entire file is received, turns the received chunks into a string again
function clFileNetworker:Finish()
    self.Receiving = false
    local concat = table.concat( self.Strings , "" )

    local crc = CRC( concat )
    
    if crc == self.CRC then
        self.OnReceived( concat , self.FileName )
    else
        self.OnFailed( concat , crc )
    end
end

-- Used to set the OnSucces and OnFailed callback
-- param OnSuccess called when succesful file transfer
-- param OnFailed called when unsuccessful file transfer
function clFileNetworker:SetCallbacks( OnReceived , OnFailed )
    if OnReceived then
        self.OnReceived = OnReceived
    else
        self.OnReceived = function() end
    end
    if OnFailed then
        self.OnFailed = OnFailed
    else
        self.OnFailed = function() end
    end
end

-- Sending files
-- @param data filename callbackcompleted
function clFileNetworker:SendToServer( data , filename , callbackcompleted )
    if self.Receiving then notification.AddLegacy( "Cannot upload file while downloading a file", NOTIFY_ERROR , 7 ) return end
    self.Sending = true
    self.Length = #filename + #CRC(data) + #data

    local function Completed( ... )
        self.Sending = false
        callbackcompleted(...)
    end

    self.SendID = datastream.StreamToServer("photocopy_serverfiletransfer"..tostring(LocalPlayer()) , { filename , CRC(data) , data}, Completed )
end

-- returns the progress on the file download
function clFileNetworker:GetProgress()
    if self.ReceivingFile then
        return (self.Index / self.Length) * 100
    elseif self.Sending then
        return ((datastream.GetProgress( self.SendID ) or 0) / self.Length) * 100
    end
end 
end // end "if CLIENT then" block



MsgN("Photocopy %Version$ loaded (http://www.sk89q.com/projects/photocopy/)")

include("photocopy/compat.lua")

local list = file.FindInLua("photocopy/formats/*.lua")
for _, f in pairs(list) do
	MsgN("Photocopy: Auto-loading format file: " .. f)
    include("photocopy/formats/" .. f)
end

