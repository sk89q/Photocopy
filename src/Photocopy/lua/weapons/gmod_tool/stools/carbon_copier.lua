TOOL.Category		= "Construction"
TOOL.Name			= "#Carbon Copier Duplicator"
TOOL.Command		= nil
TOOL.ConfigName		= ""

TOOL.ClientConVar["offsetx"] = "0"
TOOL.ClientConVar["offsety"] = "0"
TOOL.ClientConVar["offsetz"] = "0"

TOOL.ClientConVar["offsetp"] = "0"
TOOL.ClientConVar["offsety"] = "0"
TOOL.ClientConVar["offsetr"] = "0"

TOOL.ClientConVar["gravtext"] = "0"
TOOL.ClientConVar["drawindicator"] = "0"
TOOL.ClientConVar["size"] = "1"

local photocopy = require("photocopy")
local putil = require("photocopy.util")

if CLIENT then
	language.Add( "Tool_carbon_copier_name", "Carbon Copier duplicator tool" )
	language.Add( "Tool_carbon_copier_desc", "Duplicate an entity, or a group of constrained entities" )
	language.Add( "Tool_carbon_copier_0", "Primary: Select (+Use to select constrained entities, +Shift to radius select +Reload to clear selection)   Secondary: Get total mass   Reload: Get centre of gravity for contraption" )
	//language.Add( "Tool_carbon_copier_radius", "Radius Select" )
	//language.Add( "Tool_carbon_copier_radius_desc", "Select props within a certain radius" )

	cvars.AddChangeCallback("carbon_copier_offsetz",function(name,pvalue,curvalue)
		local tool = LocalPlayer():GetTool()
		if tool.Mode == "carbon_copier" then
			tool.clGhoster:SetOffset(tonumber(curvalue))
		end
		
	end)
end

local function OpenDupe( ply , cmd , args )
	local tool = ply:GetTool()
	if tool.Mode == "carbon_copier" and args[1] then
		tool:OpenDupe( args[1] )
	end
end
concommand.Add("cc_opendupe" , OpenDupe )

local function onreadsuccess( self , tool )
	tool.clipboard = self:GetClipboard()

	tool.ClientConVar.offsetz = tool:GetDistanceFromGround(tool.clipboard)
	
	tool.svGhoster:Initialize( tool.clipboard , tool:GetClientInfo("offsetz") )
	tool.svGhoster:Start()
end

function TOOL:OpenDupe( path )
	path = self.Path .. path
	local data = file.Read(path)
	
	local reader = photocopy.GetReader("PhotocopyDupe")(data , 0)
	reader:Start(onreadsuccess,nil,self)
end

function TOOL:GetDistanceFromGround( clipboard )
	local tr = {}
	tr.start = clipboard:GetOffset()
	tr.endpos = clipboard:GetOffset() + Vector(0,0,-100000)
	tr.mask = MASK_NPCSOLID_BRUSHONLY
	return util.TraceLine( tr ).Fraction * 100000
end


function TOOL:SendDupeFileInfo()
	
	local ply = self:GetOwner()
	local id = ply:SteamID():gsub(":","_")
	local path
	if SinglePlayer() then 
		path = "photocopy/localplayer/"
	else
		path = "photocopy/"..id.."/"
	end
	self.Path = path

	local root = "base"
	local function recursefind( dir , folders , files )
		dir = dir:gsub("*","")
		local root = string.match( dir , ".*/(.+)$" ):gsub("/","")

		umsg.Start("cc_fileinfo_folders" , ply )
			if #folders > 0 then
				umsg.Short(#folders)
				umsg.String(root)
				for i = 1 , #folders do
					local folder = folders[i]
					umsg.String(folder)
				end
			end
		umsg.End()
		umsg.Start("cc_fileinfo_files" , ply )
			if #files > 0 then
				umsg.Short(#files)
				umsg.String(root)
				for i = 1 , #files do
					local file = files[i]
					umsg.String(file)
				end
			end
		umsg.End()
		for i = 1 , #folders do
			file.TFind(dir..folders[i].."/*" , recursefind)
		end
	end

	file.TFind("data/"..path .. "*" , recursefind)
end


function TOOL:Initialize()
	if CLIENT then
		self.LastThink = CurTime()

		self.clGhoster = photocopy.Ghoster()
		self.clNetworker = photocopy.clFileNetworker()
	else
		self.svGhoster = photocopy.svGhoster( self:GetOwner() )
		self.svNetworker = photocopy.svFileNetworker()

		self:SendDupeFileInfo()
	end
end

function TOOL:LeftClick( trace )
	if CLIENT then return true end
	local ply = self:GetOwner()
	local hitpos = trace.HitPos + Vector(0,0,self:GetClientInfo("offsetz"))

	
	local paster = photocopy.Paster(self.clipboard, ply , hitpos , Angle(0, 0, 0))

	paster:SetSpawnFrozen(true)
	paster:Start(function()
	    ply:PrintMessage(HUD_PRINTTALK, "Paste done!")
	end)
	
	return true
end

function TOOL:RightClick( trace )
	if CLIENT then return true end
	local ent = trace.Entity
	if !IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then return end

	self.clipboard = photocopy.Clipboard( ent:LocalToWorld( ent:OBBCenter() ) )
	self.clipboard:Copy(ent)

	local offsetz = self:GetDistanceFromGround( self.clipboard )
	self:GetOwner():ConCommand("carbon_copier_offsetz "..tostring(offsetz))

	self.svGhoster:Initialize( self.clipboard , self:GetDistanceFromGround( self.clipboard ) )
	self.svGhoster:Start()

	
	return true
end


function TOOL:Reload( trace )
	if SERVER then
		self:SendDupeFileInfo()
	end
	--[[
	self:Initialize()
	if CLIENT then 
		if not self.Ghoster then
			self.Ghoster = photocopy.Ghoster()
		else
			self.Ghoster:RemoveGhosts()
			self.Ghoster:Stop()
			//self.Ghoster = photocopy.Ghoster()
		end

		return true
	end
	//local networker = photocopy.NetWorker( self:GetOwner() , self.clipboard )
	--]]
	
	return true
end


function TOOL:Think()
	if !self.Initialized then
		self:Initialize()
		self.Initialized = true
	end
	if CLIENT then
		if CurTime() > (self.LastThink + 0.2) then
			self:Deploy()
		end
		self.LastThink = CurTime()
		if SinglePlayer() then
			if LocalPlayer():GetTool() == self then 
				if LocalPlayer():KeyDown(IN_RELOAD) then
					self.SWEP:Reload()
				elseif LocalPlayer():KeyDown(IN_ATTACK) and !LocalPlayer():KeyDownLast(IN_ATTACK) then
					self.SWEP:PrimaryAttack()
				elseif LocalPlayer():KeyDown(IN_ATTACK2) and !LocalPlayer():KeyDownLast(IN_ATTACK2) then
					self.SWEP:SecondaryAttack()
				end
			end
		end




	end
end

function TOOL:Deploy()
	if self.clGhoster and CLIENT then
		if self.clGhoster.hold and self.clGhoster.Initialized then
			self.clGhoster:Start()
			self.clGhoster:SetNext(0,self.clGhoster.ParentToMouse)
			self.clGhoster:HideGhosts(false)
			self.clGhoster.hold = false
		end
	end
end

function TOOL:Holster()
	if self.clGhoster and CLIENT then
		self.clGhoster:Stop()
		self.clGhoster:HideGhosts(true)
		self.clGhoster.hold = true
	end
end

if CLIENT then
	function TOOL.BuildCPanel( cp )

	end

	
end
