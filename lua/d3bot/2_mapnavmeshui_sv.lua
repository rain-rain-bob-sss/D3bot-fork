
return function(lib)

	util.AddNetworkString("d3bot_selecting")

	local from = lib.From

	local function getCursoredPosOrNil(pl)
		local trR = pl:GetEyeTrace()
		if not trR.Hit then return end
		return trR.HitPos
	end
	local function getCursoredNodeOrNil(pl)
		local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
		if not item or item.Type ~= "node" then return end
		return item
	end
	
	local selectedNodesOrNilByPl = {}
	local function hasSelection(pl) return selectedNodesOrNilByPl[pl] end
	local function getSelectedNodes(pl) return selectedNodesOrNilByPl[pl] or {} end
	local function clearSelection(pl)
		selectedNodesOrNilByPl[pl] = nil
		pl:SendLua(lib.GlobalK .. ".ClearMapNavMeshViewHighlights()")
	end
	local function trySelectCursoredNode(pl)
		local cursoredNodeOrNil = getCursoredNodeOrNil(pl)
		if not selectedNodesOrNilByPl[pl] then selectedNodesOrNilByPl[pl] = {} end
		table.insert(selectedNodesOrNilByPl[pl], cursoredNodeOrNil)
		if not cursoredNodeOrNil then return end
		pl:SendLua(lib.GlobalK .. ".HighlightInMapNavMeshView(" .. cursoredNodeOrNil.Id .. ")")
	end
	
	local function round(num) return math.Round(num * 10) / 10 end
	
	local function setPos(node, pos)
		node:SetParam("X", round(pos.x))
		node:SetParam("Y", round(pos.y))
		node:SetParam("Z", round(pos.z))
	end
	
	local function getCursoredDirection(ang) return math.Round(math.abs(math.abs(ang) - 90) / 90) end
	local function getCursoredAxisName(pl, excludeZOrNil)
		local angs = pl:EyeAngles()
		if not excludeZOrNil and getCursoredDirection(angs.p) == 0 then return "Z" end
		return getCursoredDirection(angs.y) == 1 and "X" or "Y"
	end

	local function setParam(link,name,value)
		lib.MapNavMesh.ItemById[lib.DeserializeNavMeshItemId(link.Id)]:SetParam(name, value)
		lib.lastParamKey = name
		lib.lastParamValue = value
	end
	
	local editModes = {
		{	
			Name = "Create Node",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local node = lib.MapNavMesh:NewNode()
					setPos(node, cursoredPos)
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Link Nodes",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end 
			} 
		},
		{	
			Name = "Merge/Split/Extend Nodes",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						selectedNode:MergeWithNode(node)
						clearSelection(pl)
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end,
				[IN_ATTACK2] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then return end
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl, true)
					if not selectedNode:Split(cursoredPos, cursoredAxisName) then
						selectedNode:Extend(cursoredPos, cursoredAxisName)
					end
					clearSelection(pl)
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Reposition Node",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local cursoredPos = getCursoredPosOrNil(pl)
						if not cursoredPos then return end
						setPos(selectedNode, cursoredPos)
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end,
				[IN_ATTACK2] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then return end
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl)
					selectedNode:SetParam(cursoredAxisName, round(cursoredPos[cursoredAxisName:lower()]))
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Resize Node Area",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					clearSelection(pl)
					trySelectCursoredNode(pl)
				end,
				[IN_ATTACK2] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then return end
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl, true)
					local cursoredPosKey = cursoredAxisName:lower()
					local cursoredDimension = round(cursoredPos[cursoredPosKey])
					selectedNode:SetParam("Area" .. cursoredAxisName .. (cursoredDimension < selectedNode.Pos[cursoredPosKey] and "Min" or "Max"), cursoredDimension)
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Copy Nodes",
			FuncByKey = {
				[IN_ATTACK] = trySelectCursoredNode,
				[IN_ATTACK2] = function(pl)
					local cursoredPos = getCursoredPosOrNil(pl)
					if not cursoredPos then return end
					local cursoredAxisName = getCursoredAxisName(pl)
					local axisOffset
					local selectedNodes = getSelectedNodes(pl)
					local newNodeBySelectedNode = {}
					for idx, selectedNode in ipairs(selectedNodes) do
						if not axisOffset then axisOffset = round(cursoredPos[cursoredAxisName] - selectedNode.Pos[cursoredAxisName]) end
						local newNode = lib.MapNavMesh:NewNode()
						local offsetParamNamesSet = from{ cursoredAxisName, "Area" .. cursoredAxisName .. "Min", "Area" .. cursoredAxisName .. "Max" }:VsSet().R
						for name, v in pairs(selectedNode.Params) do newNode:SetParam(name, (offsetParamNamesSet[name] and v + axisOffset or v)) end
						newNodeBySelectedNode[selectedNode] = newNode
					end
					for idx, selectedNode in ipairs(selectedNodes) do
						local newNode = newNodeBySelectedNode[selectedNode]
						for linkedNode, link in pairs(selectedNode.LinkByLinkedNode) do
							local linkedNewNodeOrNil = newNodeBySelectedNode[linkedNode]
							if linkedNewNodeOrNil then lib.MapNavMesh:ForceGetLink(newNode, linkedNewNodeOrNil) end
						end
					end
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Set/Unset Last Parameter",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item or not lib.lastParamKey or not lib.lastParamValue then return end
					item:SetParam(lib.lastParamKey, lib.lastParamValue)
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end,
				[IN_ATTACK2] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item then return end
					if not item or not lib.lastParamKey then return end
					item:SetParam(lib.lastParamKey, "")
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Delete Item or Area",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item then return end
					item:Remove()
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end,
				[IN_ATTACK2] = function(pl)
					local item = lib.MapNavMesh:GetCursoredItemOrNil(pl)
					if not item then return end
					for idx, name in ipairs{ "AreaXMin", "AreaXMax", "AreaYMin", "AreaYMax" } do item:SetParam(name, "") end
					lib.MapNavMesh:InvalidateCache()
					lib.UpdateMapNavMeshUiSubscribers()
				end 
			} 
		},
		{	
			Name = "Link Nodes(Direction:Forward)",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						local link = lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						setParam(link,"Direction","Forward")
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end 
			} 
		},
		{	
			Name = "Link Nodes(Direction:Backward)",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						local link = lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						setParam(link,"Direction","Backward")
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end 
			} 
		},
		{	
			Name = "Link Nodes(Jumping:Needed)",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						local link = lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						setParam(link,"Jumping","Needed")
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end 
			} 
		},
		{	
			Name = "Link Nodes(Pouncing:Needed)",
			FuncByKey = {
				[IN_ATTACK] = function(pl)
					local selectedNode = getSelectedNodes(pl)[1]
					if not selectedNode then
						clearSelection(pl)
						trySelectCursoredNode(pl)
					else
						local node = getCursoredNodeOrNil(pl)
						if not node then return end
						local link = lib.MapNavMesh:ForceGetLink(selectedNode, node)
						clearSelection(pl)
						setParam(link,"Pouncing","Needed")
						lib.MapNavMesh:InvalidateCache()
						lib.UpdateMapNavMeshUiSubscribers()
					end
				end 
			} 
		},
	}
	
	local editModeByPl = {}
	
	local subscribers = {}
	local subscriptionTypeOrNilByPl = {}
	
	function lib.BeMapNavMeshUiSubscriber(pl) if not subscriptionTypeOrNilByPl[pl] then lib.SetMapNavMeshUiSubscription(pl, "view") end end
	function lib.SetMapNavMeshUiSubscription(pl, subscriptionTypeOrNil, isSpectator)
		local formerSubscriptionTypeOrNil = subscriptionTypeOrNilByPl[pl]
		if subscriptionTypeOrNil == formerSubscriptionTypeOrNil then return end
		subscriptionTypeOrNilByPl[pl] = subscriptionTypeOrNil
		if formerSubscriptionTypeOrNil == nil then
			table.insert(subscribers, pl)
			lib.UploadMapNavMesh(pl)

			if isSpectator then
				pl.m_LastPos = pl:GetPos()
				pl.m_LastEyeAngles = pl:EyeAngles()
				pl.m_Spectate = true

				pl.m_Weapons = {}
				for i, weap in ipairs(pl:GetWeapons()) do
					table.insert(pl.m_Weapons, {weap:GetClass(),weap:Clip1(),weap:Clip2()})
				end
				pl:StripWeapons()

				pl:KillSilent()
				pl:Spectate(OBS_MODE_ROAMING)
			elseif subscriptionTypeOrNil ~= "view" then
				pl:SetNWBool("D3Bot_NoWeapons",true)
				pl:SetActiveWeapon(NULL)
			end

			pl:SendLua(lib.GlobalK .. ".SetIsMapNavMeshViewEnabled(true)")
		elseif subscriptionTypeOrNil == nil then
			table.RemoveByValue(subscribers, pl)

			if pl.m_Spectate then
				pl:UnSpectate()
				pl:Spawn()

				pl:SetPos(pl.m_LastPos)
				pl:SetEyeAngles(pl.m_LastEyeAngles)

				pl.m_LastPos = nil
				pl.m_LastEyeAngles = nil
				pl.m_Spectate = nil
			end

			if pl.m_Weapons then
				for i, weap in pairs(pl.m_Weapons) do
					local wep = pl:Give(weap[1], true)
					wep:SetClip1(weap[2])
					wep:SetClip2(weap[3])
				end
			end

			pl.m_Weapons = nil
			pl:SetNWBool("D3Bot_NoWeapons",false)
			timer.Simple(0,function() pl:SelectWeapon(table.Random(pl:GetWeapons()):GetClass()) end)

			pl:SendLua(lib.GlobalK .. ".SetIsMapNavMeshViewEnabled(false)")
		end
		if formerSubscriptionTypeOrNil == "edit" then clearSelection(pl) end
		if subscriptionTypeOrNil == "edit" then
			editModeByPl[pl] = 1
			pl:SendLua(lib.GlobalK .. ".MapNavMeshEditMode = " .. 1)
		end
	end

	function lib.UpdateMapNavMeshUiSubscribers() lib.UploadMapNavMesh(subscribers) end
	
	local pathDebugTimerIdPrefix = tostring({}) .. "-"
	local function getPathDebugTimerId(pl) return pathDebugTimerIdPrefix .. pl:EntIndex() end
	function lib.ShowMapNavMeshPath(pl, pathOrEntA, nilOrEntB)
		if nilOrEntB == nil then
			local path = pathOrEntA
			pl:SendLua(lib.GlobalK .. ".SetShownMapNavMeshPath{" .. (","):Implode(from(path):SelV(function(node) return node.Id end).R) .. "}")
			lib.BeMapNavMeshUiSubscriber(pl)
			return
		end
		local entA = pathOrEntA
		local entB = nilOrEntB
		local timerId = getPathDebugTimerId(pl)
		timer.Remove(timerId)
		timer.Create(timerId, 0.1, 0, function()
			local navMesh = lib.MapNavMesh
			local nodeA = navMesh:GetNearestNodeOrNil(entA:GetPos())
			local nodeB = navMesh:GetNearestNodeOrNil(entB:GetPos())
			local abilities = {Walk = true, Jump = 250}
			lib.ShowMapNavMeshPath(pl, nodeA and nodeB and lib.GetBestMeshPathOrNil(nodeA, nodeB, nil, nil, abilities) or {}) -- Can't use any additional costs here, as they differ for each class
		end)
	end
	function lib.HideMapNavMeshPath(pl)
		timer.Remove(getPathDebugTimerId(pl))
		pl:SendLua(lib.GlobalK .. ".SetShownMapNavMeshPath{}")
	end

	hook.Add("KeyPress", tostring({}), function(pl, key)
		if subscriptionTypeOrNilByPl[pl] ~= "edit" then return end
		if key == IN_RELOAD then
			if hasSelection(pl) then
				clearSelection(pl)
			else
				editModeByPl[pl] = (editModeByPl[pl] % #editModes) + 1
				pl:SendLua(lib.GlobalK .. ".MapNavMeshEditMode = " .. editModeByPl[pl])
				pl:SetActiveWeapon(NULL)
			end
		else
			local func = editModes[editModeByPl[pl]].FuncByKey[key]
			if func then func(pl) end
		end
	end)

	hook.Add("PlayerButtonDown", tostring({}), function(pl, key)
		if subscriptionTypeOrNilByPl[pl] ~= "edit" then return end
		if key >= KEY_0 and key <= KEY_9 and editModeByPl[pl] ~= key - 1 then
			if editModes[key - 1] then
				if hasSelection(pl) then
					clearSelection(pl)
				end
				editModeByPl[pl] = key - 1
				pl:SendLua(lib.GlobalK .. ".MapNavMeshEditMode = " .. key - 1)
				pl:SetActiveWeapon(NULL)
			end
		end
	end)


	net.Receive("d3bot_selecting",function(len,ply)
		if subscriptionTypeOrNilByPl[ply] ~= "edit" then return end
		local current = editModeByPl[ply]
		local prev = net.ReadBool()
		local target
		if prev then
			target = current - 1
			if target <= 0 then target = #editModes end
		else
			target = math.Clamp((current % #editModes) + 1,1,#editModes)
		end
		editModeByPl[ply] = target
		ply:SendLua(lib.GlobalK .. ".MapNavMeshEditMode = " .. target)
		ply:SetActiveWeapon(NULL)
	end)
end
