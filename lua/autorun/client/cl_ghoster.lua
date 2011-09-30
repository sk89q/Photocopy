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
local photocopy = require("photocopy")

------------------------------------------------------------
-- Ghoster
------------------------------------------------------------
local Ghoster = putil.CreateClass(putil.IterativeProcessor)

--creates the ghoster class, used for controlling all ghosts
function Ghoster:__construct()
	local info = debug.getinfo(3)
    MsgN(string.GetFileFromFilename(info.short_src)," at line ",info.currentline)
    self.Ghosts = {}
    self.Parent = nil
    self.Ply = LocalPlayer()
    self.offset = Vector(0,0,0)

    self:Hook()
end

function Ghoster:Hook()
	local function GetInit( um )
		if self.Initialized then
			self:RemoveGhosts()
		end
		self.Parent = um:ReadEntity()
		self.offset = Vector(um:ReadFloat(),um:ReadFloat(),um:ReadFloat())
		self.Pos = self.Parent:GetPos()
		self.Ang = self.Parent:GetAngles()

		self.Initialized = true

		self:ParentToMouse()
		self:SetNext(0,self.ParentToMouse)
		self:Start()
	end
	usermessage.Hook( "photocopy_ghost_init" , GetInit)

	local function GetInfo(um)
		local model = um:ReadString()
	    local pos = Vector( um:ReadFloat() , um:ReadFloat() , um:ReadFloat() )
	    local angle = Angle( um:ReadFloat() , um:ReadFloat() , um:ReadFloat() ) 

	    pos , angle = LocalToWorld(pos, angle, self.Pos, self.Ang)

	    local ent = ClientsideModel( model )
	    ent:SetModel( model )
	    ent:SetAngles( angle )
	    ent:SetPos( pos )
	    ent:SetParent(self.Parent)
	    self.Ghosts[ent] = ent

	    self:SetAlpha(150)
	end
	usermessage.Hook("photocopy_ghost_info",GetInfo)
end

function Ghoster:SetOffset( x , y , z )
	self.offset.x = x or self.offset.x
	self.offset.y = y or self.offset.y
	self.offset.z = z or self.offset.z
end

function Ghoster:ParentToMouse()
	if self.Initialized then
		local Pos = LocalPlayer():GetEyeTraceNoCursor().HitPos + self.offset
		self.Pos = Pos
		self.Parent:SetPos( Pos )
		self:SetNext(0)
	end
end

function Ghoster:RemoveGhosts()
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:Remove()
		end
		self.Initialized = false
		self.Ghosts[ent] = nil
	end
end

function Ghoster:HideGhosts( b )
	if b then self:Stop() else self:SetNext(0) end
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:SetNoDraw(b)
		else
			self.Ghosts[k] = nil
		end
	end
end

function Ghoster:SetAlpha(alpha)
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:SetColor(255,255,255 ,alpha)
		else
			self.Ghosts[k] = nil
		end
	end
end

photocopy.Ghoster = Ghoster