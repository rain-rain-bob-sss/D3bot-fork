function D3bot.GetTrajectories2DParams(g, initVel, distZ, distRad)
	local trajectories = {}
	local radix = initVel^4 - g*(g*distRad^2 + 2*distZ*initVel^2)
	
	if radix < 0 then return trajectories end
	local pitch = math.atan((initVel^2 - math.sqrt(radix)) / (g*distRad))
	local t1 = distRad / (initVel * math.cos(pitch))
	table.insert(trajectories, {g = g, initVel = initVel, pitch = pitch, t1 = t1})
	if radix > 0 then
		local pitch = math.atan((initVel^2 + math.sqrt(radix)) / (g*distRad))
		local t1 = distRad / (initVel * math.cos(pitch))
		table.insert(trajectories, {g = g, initVel = initVel, pitch = pitch, t1 = t1})
	end
	
	return trajectories
end

---This will calculate player jump heights based on the "Source SDK 2013" gamemovement.cpp logic.
---While this could be done analytically, any such solution results in smaller final jump heights due to truncation errors of the numerical integration that the engine does.
---Therefore we will replicate what the engine is doing.
---
---You may have to add the height difference between the `HullDuck` and `Hull` hull to the final result.
---@param jumpPower number The initial jump velocity.
---@param gravAcceleration number The gravitational acceleration.
---@param isCrouching boolean When true, we will jump while crouching. This minimally changes the math, and makes the player jump higher.
---@return number height The resulting jump height in source units.
function D3bot.CalculateJumpHeight(jumpPower, gravAcceleration, isCrouching)
	-- Some information:
	-- - The initial vertical velocity is not 0 when the player is standing, but `-g/tickrate/2`. (https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/gamemovement.cpp#L1259)
	-- - Crouching and instantly jumping is better than jumping and crouching. This is because if the player jumps while crouching, the entity's speed is overwritten instead of added to, resulting in an initial velocity advantage of `g/tickrate/2`. (https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/gamemovement.cpp#L2452-L2465)
	-- - After we have started to jump, we will subtract `-g/tickrate/2` again. (https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/gamemovement.cpp#L2122)

	local tickRate = 1 / engine.TickInterval() -- Ticks/s
	local integratedAcceleration = math.abs(gravAcceleration/tickRate)

	local vel, height = -integratedAcceleration/2, 0
	if isCrouching then
		vel = jumpPower
	else
		vel = vel + jumpPower
	end
	vel = vel - integratedAcceleration/2

	-- Checks to ensure termination.
	if vel > 10000 then return 0 end
	if integratedAcceleration <= 0 then return 0 end

	while vel > 0 do
		height = height + vel / tickRate
		vel = vel - integratedAcceleration
	end

	return height
end

function D3bot.GetTrajectory2DPoints(trajectory, segments)
	trajectory.points = {}
	for i = 0, segments, 1 do
		local t = Lerp(i/segments, 0, trajectory.t1)
		local r = Vector(math.cos(trajectory.pitch)*trajectory.initVel*t, 0, math.sin(trajectory.pitch)*trajectory.initVel*t - trajectory.g/2*t^2)
		table.insert(trajectory.points, r)
	end
	
	return trajectory
end

function D3bot.GetTrajectories(initVel, r0, r1, segments)
	local g = 600 -- Hard coded acceleration, should be read from gmod later
	
	local distZ = r1.z - r0.z
	local distRad = math.sqrt((r1.x - r0.x)^2 + (r1.y - r0.y)^2)
	local yaw = math.atan2(r1.y - r0.y, r1.x - r0.x)
	
	local trajectories = D3bot.GetTrajectories2DParams(g, initVel, distZ, distRad)
	for i, trajectory in ipairs(trajectories) do
		trajectories[i].yaw = yaw
		-- Calculate 2D trajectory from parameters
		trajectories[i] = D3bot.GetTrajectory2DPoints(trajectory, segments)
		-- Rotate and move trajectory into 3D space
		for k, _ in ipairs(trajectory.points) do
			trajectory.points[k]:Rotate(Angle(0, math.deg(yaw), 0))
			trajectory.points[k]:Add(r0)
		end
	end
	
	return trajectories
end

-- Remove spectating, meshing and dead players
function D3bot.RemoveObsDeadTgts(tgts)
	return D3bot.From(tgts):Where(function(k, v) return IsValid(v) and v:GetObserverMode() == OBS_MODE_NONE and not v:IsFlagSet(FL_NOTARGET) and v:Alive() end).R
end

---Calculates a falloff on the given nodes.
---@param startNode D3NavmeshNode|nil -- The node to start on.
---@param iterations integer -- The maximum number of iterations.
---@param startValue number -- The starting value.
---@param falloff number -- The falloff factor for every followed link.
---@param nodes table<D3NavmeshNode, number> -- The starting node-number pairs.
---@return table<D3NavmeshNode, number> -- Result is a map of nodes with number values.
function D3bot.NeighbourNodeFalloff(startNode, iterations, startValue, falloff, nodes)
	if not startNode then return {} end
	local nodes = nodes or {}
	local queue = {startNode}
	nodes[startNode] = (nodes[startNode] or 0) + startValue
	while #queue > 0 and iterations > 0 do
		local node = table.remove(queue)
		iterations = iterations - 1
		for linkedNode, link in pairs(node.LinkByLinkedNode) do
			nodes[linkedNode] = nodes[node] * falloff
			table.insert(queue, linkedNode)
		end
	end
	return nodes
end

---Return all players that are controller by D3bot, this includes real players that D3bot is in control of.
---@return GPlayer[]
function D3bot.GetBots()
	local bots = {}
	for _, v in pairs(player.GetAll()) do
		if v.D3bot_Mem then
			table.insert(bots, v)
		end
	end
	return bots
end
