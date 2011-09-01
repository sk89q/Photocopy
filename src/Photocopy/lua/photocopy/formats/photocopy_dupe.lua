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

CreateConVar("photocopy_pcd_serialization_rate", "2000", { FCVAR_ARCHIVE })
CreateConVar("photocopy_pcd_deserialization_rate", "2000", { FCVAR_ARCHIVE })

------------------------------------------------------------
-- Writer
------------------------------------------------------------

local PCDWriter = putil.CreateClass(photocopy.Writer)

--- Construct the Photocopy Dupe writer.
-- @param data
function PCDWriter:__construct(clipboard)
    photocopy.Writer.__construct(self, clipboard)
    
    self.SerializationRate = GetConVar("photocopy_pcd_serialization_rate"):GetInt()
    
    local offset = self.Clipboard:GetOffset()
    self.Header = {
        NumEnts = table.Count(self.Clipboard:GetEntityData()),
        NumConstrs = table.Count(self.Clipboard:GetConstraintData()),
        OriginPos = string.format("%g,%g,%g", offset.x, offset.y, offset.z),
        Time = os.time(),
    }
    
    self.Buffer = putil.Buffer()
    
    -- Strings to be stored here
    self.Strings = {}
    self.StringsIndex = {}
    
    self:SetNext(0, self._WriteHeader)
end

--- Set the name of the save.
-- @param name
function PCDWriter:SetName(name)
    self.Header.Name = name
end

--- Set the description of the save.
-- @param desc
function PCDWriter:SetDescription(desc)
    self.Header.Desc = desc
end

--- Set the name of the creator of the save.
-- @param name
function PCDWriter:SetCreatorName(name)
    self.Header.Creator = name
end

--- Set the save time. The save time is automatically set to the time
-- that an instance of this class was created.
-- @param name
function PCDWriter:SetSaveTime(t)
    self.Header.Time = t
end

--- Set the origin position.
-- @param name
function PCDWriter:SetOriginPos(pos)
    if pos then
        self.Header.OriginPos = string.format("v%g,%g,%g", pos.x, pos.y, pos.z)
    end
end

-- Write a integer that is free of nulls.
-- @param v
function PCDWriter:WriteNLInt(buffer, v)
    local a = math.floor(v / 16581375) + 1
    local b = math.floor(v / 65025) % 255 + 1
    local c = math.floor(v / 255) % 255 + 1
    local d = math.floor(v % 255) + 1
    
    buffer:Write(string.char(a, b, c, d))
end

-- Write a variable width ID that is free of nulls.
-- @param v
function PCDWriter:WriteVarID(buffer, v)
    local a = math.floor(v / 16581375) + 1
    local b = math.floor(v / 65025) % 255 + 1
    local c = math.floor(v / 255) % 255 + 1
    local d = math.floor(v % 255) + 1
    
    buffer:Write(string.char(d))
    if v > 255 then buffer:Write(string.char(c)) end
    if v > 65025 then buffer:Write(string.char(b)) end
    if v > 16581375 then buffer:Write(string.char(a)) end
end

-- Write a chunk.
-- @param identifier
-- @param content
function PCDWriter:WriteChunk(identifier, content)
    if string.len(identifier) ~= 4 then
        Error("Invalid identifier length: " .. identifier)
    end
    self.Buffer:Write(identifier)
    self:WriteNLInt(self.Buffer, string.len(content))
    self.Buffer:Write(content)
end

-- Escape the values for the key/value sections.
-- @param str
-- @return Escaped
function PCDWriter:EscapeKV(str)
    str = tostring(str)
    str = str:gsub("\2", "\2\2")
    str = str:gsub("\1", "\2\1")
    str = str:gsub("\0", "") -- No nulls
    return str
end

-- Pool a string.
-- @param str
-- @return ID
function PCDWriter:PoolString(str)
    if not self.StringsIndex[str] then
        self.StringsIndex[str] = table.insert(self.Strings, str)
    end
    return self.StringsIndex[str]
end

-- Serialize values for the table.
-- @param val
-- @return Serialized
function PCDWriter:SerializeTableKV(val)
    local t = type(val)
    
    if val == nil then return "0"
    elseif t == "string" and val == "" then return "S"
    elseif t == "string" then return "s" .. self:PoolString(val)
    elseif t == "number" then return "n" .. val
    elseif t == "boolean" and val == true then return "T"
    elseif t == "boolean" and val == false then return "F"
    elseif t == "Vector" then
        return string.format("v%g,%g,%g", val.x, val.y, val.z)
    elseif t == "Angle" then
        return string.format("a%g,%g,%g", val.p, val.y, val.r)
    elseif t == "Player" then return "p" .. val:UniqueID()
    elseif t == "table" then
        if not self.TableIndex[val] then
            self.TableIndex[val] = self.TableIndexN
            self.TableIndexN = self.TableIndexN + 1
            table.insert(self.TableQueue, val)
        end
        return "t" .. self.TableIndex[val]
    else
        self:Warn("Could not serialize type '" .. t .. "'")
        return "0"
    end
end

--- Prepares for a table to be written.
-- @param head Head table
-- @param endFunc Function to advance to after finishing
function PCDWriter:PrepareTableWrite(head, endFunc)
    self.TableIndex = {}
    self.TableIndex[head] = 0
    self.TableIndexN = 1
    self.TableQueue = { head }
    self.ConcludeFunc = endFunc
    self.Index = 1
    self.TableBuffer = putil.Buffer()
    self.CurTable = nil
    self.CurTableIndex = nil
    self.NextSeq = 1
    self.InSeq = true
end

--- Write a table.
-- @param data
function PCDWriter:_WriteTable()
    self:SetNext(0.1)
    
    -- Store the number of table values we've already stored so that we can
    -- limit the number that we serialize per run
    local processed = 0
    
    while true do
        if self.CurTable then -- We have an iterator to call
            while true do
                local k, v = next(self.CurTable, self.CurTableIndex)
                if not k then break end -- No more table
                self.CurTableIndex = k
                
                -- Store the table sequentially until we hit a non-sequential
                -- portion (this may save some space on mixed tables)
                if self.NextSeq ~= k then self.InSeq = false end
                self.NextSeq = self.NextSeq + 1
                
                if self.InSeq then
                    self.TableBuffer:Write(self:SerializeTableKV(v))
                else
                    self.TableBuffer:Write(self:SerializeTableKV(k))
                    self.TableBuffer:Write("\2") -- Key/value seperator
                    self.TableBuffer:Write(self:SerializeTableKV(v))
                end
                
                self.TableBuffer:Write("\3") -- Key/value end
                
                -- Cap the number of key/values serialized per run
                processed = processed + 1
                if processed > self.SerializationRate then
                    return
                end
            end
            
            self.TableBuffer:Write("\1") -- Table end
        end
        
        -- Get the next table
        local t = table.remove(self.TableQueue, 1)
        if not t then
            self.CurTable = nil
            self:SetNext(0.1, self.ConcludeFunc)
            return
        end
        
        self.TableBuffer:Write(tonumber(self.TableIndex[t]))
        self.TableBuffer:Write("\1") -- Table start
        
        -- Set up the next table to run through
        self.CurTable = t
        self.CurTableIndex = nil
        self.NextSeq = 1
        self.InSeq = true
    end
end

--- Write the header.
-- @param data
function PCDWriter:_WriteHeader()
    local ver = 1
    -- 89 P C O P Y 1A \r \n version
    self.Buffer:Write(string.char(137, 80, 67, 79, 80, 89, 26, 13, 10, ver))
    
    local header = putil.Buffer()
    for k, v in pairs(self.Header) do
        header:Write(self:EscapeKV(k))
        header:Write(string.char(1))
        header:Write(self:EscapeKV(v))
        header:Write(string.char(1))
    end
    self:WriteChunk("info", header:GetValue())
    
    -- Write entity data
    self:SetProgress(5)
    self:PrepareTableWrite(self.Clipboard:GetEntityData(), self._WriteConstraints)
    self:SetNext(0.1, self._WriteTable)
end

--- Write the constraints.
-- @param data
function PCDWriter:_WriteConstraints()
    self:WriteChunk("ents", self.TableBuffer:GetValue())
    
    -- Write constraint data
    self:SetProgress(40)
    self:PrepareTableWrite(self.Clipboard:GetConstraintData(),
                           self._FinishConstraints)
    self:SetNext(0.1, self._WriteTable)
end

--- Write constraints to main file buffer.
-- @param data
function PCDWriter:_FinishConstraints()
    self:WriteChunk("cons", self.TableBuffer:GetValue())
    self:PrepareTableWrite({}, false) -- GC
    
    self:SetProgress(80)
    self.CurTableIndex = 1
    self.StringsBuffer = putil.Buffer()
    self:SetNext(0, self._WriteStrings)
end

--- Write strings.
-- @param data
function PCDWriter:_WriteStrings()
    self:SetNext(0.1)
    
    for i = 1, self.SerializationRate do
        local str = self.Strings[self.CurTableIndex]
        
        if not str then
            self:WriteChunk("strs", self.StringsBuffer:GetValue())
            self:SetNext(0.1, self._Finish)
            return
        end
        
        self.StringsBuffer:Write(self:EscapeKV(str))
        self.StringsBuffer:Write(string.char(1))
        
        self.CurTableIndex = self.CurTableIndex + 1
    end
end

-- Finish up.
-- @param data
function PCDWriter:_Finish()
    self.Output = self.Buffer:GetValue()
    
    -- Free references for the GC
    self.Data = nil
    self.Buffer = nil
    self.Strings = nil
    self.StringsIndex = nil
    
    self:SetProgress(100)
    self:SetNext(0, false)
end

AccessorFunc(PCDWriter, "Header", "Header")

------------------------------------------------------------
-- Reader
------------------------------------------------------------

local PCDReader = putil.CreateClass(photocopy.Reader)

--- Construct the PCD reader.
-- @param data
function PCDReader:__construct(data)
    photocopy.Reader.__construct(self, data)
    
    self.DeserializationRate = GetConVar("photocopy_pcd_deserialization_rate"):GetInt()
    
    self.Header = {}
    self.Strings = {}
    self.EntityData = {}
    self.ConstraintData = {}
    self:SetNext(0, self._ParseHeader)
end

-- Unescape the values for the key/value sections.
-- @param str
-- @return Escaped
function PCDReader:UnescapeKV(str)
    str = str:gsub("\2\1", "\1")
    str = str:gsub("\2\2", "\2")
    return str
end

-- Read a integer that is free of nulls.
-- @param str
-- @param offset
function PCDReader:ParseNLInt(str, offset)
    local a = string.byte(str, offset + 1) - 1
    local b = string.byte(str, offset + 2) - 1
    local c = string.byte(str, offset + 3) - 1
    local d = string.byte(str, offset + 4) - 1
    return a * 16581375 + b * 65025 + c * 255 + d
end

-- Deserialize values for the table.
-- @param val
-- @return Serialized
function PCDReader:DeserializeTableKV(val)
    local t = val:sub(1, 1)
    
    if val == "0" then return nil
    elseif val == "S" then return ""
    elseif t == "s" then
        local index = tonumber(val:sub(2))
        if not index then
            self:Warn("Non-numeric string index detected")
            return ""
        else
            local str = self.Strings[index]
            if not str then
                self:Warn("Unpooled string of index '%d' detected", index)
                self.Strings[index] = ""
                return ""
            else
                return str
            end
        end
    elseif t == "n" then return tonumber(val:sub(2)) or 0
    elseif t == "T" then return true
    elseif t == "F" then return false
    elseif t == "v" then
        local x, y, z = val:sub(2):match("([^,]+),([^,]+),([^,]+)")
        return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    elseif t == "a" then
        local p, y, r = val:sub(2):match("([^,]+),([^,]+),([^,]+)")
        return Angle(tonumber(p) or 0, tonumber(y) or 0, tonumber(r) or 0)
    elseif t == "p" then return player.GetByUniqueID(val:sub(2))
    elseif t == "t" then
        local id = val:sub(2)
        if not self.TableIndex[id] then
            self.TableIndex[id] = {}
        end
        return self.TableIndex[id]
    else
        self:Warn("Could not deserialize type '" .. t .. "'")
        return nil
    end
end

--- Prepares for a table to be read.
-- @param key Chunk key to deserialize
-- @param endFunc Function to advance to after finishing
function PCDReader:PrepareTableRead(key, endFunc)
    self.TableIndex = {}
    self.HeadTable = nil
    self.ConcludeFunc = endFunc
    self.CurTableDataIter = self.ChunkIndex[key]:gmatch("([^\1]+)\1([^\1]+)\1")
    self.CurTable = nil
    self.CurKVIter = nil
end

--- Read a table.
-- @param data
function PCDReader:_ReadTable()
    self:SetNext(0.1)
    
    local processed = 0
    
    while true do
        if self.CurKVIter then -- We have an iterator to call
            while true do
                local kv = self.CurKVIter()
                if not kv then break end
                
                local k, v = kv:match("^([^\2]+)\2(.*)$")
                if k then
                    local k = self:DeserializeTableKV(k)
                    local v = self:DeserializeTableKV(v)
                    if k then
                        self.CurTable[k] = v
                    else
                        self:Warn("Nil table index detected")
                    end
                else
                    table.insert(self.CurTable, self:DeserializeTableKV(kv))
                end
                
                -- Cap the number of key/values serialized per run
                processed = processed + 1
                if processed > self.DeserializationRate then
                    return
                end
            end
        end
        
        -- Get the next table
        local id, data = self.CurTableDataIter()
        if not id then
            self:SetNext(0.1, self.ConcludeFunc)
            return
        end
        
        self.TableIndex[id] = self.TableIndex[id] or {}
        self.CurTable = self.TableIndex[id]
        if not self.HeadTable then
            self.HeadTable = self.CurTable
        end
        self.CurKVIter = data:gmatch("([^\3]+)\3")
    end
end

--- Write the header.
-- @param data
function PCDReader:_ParseHeader()
    local bytes = string.char(137, 80, 67, 79, 80, 89, 26)
    
    if self.Data:sub(1, string.len(bytes)) ~= bytes then
        self:SetError("Not a valid PCOPY file")
        return
    end
    
    if string.len(self.Data) < 10 then
        self:SetError("File is incomplete")
        return
    end
    
    -- ASCII transfer detection
    local c1 = self.Data:sub(8, 8)
    local c2 = self.Data:sub(9, 9)
    local shift = 0
    
    if c1 == "\r" and c2 == "\n" then
        -- Good
    elseif c1 == "\r" or c1 == "\n" then
        self:Warn("This file was not properly transferred as binary; this file may be corrupt")
        shift = -1
    else
        self:SetError("PCOPY file is corrupt")
        return
    end
    
    local ver = string.byte(self.Data:sub(10))
    if ver ~= 1 then
        self:SetError("File is not an expected version 1")
        return
    end
    
    self.ChunkData = self.Data:sub(11 + shift)
    self.Chunks = {}
    self.ChunkIndex = {}
    self.Offset = 0
    self.ChunkDataSize = string.len(self.ChunkData)
    
    -- Parse chunks
    self:SetProgress(5)
    self:SetNext(0.1, self._ParseChunks)
end

--- Parse the chunks.
-- @param data
function PCDReader:_ParseChunks()
    self:SetNext(0.1)
    
    for i = 1, 10 do -- Not yet benchmarked
        local identifier = self.ChunkData:sub(self.Offset + 1, self.Offset + 4)
        local len = self:ParseNLInt(self.ChunkData, self.Offset + 4)
        local data
        if self.Offset + 8 + len > self.ChunkDataSize then
            data = self.ChunkData:sub(self.Offset + 9)
            self:Warn("'%s' chunk was truncated", identifier)
        else
            data = self.ChunkData:sub(self.Offset + 9, self.Offset + 8 + len)
        end
        self.Offset = self.Offset + 8 + len
        
        local index = table.insert(self.Chunks, { identifier, data })
        self.ChunkIndex[identifier] = data
        -- In Lua, there is only one copy of a string (and they are immutable)
        
        if self.Offset >= self.ChunkDataSize then
            if self.ChunkIndex.info then
                self.CurIter = self.ChunkIndex.info:gmatch("([^\1]+)\1([^\1]+)\1")
                self:SetProgress(25)
                self:SetNext(0.1, self._ParseInfo)
            else -- No info chunk?
                self:SetError("File is missing the 'info' chunk")
            end
            
            return
        end
    end
end

--- Parse the info chunk.
-- @param data
function PCDReader:_ParseInfo()
    self:SetNext(0.1)
    
    local processed = 0
    
    while true do
        local k, v = self.CurIter()
        if not k then
            if self.ChunkIndex.strs then
                self.CurIter = self.ChunkIndex.strs:gmatch("([^\1]+)\1")
                self:SetProgress(35)
                self:SetNext(0.1, self._ParseStrings)
            else -- No info chunk?
                self:SetError("File is missing the 'strs' chunk")
            end
            
            return
        end
        
        self.Header[self:UnescapeKV(k)] = self:UnescapeKV(v)
        
        processed = processed + 1
        if processed >= self.DeserializationRate then
            return
        end
    end
end

--- Parse the strs chunk.
-- @param data
function PCDReader:_ParseStrings()
    self:SetNext(0.1)
    
    local processed = 0
    
    while true do
        local v = self.CurIter()
        if not v then
            if self.ChunkIndex.ents then
                self:SetProgress(50)
                self:PrepareTableRead("ents", self._ParseConstraints)
                self:SetNext(0.1, self._ReadTable)
            else -- No ents chunk?
                self:SetError("File is missing the 'ents' chunk")
            end
            
            return
        end
        
        local index = table.insert(self.Strings, self:UnescapeKV(v))
        
        processed = processed + 1
        if processed >= self.DeserializationRate then
            return
        end
    end
end

--- Parse the constraints chunk (after the entities chunk).
-- @param data
function PCDReader:_ParseConstraints()
    self.EntityData = self.HeadTable or {}
    
    if self.ChunkIndex.cons then
        self:SetProgress(75)
        self:PrepareTableRead("cons", self._Finish)
        self:SetNext(0.1, self._ReadTable)
    else
        self:SetError("File is missing the 'cons' chunk")
    end
end

--- Finish up.
-- @param data
function PCDReader:_Finish()
    self.ConstraintData = self.HeadTable or {}
    
    local clipboard = photocopy.Clipboard(self:GetOriginPos())
    clipboard:SetEntityData(self.EntityData)
    clipboard:SetConstraintData(self.ConstraintData)
    self:SetClipboard(clipboard)
    
    -- Free references for the GC
    self.Data = nil
    self.Strings = nil
    self.EntityData = nil
    self.ConstraintData = nil
    
    self:SetProgress(100)
    self:SetNext(0, false)
end

--- Get the original position of the save. This should only be called after
-- the file has been fully loaded.
-- @return Vector
function PCDReader:GetOriginPos()
    if self.Header.OriginPos then
		local x, y, z = self.Header.OriginPos:match("^([^,]+),([^,]+),([^,]+)$")
		return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    end
    return Vector(0, 0, 0)
end

------------------------------------------------------------

photocopy.RegisterFormat("PhotocopyDupe", PCDReader, PCDWriter)