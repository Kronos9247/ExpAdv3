--[[
	   ____      _  _      ___    ___       ____      ___      ___     __     ____      _  _          _        ___     _  _       ____   
	  F ___J    FJ  LJ    F _ ", F _ ",    F ___J    F __".   F __".   FJ    F __ ]    F L L]        /.\      F __".  FJ  L]     F___ J  
	 J |___:    J \/ F   J `-' |J `-'(|   J |___:   J (___|  J (___|  J  L  J |--| L  J   \| L      //_\\    J |--\ LJ |  | L    `-__| L 
	 | _____|   /    \   |  __/F|  _  L   | _____|  J\___ \  J\___ \  |  |  | |  | |  | |\   |     / ___ \   | |  J |J J  F L     |__  ( 
	 F L____:  /  /\  \  F |__/ F |_\  L  F L____: .--___) \.--___) \ F  J  F L__J J  F L\\  J    / L___J \  F L__J |J\ \/ /F  .-____] J 
	J________LJ__//\\__LJ__|   J__| \\__LJ________LJ\______JJ\______JJ____LJ\______/FJ__L \\__L  J__L   J__LJ______/F \\__//   J\______/F
	|________||__/  \__||__L   |__|  J__||________| J______F J______F|____| J______F |__L  J__|  |__L   J__||______F   \__/     J______F 

	::Expression 3 Base::
]]

print("expr3->cl_init");
include("shared.lua");

--[[
]]

function ENT:Initialize( )
end

--[[
]]

net.Receive("Expression3.RequestUpload", function(len)
	local ent = net.ReadEntity();

	print("Upload request recived:", ent, IsValid(ent), ent.SubmitToServer);

	timer.Create("Expression3.SubmitToServer", 1, 1, function()
		if (IsValid(ent) and ent.SubmitToServer) then
			print("Submitting to server!");
			ent:SubmitToServer(Golem.GetCode( ));
		end
	end);
end)

function ENT:SubmitToServer(code)
	if (code and code ~= "") then
		net.Start("Expression3.SubmitToServer");
			net.WriteEntity(self)
			net.WriteString(code);
		net.SendToServer();
	end
end

--[[
]]

net.Receive("Expression3.SendToClient", function(len)
	local ent = net.ReadEntity();
	local ply = net.ReadEntity();
	local script = net.ReadString();

	if (script and script ~= "") then
		if (ent and IsValid(ent) and ent.ReceiveFromServer) then
			if (ply and IsValid(ply)) then
				ent:ReceiveFromServer(ply, script);
			end
		end
	end
end);

function ENT:ReceiveFromServer(ply, script)
	print("CLIENT");
	print("Reciveied:", self, ply);
	print(script);
	print("----------------------");

	timer.Simple(1, function()
		if (IsValid(self)) then
			self:SetCode(script, true);
		end
	end);
end

function ENT:PostInitScript()

end

--[[
]]

function ENT:DrawTranslucent()
	self:Draw()
end

function ENT:Draw()
	self:DrawModel( )
end

--[[
]]

function ENT:BeingLookedAtByLocalPlayer()
	if ( LocalPlayer():GetEyeTrace().Entity != self ) then return false end
	if ( LocalPlayer():GetViewEntity() == LocalPlayer() && LocalPlayer():GetShootPos():Distance( self:GetPos() ) > 256 ) then return false end
	if ( LocalPlayer():GetViewEntity() ~= LocalPlayer() && LocalPlayer():GetViewEntity():GetPos():Distance( self:GetPos() ) > 256 ) then return false end

	return true
end

function ENT:GetCreatorName()
	local owner = self:CPPIGetOwner();

	if (owner == nil) then
		return "unowned/world";
	end

	if (not IsValid(owner)) then
		return "Disconnected";
	end

	return owner:GetName();
end

function ENT:GetOverlayText()
	return table.concat({
		"::Expression (adv) 3::",
		self:GetCreatorName(),
		"SV average: " .. self:GetServerAverageCPU(),
		"SV total:" .. self:GetServerTotalCPU(),
		"SV warning:" .. tostring(self:GetServerWarning()),
		"CL average: " .. self:GetClientAverageCPU(),
		"CL total:" .. self:GetClientTotalCPU(),
		"CL warning:" .. tostring(self:GetClientWarning()),
	}, "\n");
end