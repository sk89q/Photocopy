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
local putil = require("photocopy.util")

local AdvDupeReader = putil.CreateClass(photocopy.Reader)

--- Construct the Adv. Dupe reader.
-- @param data
function AdvDupeReader:__construct(data , parsetime)
    photocopy.Reader.__construct(self, data)
    self.parsetime = parsetime or 0.1
    
    self.Header = {}
    self.ExtraHeader = {}
    self.EntityData = {}
    self.ConstraintData = {}
    self:SetNext(0, self._ParseFormat)
end

--- Parse a key value block in the format of the two headers.
-- @param data
-- @param unquote Reverse string.format("%q", str)
-- @param getFirst Get first line
-- @return Table
function AdvDupeReader:ParseKeyValueBlock(data, unquote, getFirst)
    local lines = string.Explode("\n", data)
    local firstLine = nil
    if getFirst then
        firstLine = table.Remove(lines, 1)
    end
    local out = {}
    
    for _, line in pairs(lines) do
        local k, v = line:match("^(.-):(.*)$")
        if v then
            if unquote then
                v = self:Unquote(v)
            end
            out[k] = v
        elseif k then
            out[k] = ""
        end
    end
    
    return out, firstLine or ""
end

--- This function does enough to unquote strings for Adv. Dupe's format, but
-- it is flat out wrong. However, we can depend on Adv. Dupe having a bad
-- serializer to make this viable.
function AdvDupeReader:Unquote(str)
    if str:sub(1, 1) == "\"" then str = str:sub(2) end
    if str:sub(-1, -1) == "\"" then str = str:sub(1, -2) end
    str = str:gsub("%\\%\\", "\\")
    return str
end

-- Parse a serialized table. Unfortunately this function is highly suspectible
-- to server choking, but only less than Adv. Dupe's version. Without working
-- coroutines in Gmod, optimizing this is complicated.
-- @param str
-- @return table
function AdvDupeReader:DeserializeTables(str)
    local head = {}
    local tables = {}
    
    for id, chunk in str:gmatch("(%w+){(.-)}") do
        local isHead = false
        
        -- Detect the head table
        if id:sub(1, 1) == "H" then
            id = id:sub(2)
            isHead = true
        end
        
        -- There is no need to merge table references (as in Adv. Dupe's
        -- serializer) if tables are tracked this way
        tables[id] = tables[id] or {}
        if isHead then head = tables[id] end
        
        for item in chunk:gmatch("(.-);") do
            local k, v = item:match("(.-)=(.+)")
            
            if not k then
                table.insert(tables[id], self:DeserializeChunk(item, tables))
            else
                k = self:DeserializeChunk(k, tables)
                v = self:DeserializeChunk(v, tables)
                
                -- Extra error check
                if k ~= nil then
                    tables[id][k] = v
                end
            end
        end
    end
    
    return head
end

--- Deserializes a chunk. This is pretty much the same as Adv. Dupe's chunk
-- deserialization code, except that it is a little more error-resiliant.
-- @param str String to decode
-- @param tables Tables
-- @return data
function AdvDupeReader:DeserializeChunk(str, tables)
    local t, v = str:match("^(.):(.+)$")
    if not v then return nil end
    
    if t == "N" then return tonumber(v)
    elseif t == "S" then
        local s = string.gsub(self:Unquote(v), "»", ";")
        return s
    elseif t == "Z" then return self.Dict[self:Unquote(v)]
    elseif t == "Y" then return self.Dict[v]
    elseif t == "B" then return v == "t"
    elseif t == "V" then
		local x, y, z = v:match("^(.-),(.-),(.+)$")
		return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    elseif t == "A" then
		local p, y, r = v:match("^(.-),(.-),(.+)$")
		return Angle(tonumber(p) or 0, tonumber(y) or 0, tonumber(r) or 0)
    elseif t == "P" then return player.GetByUniqueID(v)
    elseif t == "T" then
        tables[v] = tables[v] or {}
        return tables[v]
    end
    
    return nil
end

--- Extract the general structure of the advanced duplicator file. No
-- processing of the sections are done at this stage.
-- @return Whether to advance stage
function AdvDupeReader:_ParseFormat()
    local header, extraHeader, dataBlock, dictBlock
    
    -- Contraption Saver
    if self.Data:sub(1, 13) == "[Information]" then
        header, extraHeader, dataBlock = 
            self.Data:match("%[Information%]\n(.+)\n%[More Information%]\n(.+)\n%[Save%]\n(.+)")
    -- Advanced Duplicator
    elseif self.Data:sub(1, 6) == "[Info]" then
        header, extraHeader, dataBlock, dictBlock = 
            self.Data:match("%[Info%]\n(.+)\n%[More Information%]\n(.+)\n%[Save%]\n(.+)\n%[Dict%]\n(.+)")
    else
        dataBlock = self.Data
    end
    
    self.HeaderData = header or ""
    self.ExtraHeaderData = extraHeader or ""
    self.SaveData = dataBlock or ""
    self.DictData = dictBlock
    
    self:SetProgress(5)
    self:SetNext(self.parsetime, self._ParseHeaders)
end

-- Parse the two headers in this stage. This function will choke the server
-- if there are enough keys.
-- @return Whether to advance stage
function AdvDupeReader:_ParseHeaders()
    self.Header = self:ParseKeyValueBlock(self.HeaderData)
    self.ExtraHeader = self:ParseKeyValueBlock(self.ExtraHeaderData)
    
    self:SetProgress(10)
    self:SetNext(self.parsetime, self._ParseDictAndSave)
end

-- Parse the dict and save sections. Choking issue applies.
function AdvDupeReader:_ParseDictAndSave()
    -- Advanced Duplicator
    if self.DictData then
        self.Dict = self:ParseKeyValueBlock(self.DictData, true)
        self.Save = self:ParseKeyValueBlock(self.SaveData, true)
        
        self:SetProgress(40)
        self:SetNext(self.parsetime, self._DeserializeEntities)
    -- Contraption Saver
    else
        local dict, firstLine
        
        if self.Header.Type == "Contraption Saver File" then
            dict, firstLine = self:ParseKeyValueBlock(self.DictData, false, true)
        else
            dict, firstLine = self:ParseKeyValueBlock(self.DictData, true, true)
        end
        
        self.Dict = dict
        self.SaveTableData = firstLine
        
        -- The first line contains the entity/constraint data (I think)
        self:SetProgress(40)
        self:SetNext(self.parsetime, self.DeserializeContraptionSaver)
    end
end

-- Parse contraption saver's file. Choking issue applies.
function AdvDupeReader:DeserializeContraptionSaver()
    local t = self:DeserializeTables(self.SaveTableData)
    self.EntityData = t.Entities or {}
    self.ConstraintData = t.Constraints or {}
    
    self:SetProgress(95)
    self:SetNext(0, self._Finish)
end

-- Parse the dict and save sections. Choking issue applies.
function AdvDupeReader:_DeserializeEntities()
    self.EntityData = self:DeserializeTables(self.Save.Entities or "")
    
    self:SetProgress(70)
    self:SetNext(self.parsetime, self._DeserializeConstraints)
end

-- Parse the dict and save sections. Choking issue applies.
function AdvDupeReader:_DeserializeConstraints()
    self.ConstraintData = self:DeserializeTables(self.Save.Constraints or "")
    
    self:SetProgress(95)
    self:SetNext(0, self._Finish)
end

-- Finish off and build the clipboard.
function AdvDupeReader:_Finish()
    local clipboard = photocopy.Clipboard(self:GetOriginPos())
    clipboard:SetEntityData(self.EntityData)
    clipboard:SetConstraintData(self.ConstraintData)
    self:SetClipboard(clipboard)
    
    -- Free references for the GC
    self.Data = nil
    
    self:SetProgress(100)
    self:SetNext(0, false)
end

--- Get the original position of the save. This should only be called after
-- the file has been fully loaded.
-- @return Vector
function AdvDupeReader:GetOriginPos()
    if self.ExtraHeader.HoldPos then
		local x, y, z = self.ExtraHeader.StartPos:match("^(.-),(.-),(.+)$")
		return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    end
    return Vector(0, 0, 0)
end

photocopy.RegisterFormat("AdvDupe", AdvDupeReader, nil)