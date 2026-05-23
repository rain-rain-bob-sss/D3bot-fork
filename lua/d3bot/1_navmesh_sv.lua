--- TODO: Implement LZMA navmesh saving

local function AutoSave()
	local Directory = "d3bot/navmesh/backups"
	local DirectoryToSaveIn = Directory.."/"..game.GetMap()..".txt"

	local mapmesh = D3bot.MapNavMesh
	local should_runfunction = not (#mapmesh.Params == 0 and #mapmesh.LinkById == 0 and #mapmesh.ItemById == 0 and #mapmesh.NodeById == 0)
	if not should_runfunction then return end
	local saved = file.Read(D3bot.MapNavMeshPath, "DATA")
	local savedbackup = file.Read(DirectoryToSaveIn, "DATA")
	local tosave = D3bot.MapNavMesh:SerializeSorted()

	if not (saved == tosave or savedbackup == tosave) then -- Don't mind this line.
		file.CreateDir(Directory)
		file.Write(DirectoryToSaveIn, tosave)

		print("Auto saved navmesh in backups folder. "..DirectoryToSaveIn)
		PrintMessage(3, "Automatically saved D3bot navmesh.")
	end
end

timer.Create("D3bot.AutoBackupSaveMesh", 180, 0, function()
	AutoSave()
end)

hook.Add("ShutDown", "D3bot.AutoBackupSaveMesh", function()
	AutoSave()
end)


return function(lib)
	lib.MapNavMeshDir = "d3bot/navmesh/map/"
	
	function lib.GetMapNavMeshPath(mapName)
		return lib.MapNavMeshDir .. mapName .. ".txt"
	end
	function lib.GetMapNavMeshPath_LZMA(mapName)
		return lib.MapNavMeshDir .. mapName .. ".lzma.txt"
	end
	function lib.GetMapNavMeshParamsPath(mapName)
		return lib.MapNavMeshDir .. mapName .. ".params.txt"
	end
	function lib.GetMapNavMeshParamsPath_LZMA(mapName)
		return lib.MapNavMeshDir .. mapName .. ".lzma.params.txt"
	end
	lib.MapNavMeshPath = lib.GetMapNavMeshPath(game.GetMap())
	lib.MapNavMeshPath_LZMA = lib.GetMapNavMeshPath(game.GetMap())
	lib.MapNavMeshParamsPath = lib.GetMapNavMeshParamsPath(game.GetMap())
	lib.MapNavMeshParamsPath_LZMA = lib.GetMapNavMeshParamsPath(game.GetMap())

	
	function lib.CheckMapNavMesh(mapName)
		return file.Exists(lib.GetMapNavMeshPath(mapName), "DATA")
	end
	
	util.AddNetworkString(lib.MapNavMeshNetworkStr)
	function lib.UploadMapNavMesh(plOrPls)
		local rawData = util.Compress(lib.MapNavMesh:Serialize()) or ""
		local dataLen = rawData:len()
		local maxChunkSize = 2^16 - 10 -- Leave 10 bytes for other stuff than the data.

		for i = 1, dataLen, maxChunkSize do
			local dataLeft = dataLen + 1 - i
			local chunkSize = math.min(maxChunkSize, dataLeft)
			local subDataComp = string.sub(rawData, i, i + chunkSize - 1)

			net.Start(lib.MapNavMeshNetworkStr, false)
			net.WriteBool(false)
			net.WriteUInt(chunkSize, 16)
			net.WriteData(subDataComp, chunkSize)
			net.Send(plOrPls)
		end

		-- Finish the transfer.
		net.Start(lib.MapNavMeshNetworkStr, false)
		net.WriteBool(true)
		net.WriteUInt(0, 16)
		net.Send(plOrPls)
	end
	
	file.CreateDir(lib.MapNavMeshDir)
	function lib.SaveMapNavMesh()
		file.Write(lib.MapNavMeshPath, lib.MapNavMesh:SerializeSorted())
		file.Write(lib.MapNavMeshParamsPath, lib.MapNavMesh:ParamsSerializeSorted())

		local Directory = "d3bot/navmesh/backups/"
		local DirectoryToSaveIn = Directory.."/"..game.GetMap()..".txt"

		if file.IsDir(Directory, "DATA") and file.Exists(DirectoryToSaveIn, "DATA") then
			print("Backup navmesh found, deleting the backup navmesh file.")
			PrintMessage(3, "Backup navmesh found, deleting the backup navmesh file.")
			file.Delete(DirectoryToSaveIn, "DATA")
		end
	end
	function lib.SaveMapNavMeshParams()
		file.Write(lib.MapNavMeshParamsPath, lib.MapNavMesh:ParamsSerializeSorted())
	end
	function lib.LoadMapNavMesh()
		local mapNavMesh
		lib.TryCatch(function()
			mapNavMesh = lib.DeserializeNavMesh(file.Read(lib.MapNavMeshPath, "DATA") or "")
		end, function(errorMsg)
			mapNavMesh = lib.NewNavMesh()
			lib.LogError("Couldn't load " .. lib.MapNavMeshDir .. " (using empty nav mesh instead):\n" .. errorMsg)
		end)
		lib.TryCatch(function()
			mapNavMesh:DeserializeNavMeshParams(file.Read(lib.MapNavMeshParamsPath, "DATA") or "")
		end, function(errorMsg)
			lib.LogError("Couldn't load params for " .. lib.MapNavMeshDir .. ":\n" .. errorMsg)
		end)
		lib.MapNavMesh = mapNavMesh
	end
	function lib.LoadBackupMapNavMesh()
		local Directory = "d3bot/navmesh/backups/"
		local LoadDirectory = Directory.."/"..game.GetMap()..".txt"
		local backupsave = file.Read(LoadDirectory, "DATA")
		
		local mapNavMesh
		lib.TryCatch(function()
			mapNavMesh = lib.DeserializeNavMesh(backupsave or "")
		end, function(errorMsg)
			mapNavMesh = lib.NewNavMesh()
			lib.LogError("Couldn't load " .. LoadDirectory .. " (using empty nav mesh instead):\n" .. errorMsg)
		end)
--[[
		local mapNavMesh
		lib.TryCatch(function()
			mapNavMesh = lib.DeserializeNavMesh(file.Read(lib.MapNavMeshPath, "DATA") or "")
		end, function(errorMsg)
			mapNavMesh = lib.NewNavMesh()
			lib.LogError("Couldn't load " .. lib.MapNavMeshDir .. " (using empty nav mesh instead):\n" .. errorMsg)
		end)
]]
		lib.TryCatch(function()
			mapNavMesh:DeserializeNavMeshParams(file.Read(lib.MapNavMeshParamsPath, "DATA") or "")
		end, function(errorMsg)
			lib.LogError("Couldn't load params for " .. lib.MapNavMeshDir .. ":\n" .. errorMsg)
		end)
		lib.MapNavMesh = mapNavMesh
	end
	lib.LoadMapNavMesh()
end
