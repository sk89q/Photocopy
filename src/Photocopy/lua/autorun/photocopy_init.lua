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

if SERVER then
	AddCSLuaFile("includes/modules/photocopy.lua")
	AddCSLuaFile("includes/modules/photocopy.util.lua")
	AddCSLuaFile("autorun/photocopy_init.lua")
end

local list = file.FindInLua("photocopy/formats/*.lua")
for _, f in pairs(list) do
	MsgN("Photocopy: Auto-loading format file: " .. f)
	if SERVER then
		AddCSLuaFile("photocopy/formats/"..f)
	end
    include("photocopy/formats/" .. f)
end

