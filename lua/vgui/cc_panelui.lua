local function getidx(tab,str)
	for i = 1 , #tab do
		if tab[i] == str then
			return i - 1
		end
	end
end

local function insertnode(base , name , bfolder)
	local idx
	if bfolder then
		base.subnodes[ #base.subnodes + 1 ] = "a"..name
		idx = getidx(base.subnodes,"a"..name)
	else
		base.subnodes[ #base.subnodes + 1 ] = "b"..name
		idx = getidx(base.subnodes,"b"..name)
	end
	table.sort(base.subnodes)
	PrintTable(base.subnodes)
	MsgN(idx)
	
	local pNode = vgui.Create( "DTree_Node", base )
	pNode:SetText( name )
	pNode:SetParentNode( base )
	if base.GetRoot then
		pNode:SetRoot( base:GetRoot() )
	else
		pNode:SetRoot( base )
	end

	pNode:SetVisible( true )
	pNode:SetParent( base:GetCanvas() or base.ChildNodes:GetCanvas() )
	table.insert( base.Items, idx, pNode )
	    
	base:InvalidateLayout()
	if base.ChildNodes then
		base.ChildNodes:InvalidateLayout()
	end
	return pNode
end


local PANEL = {}

function PANEL:Init()

	self.CategoryList = vgui.Create( "DPanelList" )
	self.CategoryList:SetAutoSize( true )
	self.CategoryList:SetSpacing( 5 )
	self.CategoryList:EnableHorizontal( false )
	self.CategoryList:EnableVerticalScrollbar( true )
		 
	    local CategoryContentFive = vgui.Create( "DCheckBoxLabel" )
	    CategoryContentFive:SetText( "All Talk" )
	    CategoryContentFive:SetConVar( "sv_alltalk" )
	    CategoryContentFive:SetValue( 1 )
	    CategoryContentFive:SizeToContents()
	CategoryList:AddItem( CategoryContentFive )
	 
	    local CategoryContentSix = vgui.Create( "DNumSlider" )
	    CategoryContentSix:SetSize( 150, 50 ) -- Keep the second number at 50
	    CategoryContentSix:SetText( "Max Props" )
	    CategoryContentSix:SetMin( 0 )
	    CategoryContentSix:SetMax( 256 )
	    CategoryContentSix:SetDecimals( 0 )
	    CategoryContentSix:SetConVar( "sbox_maxprops" )
	CategoryList:AddItem( CategoryContentSix )
	
	
	self:Invalidate()
	self:SetupEvents()
end


function PANEL:Invalidate()

	//self:AddFile()
end


function PANEL:SetupEvents()

	 
end

function PANEL:PerformLayout()
	self.BaseClass.PerformLayout(self)


	self:Invalidate()
end

vgui.Register( "CC_InfoPanel" , PANEL , "DPanelList" )


local PANEL = {}

function PANEL:Init()
	self.panelnames = {}
	self.panels = {}

	self.tree = vgui.Create("DTree",self)
	self.tree.subnodes = {}
	self.panelnames[self.tree] = ""
	self.formlist = vgui.Create("DPanelList" , self)
	self.formlist:EnableVerticalScrollbar(true)
	//self.formlist:SetDrawBackground(false)

	self.btnform = vgui.Create( "DForm", self )
	self.btnform.Paint = nil
	self.btnform:SetName( "Pasting Options" )
	self.formlist:AddItem(self.btnform)

	self.open = self.btnform:Button("Open")

	self.test = self.btnform:Button("PRESS ME")
	self.test.DoClick = function()
		insertnode(self.tree,"A TEST",false)
	end




	local SomeCollapsibleCategory = vgui.Create("DCollapsibleCategory", DermaPanel)
SomeCollapsibleCategory:SetPos( 25,50 )
SomeCollapsibleCategory:SetSize( 200, 50 ) -- Keep the second number at 50
SomeCollapsibleCategory:SetExpanded( 0 ) -- Expanded when popped up
SomeCollapsibleCategory:SetLabel( "Our Collapsible Category" )
 
CategoryList = vgui.Create( "DPanelList" )
CategoryList:SetAutoSize( true )
CategoryList:SetSpacing( 5 )
CategoryList:EnableHorizontal( false )
CategoryList:EnableVerticalScrollbar( true )
 
SomeCollapsibleCategory:SetContents( CategoryList ) -- Add our list above us as the contents of the collapsible category
 
    local CategoryContentOne = vgui.Create( "DCheckBoxLabel" )
    CategoryContentOne:SetText( "God Mode" )
    CategoryContentOne:SetConVar( "sbox_godmode" )
    CategoryContentOne:SetValue( 1 )
    CategoryContentOne:SizeToContents()
CategoryList:AddItem( CategoryContentOne ) -- Add the above item to our list
 
    local CategoryContentTwo = vgui.Create( "DCheckBoxLabel" )
    CategoryContentTwo:SetText( "Player Damage" )
    CategoryContentTwo:SetConVar( "sbox_plpldamage" )
    CategoryContentTwo:SetValue( 1 )
    CategoryContentTwo:SizeToContents()
CategoryList:AddItem( CategoryContentTwo )
 
    local CategoryContentThree = vgui.Create( "DCheckBoxLabel" )
    CategoryContentThree:SetText( "Fall Damage" )
    CategoryContentThree:SetConVar( "mp_falldamage" )
    CategoryContentThree:SetValue( 1 )
    CategoryContentThree:SizeToContents()
CategoryList:AddItem( CategoryContentThree )
 
    local CategoryContentFour = vgui.Create( "DCheckBoxLabel" )
    CategoryContentFour:SetText( "Noclip" )
    CategoryContentFour:SetConVar( "sbox_noclip" )
    CategoryContentFour:SetValue( 1 )
    CategoryContentFour:SizeToContents()
CategoryList:AddItem( CategoryContentFour )
 
    local CategoryContentFive = vgui.Create( "DCheckBoxLabel" )
    CategoryContentFive:SetText( "All Talk" )
    CategoryContentFive:SetConVar( "sv_alltalk" )
    CategoryContentFive:SetValue( 1 )
    CategoryContentFive:SizeToContents()
CategoryList:AddItem( CategoryContentFive )
 
    local CategoryContentSix = vgui.Create( "DNumSlider" )
    CategoryContentSix:SetSize( 150, 50 ) -- Keep the second number at 50
    CategoryContentSix:SetText( "Max Props" )
    CategoryContentSix:SetMin( 0 )
    CategoryContentSix:SetMax( 256 )
    CategoryContentSix:SetDecimals( 0 )
    CategoryContentSix:SetConVar( "sbox_maxprops" )
CategoryList:AddItem( CategoryContentSix )
 
    local CategoryContentSeven = vgui.Create( "DSysButton" )
    CategoryContentSeven:SetType( "close" )
    CategoryContentSeven.DoClick = function()
        RunConsoleCommand("sv_password", "toyboat")
    end
    CategoryContentSeven.DoRightClick = function()
        RunConsoleCommand("sv_password", "**")
    end
CategoryList:AddItem( CategoryContentSeven )


self.btnform:AddItem(SomeCollapsibleCategory)




	//local t = self.tree:AddNode("test")
	//self.panelnames[t] = "test"
	//for i = 1 , 25 do
//
	//	t = t:AddNode("Tank "..tostring(i).."-new barrel" )
	//	self.panelnames[t] = "Tank "..tostring(i).."-new barrel"
	//end



	
	//self:Invalidate()
	self:SetupEvents()
end


function PANEL:Invalidate()
	local w , h , pad = self:GetWide() , self:GetTall() , 12

	self.tree:SetSize(w-pad,h / 2)
	self.tree:AlignTop(pad/2)
	self.tree:AlignLeft(pad/2)

	self.formlist:SetSize(w-pad, ((h-self.tree:GetTall())- pad*1.5))
	self.formlist:MoveBelow( self.tree , pad/2)
	self.formlist:AlignLeft(pad/2)


	self.btnform:SetSize(w-pad, h / 2.2)
	self.btnform:AlignBottom(pad/2)
	self.btnform:AlignLeft(pad/2)




	//self:AddFile()
end


local FileIcons = {
    dll = "gui/silkicons/page_white_wrench",
    lua = "gui/silkicons/page",
    mdl = "gui/silkicons/brick_add",
    vmt = "gui/silkicons/table_edit",
    txt = "gui/silkicons/table_edit",
    vtf = "gui/silkicons/palette",
    tga = "gui/silkicons/palette",
    jpeg = "gui/silkicons/palette",
    mp3 = "gui/silkicons/sound",
    wav = "gui/silkicons/sound",
    bsp = "gui/silkicons/world"
}

function PANEL:Recursebase( path , base )
	if self.panelnames[base] == "" then
		return path
	end
	path = self.panelnames[base] .."/".. path
	if base.base then
		path = self:Recursebase(path , base.base)
	end
	return path
end

function PANEL:SetupEvents()
	local parent = self
	
	usermessage.Hook("cc_fileinfo_folders" , function(um)
		local amount = um:ReadShort()
		local root = um:ReadString()
		local base

		if self.panels[root] then
			base = self.panels[root]
		else
			base = self.tree
		end


		local folder

		for i = 1 , amount do
			folder = um:ReadString()
			local node = base:AddNode(folder)
			node.subnodes = {}
			base.subnodes[ #base.subnodes + 1 ] = "a"..folder
			node.base = base
			self.panelnames[ node ] = folder
			self.panels[ folder ] = node
			//self.foldermap[ #self.foldermap + 1 ] = folder
		end
	end)

	usermessage.Hook("cc_fileinfo_update" , function(um)
		local amount = um:ReadShort()
		local root = um:ReadString()
		local Type = um:ReadBool()
		local base

		if self.panels[root] then
			base = self.panels[root]
		else
			base = self.tree
		end

		if root then
			local folder
			for i = 1 , amount do
				folder = um:ReadString()
				local node = base:AddNode(folder)
				node.base = base
				self.panelnames[ node ] = folder
				self.panels[ folder ] = node
				//self.foldermap[ #self.foldermap + 1 ] = folder
			end
		else
			local file
			file = um:ReadString()
			local node = InsertNode(base,file,false)
			node.Icon:SetImage( FileIcons[ extension ] or "gui/silkicons/table_edit")

			node.base = base
			self.panelnames[ node ] = file
			self.panels[ file ] = AddNode
		end
	end)

	usermessage.Hook("cc_fileinfo_files" , function(um)
		local amount = um:ReadShort()
		local root = um:ReadString()
		local base

		if self.panels[root] then
			base = self.panels[root]
		else
			base = self.tree
		end

		local file
		for i = 1 , amount do
			file = um:ReadString()
			local node = base:AddNode(file)
			node.Icon:SetImage( FileIcons[ extension ] or "gui/silkicons/table_edit")
			base.subnodes[ #base.subnodes + 1 ] = "b"..file
			node.base = base
			self.panelnames[ node ] = file
			self.panels[ file ] = AddNode
			//self.filemap[ #self.filemap + 1 ] = file
		end
	end)


	function self.open:DoClick()
		local panel = parent.tree:GetSelectedItem()
		local name = parent.panelnames[panel] or ""
		if panel then
			if panel.base then
				name = parent:Recursebase( name , panel.base )
			end

			if string.GetExtensionFromFilename(name) == "txt" then
				RunConsoleCommand("cc_opendupe", name )
			end
		else
			notification.AddLegacy("Cannot open dupe (not a dupe file)", NOTIFY_ERROR, 5)
			surface.PlaySound( "buttons/button10.wav" )
		end
	end
	
	 
end


function PANEL:AddFile( folder , file )
	

end

function PANEL:PerformLayout()
	self.BaseClass.PerformLayout(self)


	self:Invalidate()
end

vgui.Register( "CC_PasteMenu" , PANEL , "DPanel" )

local PANEL = {}

function PANEL:Init()
	self.sheet = vgui.Create("DPropertySheet" , self )
	self.sheet:AddSheet("Pasting", vgui.Create("CC_PasteMenu") , nil , false,false , "Paste your contraptions")
	self.sheet:AddSheet("Options", vgui.Create("DButton") , nil , false,false , "Paste your contraptions")

end
function PANEL:Paint() end


function PANEL:Invalidate()
	local w , h , pad = self:GetWide() , self:GetTall() , 12

	self.sheet:SetSize(w,h)
	self.sheet:Center()

end

local CPanel_Width = 281
function PANEL:PerformLayout()
    //self.BaseClass:PerformLayout( self )
    self:SetSize(CPanel_Width,ScrH()-106)
    self:Invalidate()
end
vgui.Register("CC_Base",PANEL,"DPanel")


//local f = vgui.Create("DFrame")
//f:SetSize( 300 , 900)
//f:Center()
//f:MakePopup()
//local gc = vgui.Create("CC_Base",f)
//gc:Dock(FILL)


concommand.Add("cc_reloadui",function(ply,cmd,args)
	local info = debug.getinfo(1, "S")

	if info && info.short_src then
		local src = info.short_src

		local start , End = string.find(src , "lua\\")
		src = string.sub(src, End , #src)
		
		MsgN("Reloading (" .. src .. ")...")
		include(src)
	end
end)
