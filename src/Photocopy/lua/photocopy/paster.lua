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

CreateConVar("photocopy_paste_spawn_rate", "5", { FCVAR_ARCHIVE })
CreateConVar("photocopy_paste_setup_rate", "20", { FCVAR_ARCHIVE })
CreateConVar("photocopy_paste_constrain_rate", "10", { FCVAR_ARCHIVE })

--- Function to override duplication for prop_physics. This version has
-- no effect, which is the main advantage. This is largely copied from sandbox.
-- @param ply
-- @param pos
-- @param model
-- @param physObj
-- @param data Entity data
function photocopy.PropClassFunction(ply, pos, ang, model, physObjs, data)
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
-- Functions
------------------------------------------------------------

--- Makes sure that the returned value is indeed a Vector. This function
-- accepts Vectors, tables, and anything else. A vector at 0, 0, 0 will
-- be returned if the data is invalid.
-- @param val Value of any type
-- @return Vector
local function CastVector(val)
    if type(val) == 'Vector' then
        return val
    elseif type(val) == 'table' then
        return Vector(tonumber(val[1]) or 0,
                      tonumber(val[2]) or 0,
                      tonumber(val[3]) or 0)
    else
        return Vector(0, 0, 0)
    end
end

--- Makes sure that the return value is actually an Angle. This function
-- accepts Angles, tables, and anything else. An angle of 0, 0, 0 will be
-- returned in lieu of a valid Angle.
-- @param val Value
-- @return Angle
local function CastAngle(val)
    if type(val) == 'Angle' then
        return val
    elseif type(val) == 'table' then
        return Angle(tonumber(val[1]) or 0,
                     tonumber(val[2]) or 0,
                     tonumber(val[3]) or 0)
    else
        return Angle(0, 0, 0)
    end
end

--- Returns a table for sure.
-- @param val
-- @return Table
local function CastTable(val)
    if type(val) == 'table' then
        return val
    else
        return {}
    end
end

--- Runs a function and catches errors, without caring about the return
-- value of the function. Errors will be raised as a Lua error, but it
-- will not end execution.
-- @param f Function to call
-- @param ... Arguments
local function ProtectedCall(f, ...)
    local args = {...}
    local ret, err = pcall(f, unpack(args, 1, table.maxn(args)))
    if not ret then
        ErrorNoHalt(err)
        return false
    end
    return true
end

--- Freeze all the physics objects of an entity.
-- @param ent
local function FreezeAllPhysObjs(ent)
    for bone = 0, ent:GetPhysicsObjectCount() - 1 do
        local physObj = ent:GetPhysicsObjectNum(bone)
        
        if physObj:IsValid() then
            physObj:EnableMotion(false)
        end
    end
end

------------------------------------------------------------
-- Paster
------------------------------------------------------------

local Paster = photocopy.CreateClass(photocopy.IterativeProcessor)
photocopy.Paster = Paster

--- Construct the Paster. Currently the angle to paste at cannot have a
-- non-zero pitch or roll, as some entities will spawn with an incorrect
-- orientation (the cause is not yet pinpointed).
-- @param clipboard Clipboard
-- @param ply Player
-- @param originPos Position to paste at
-- @param originAng Angle to paste at
function Paster:__construct(clipboard, ply, originPos, originAng)
    photocopy.IterativeProcessor.__construct(self)
    
    self.EntityData = table.Copy(clipboard.EntityData)
    self.ConstraintData = table.Copy(clipboard.ConstraintData)
    self.Player = ply
    self.Pos = originPos
    self.Ang = originAng
    
    self.SpawnFrozen = false
    self.NoConstraints = false
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
    
    return true
end

--- After the entity is created, this function can be used to undo the entity.
-- Return true if the entity should continue existing, otherwise return
-- false to have the entity removed.
-- @param ent
-- @param entData
-- @return Boolean indicating whether the entity can be created
function Paster:IsAllowedEntity(ent, entData)
    return true
end

--- Check to see whether this constraint can be created. Return false in
-- this function to disable. The constraint data table can also be modified.
function Paster:CanCreateConstraint(constrData)
    return true
end

--- Apply entity modifiers. The duplicator's ApplyEntityModifiers() will
-- fail on a bad entity modifier function, but this one will log
-- individual errors to the paster log.
-- @param ent
function Paster:ApplyEntityModifiers(ent)
    for type, func in pairs(duplicator.EntityModifiers) do
        if ent.EntityMods[type] then
            local ret, err = pcall(func, self.Player, ent, ent.EntityMods[type])
            
            if not ret then
                self:Warn("Entity mod '%s' failed on ent #%d: %s",
                              type, ent:EntIndex(), err)
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
                        self:Warn("Bone mod '%s' failed on ent #%d: %s",
                                      type, ent:EntIndex(), err)
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
        factory = photocopy.PropClassFunction
    end
    
    -- Get class arguments
    for _, argName in ipairs(cls.Args) do
        local newArgName = photocopy.IgnoreClassKeys[argName:lower()]
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
        self:Warn("Factory failed to create '%s': %s", entData.Class, res)
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
    
    if not util.IsValidModel(entData.Model) then
        self:Warn("Server doesn't have the model '%s'; no entity created",
                  entData.Model)
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
    if not util.IsValidModel(entData.Model) then
        self:Warn("Server doesn't have the model '%s'; no dummy entity created",
                  entData.Model)
        return nil
    else
        self:Warn("Server doesn't have a '%s' entity", entData.Class)
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
        ProtectedCall(ent.PostEntityPaste, ent, self.Player, ent, self.CreatedEntsMap)
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
                    self:Warn("Failed to create constraint '%s': " ..
                        "Referred to non-existent entity #%d",
                        constrData.Type, data.Index or -1)
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
        self:Warn("Failed to create constraint '%s': %s",
            constrData.Type, res)
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
    FreezeAllPhysObjs(self.HelperEnt)
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
            
            if not self:IsAllowedEntity(ent, entData) then
                ent:Remove()
            elseif ValidEntity(ent) then
                if ValidEntity(self.HelperEnt) then
                    ent:SetParent(self.HelperEnt)
                end
                
                self.Player:AddCleanup("duplicates", ent)
                
                self:SetupEntity(ent, entData)
                
                self.CreatedEntsMap[entIndex] = ent
                
                ent:SetNotSolid(true)
                FreezeAllPhysObjs(ent)
            end
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