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

photocopy = {}

--- Function to get a registered Photocopy reader.
-- @param fmt Format
function photocopy.GetReader(fmt)
    local fmtTable = list.Get("PhotocopyFormats")[fmt]
    if not fmtTable then return nil end
    return fmtTable.ReaderClass
end

--- Function to get a registered Photocopy writer.
-- @param fmt Format
function photocopy.GetWriter(fmt)
    local fmtTable = list.Get("PhotocopyFormats")[fmt]
    if not fmtTable then return nil end
    return fmtTable.WriterClass
end

--- Creates a new class (a table) that is callable.
-- @param parent Optional parent table (__index = parent)
-- @return Callable table
function photocopy.CreateClass(parent)
    local cls = {}
    
    return setmetatable(cls, {
        __call = function(self, ...)
            local args = {...}
            local instance = {}
            setmetatable(instance, { __index = cls })
            if cls.__construct then
                instance:__construct(unpack(args))
            elseif type(args[1]) == 'table' then
                for k, v in pairs(args[1]) do
                    instance[k] = v
                end
            end
            
            return instance
        end,
        __index = parent
    })
end

include("photocopy/common.lua")
include("photocopy/clipboard.lua")
include("photocopy/paster.lua")
include("photocopy/formats/adv_dupe.lua")
include("photocopy/formats/photocopy_dupe.lua")