
return function(lib)
	function lib.LoadConfig(fileName, gamePath)
        gamePath = gamePath or "DATA"

        local content = file.Read(fileName, gamePath)
        if not content then return false end

        local config = util.JSONToTable(content)
        if not config then return false end

        

        return true,config
    end
end
