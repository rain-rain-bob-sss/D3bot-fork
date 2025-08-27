
return function(globalK, otherLibFilesRelPathEach)
	local lib = {}
	
	local consoleErrorColor = Color(255, 75, 0)
	function lib.LogError(msg) MsgC(consoleErrorColor, "Error: " .. msg .. "\n") end
	
	function lib.TryInvoke(func, ...) if isfunction(func) then func(...) end end
	function lib.TryCatch(func, error)
		local didNotError, errorMsg = xpcall(func, debug.traceback)
		if not didNotError then error(errorMsg) end
	end

	--- Calls a function twice, swapping arguments
	---@param a any First argument
	---@param b any Second argument
	---@param func fun(x:any,y:any) The function to invoke
	function lib.TwoWay(a, b, func)
		func(a, b)
		func(b, a)
	end
	
	--- Write a value to a table at key, or append if key is nil
	---@param tbl table The target table
	---@param k any|nil The key (if nil, append value)
	---@param v any The value to insert
	function lib.WriteOrAdd(tbl, k, v) if k == nil then table.insert(tbl, v) else tbl[k] = v end end
	
	lib.SortedQueueMeta = { __index = {} }
	local sortedQueueFallback = lib.SortedQueueMeta.__index

	--- Create a new sorted queue with a comparator function
	---@param func fun(a:any,b:any):boolean Comparison function (returns true if a < b)
	---@return table SortedQueue
	function lib.NewSortedQueue(func)
		return setmetatable({
			Set = {},
			Func = func }, lib.SortedQueueMeta)
	end

	--- Enqueue an item into a sorted queue
	---@param item any The item to insert
	function sortedQueueFallback:Enqueue(item)
		if self.Set[item] then return end
		self.Set[item] = true
		for idx, v in ipairs(self) do if self.Func(item, v) then return table.insert(self, idx, item) end end
		return table.insert(self, item)
	end

	--- Dequeue the last item from the sorted queue
	---@return any|nil item The removed item or nil if empty
	function sortedQueueFallback:Dequeue()
		local item = table.remove(self)
		if item then self.Set[item] = nil end
		return item
	end
	
	--- Splits a string into an array by separator
	---@param str string Input string
	---@param separator string The separator
	---@return string[] parts Array of split substrings
	function lib.GetSplitStr(str, separator) return str == "" and {} or str:Split(separator) end

	--- Wraps a string with another string
	---@param str string The text to wrap
	---@param wrap string The wrapper string
	---@return string wrapped The wrapped string
	function lib.GetWrappedStr(str, wrap) return wrap .. str .. wrap end

	--- Returns a quoted version of the string
	---@param str string Input string
	---@return string quoted The quoted string
	function lib.GetQuotedStr(str) return lib.GetWrappedStr(str, "\"") end
	
	--- Wrapper for sending net messages (handles server/client)
	---@param ... any Net message args
	function lib.Send(...) (SERVER and net.Send or net.SendToServer)(...) end
	
	--- Returns iterator for pairs sorted by key
	---@generic K,V
	---@param t table<K,V> Input table
	---@param f fun(a:any,b:any):boolean? Optional sort function
	---@return fun():K,V iterator Iterator function
	function lib.PairsByKeys(t, f)
      local a = {}
      for n in pairs(t) do table.insert(a, n) end
      table.sort(a, f)
      local i = 0				-- iterator variable
      local iter = function ()	-- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
      end
      return iter
    end
	
	lib.QueryMeta = { __index = {} }
	local queryFallback = lib.QueryMeta.__index
	--- Wrap a value in a query
	---@param v any The value
	---@return table Query
	function lib.From(v) return setmetatable({ R = v }, lib.QueryMeta) end
	local from = lib.From
	--- Checks if any value matches condition
	---@param func fun(k:any,v:any):boolean Condition function
	---@return table Query self
	function queryFallback:Any(func)
		for k, v in pairs(self.R) do
			if func(k, v) then
				self.R = true
				return self
			end
		end
		self.R = false
		return self
	end
	--- Shallow copy table
	---@return table Query self
	function queryFallback:ShallowCopy()
		local r = {}
		for k, v in pairs(self.R) do r[k] = v end
		self.R = r
		return self
	end
	--- Count table length
	---@return table Query self
	function queryFallback:Len()
		local len = 0
		for k, v in ipairs(self.R) do len = len + 1 end
		self.R = len
		return self
	end
	--- Collect keys of table
	---@return table Query self
	function queryFallback:Ks()
		local r = {}
		for k, v in pairs(self.R) do table.insert(r, k) end
		self.R = r
		return self
	end
	--- Select values using function
	---@param func fun(k:any,v:any):any Mapper
	---@return table Query self
	function queryFallback:Sel(func)
		local r = {}
		for k, v in pairs(self.R) do lib.WriteOrAdd(r, func(k, v)) end
		self.R = r
		return self
	end
	--- Select values with sort
	---@param func fun(k:any,v:any):any Mapper
	---@param sortFunc fun(a:any,b:any):boolean Sort comparator
	---@return table Query self
	function queryFallback:SelSort(func, sortFunc)
		local r = {}
		for k, v in lib.PairsByKeys(self.R, sortFunc) do lib.WriteOrAdd(r, func(k, v)) end
		self.R = r
		return self
	end
	--- Select values (value transform only)
	---@param func fun(v:any):any Mapper
	---@return table Query self
	function queryFallback:SelV(func)
		local r = {}
		for k, v in pairs(self.R) do r[k] = func(v) end
		self.R = r
		return self
	end
	--- Filter values
	---@param func fun(k:any,v:any):boolean Predicate
	---@return table Query self
	function queryFallback:Where(func)
		local r = {}
		for k, v in pairs(self.R) do if func(k, v) then r[k] = v end end
		self.R = r
		return self
	end
	function queryFallback:W(arr)
		for k, v in ipairs(arr) do table.insert(self.R, v) end
		return self
	end
	function queryFallback:Wo(v)
		self:ShallowCopy()
		table.RemoveByValue(self.R, v)
		return self
	end
	--- Sort array
	---@param funcOrNil fun(a:any,b:any):boolean|nil Comparator
	---@return table Query self
	function queryFallback:Sort(funcOrNil)
		self:ShallowCopy()
		table.sort(self.R, funcOrNil or function(a, b) return a < b end)
		return self
	end
	--- Convert array values to set
	---@return table Query self
	function queryFallback:Reverse(func)
		local r = {}
		for k, v in ipairs(self.R) do table.insert(r, 1, v) end
		self.R = r
		return self
	end
	function queryFallback:VsSet()
		local r = {}
		for k, v in ipairs(self.R) do r[v] = true end
		self.R = r
		return self
	end
	--- Flatten array of arrays
	---@return table Query self
	function queryFallback:Concat()
		local r = {}
		for idx, arr in ipairs(self.R) do for idx2, v in ipairs(arr) do table.insert(r, v) end end
		self.R = r
		return self
	end
	--- Join array into string
	---@param separator string Separator
	---@return table Query self
	function queryFallback:Join(separator)
		self.R = string.Implode(separator, self.R)
		return self
	end
	
	function lib.GetFileInfo(path)
		local pathWoExt = path:StripExtension()
		local includePath = lib.GetIncludePath(path)
		local isSvside = pathWoExt:EndsWith("_sv")
		local isClside = pathWoExt:EndsWith("_cl")
		if not isSvside and not isClside then
			isSvside = true
			isClside = true
		end
		return {
			Name = path:GetFileFromFilename(),
			NameWoExt = pathWoExt:GetFileFromFilename(),
			Dir = path:GetPathFromFilename(),
			Path = path,
			PathWoExt = pathWoExt,
			IncludeDir = includePath:GetPathFromFilename(),
			IncludePath = includePath,
			IsSvside = isSvside,
			IsClside = isClside }
	end
	function lib.GetIncludePath(luaFilePath)
		local luaFolder = "lua/"
		local luaDirIdx = luaFilePath:find(luaFolder, 1, true)
		if not luaDirIdx then return luaFilePath end
		return luaFilePath:sub(luaDirIdx + #luaFolder)
	end
	function lib.MakeLibFileAvailable(relInfo) if SERVER and relInfo.IsClside then AddCSLuaFile(relInfo.IncludePath) end end
	function lib.ExecuteLibFile(relInfo) if (SERVER and relInfo.IsSvside) or (CLIENT and relInfo.IsClside) then lib.TryInvoke(include(relInfo.IncludePath), lib) end end
	
	lib.Color = {}
	lib.Color.Black = Color(0, 0, 0)
	lib.Color.White = Color(255, 255, 255)
	lib.Color.Red = Color(255, 0, 0)
	lib.Color.Orange = Color(255, 128, 0)
	lib.Color.Yellow = Color(255, 255, 0)
	lib.Color.Green = Color(0, 150, 0)
	for name, color in pairs(lib.Color) do
		color.HalfAlpha = ColorAlpha(color, 128)
		color.EightAlpha = ColorAlpha(color, 32)
		color.SixteenthAlpha = ColorAlpha(color, 32)
	end
	
	function lib.GetEntsOfClss(clss,func) 
		func = func or ents.FindByClass
		return from(clss):SelV(func):Concat().R
	end
	
	if SERVER then
		local relFileInfo = lib.GetFileInfo(debug.getinfo(1, "S").short_src)
		
		lib.MakeLibFileAvailable(relFileInfo)
		
		local assumedLibFilesRelPathEach = from(file.Find(relFileInfo.Dir .. "*.lua", "GAME")):SelV(function(name) return relFileInfo.IncludeDir .. name end).R
		function lib.SuggestSecondLibArgument() return "{\n\t" .. from(assumedLibFilesRelPathEach):Wo(relFileInfo.IncludePath):Sort():SelV(lib.GetQuotedStr):Join(",\n\t").R .. " }" end
	end
	for idx, relPath in ipairs(otherLibFilesRelPathEach) do
		local relInfo = lib.GetFileInfo(relPath)
		lib.MakeLibFileAvailable(relInfo)
		lib.ExecuteLibFile(relInfo)
	end
	
	if _G[globalK] then error("The specified global variable has already been assigned to.", 2) end
	_G[globalK] = lib
	lib.GlobalK = globalK
	lib.IsInitialized = true
end
