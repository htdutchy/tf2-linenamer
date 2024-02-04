-- [GLOBALS]
-- Table to store the names and keep track of registered lines
local nameTable = {}
-- prefix to use
local prefix = "^"

-- [API Interface]
function isEntityExists(id)
	return api.engine.entityExists(id)
end

function getComponent(id, component)
	if isEntityExists(id) then
		local comp = api.engine.getComponent(id, component)
		if not comp then
			return nil, "Component not found"
		end
		return comp
	end
	return nil, "Entity does not exist"
end

function getName(id)
	local nameComponent, err = getComponent(id, api.type.ComponentType.NAME)
	if not nameComponent then
		return nil, err
	end
	
	if not nameComponent.name then
		return nil, "Name not found in component"
	end
	
	return nameComponent.name
end

function getLine(id)
	return getComponent(id, api.type.ComponentType.LINE)
end

function getStationGroup(id)
	return getComponent(id, api.type.ComponentType.STATION_GROUP)
end

function getStation(id)
	return getComponent(id, api.type.ComponentType.STATION)
end

function getTownIdByStation(id)
	if not isEntityExists(id) then
		return nil, "Entity does not exist"
	end
	
	local townId = api.engine.system.stationSystem.getTown(id)
	if not townId then
		return nil, "Town ID not found"
	end
	
	return townId
end

function getTown(id)
	return getComponent(id, api.type.ComponentType.TOWN)
end

function getPlayerLines()
	return api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
end


-- [DATA WRANGLING]
function isUpdatableName(name)
	local lowerName = string.lower(name)
	return name == "" or name:match("^%s*$") or lowerName == "r" or lowerName == "reload" or name:match("^Line %d+$")
end

function getTownIdByStationGroup(stationGroupId)
	local stationGroup = getStationGroup(stationGroupId)
	if stationGroup and stationGroup.stations[1] then
		return getTownIdByStation(stationGroup.stations[1])
	end
	return nil
end

function getInitials(list)
	local initials = {}
	for _, item in ipairs(list) do
		local itemInitials = ""
		for word in item:gmatch("%S+") do -- Iterate through each word in the item
			local firstChar = word:sub(1, 1)
			itemInitials = itemInitials .. firstChar
		end
		table.insert(initials, itemInitials)
	end
	return table.concat(initials, ", ")
end


function getLineData(lineId)
	local data = {
		id = "",
		name = "",
		groups = {},
		viaGroups = {},
		groupIds = {},
		towns = {},
		viaTowns = {},
		townIds = {},
		firstTown = "",
		lastTown = "",
		firstGroup = "",
		lastGroup = "",
		isLocal = false,
		isReturn = false,
	}
	local allTowns = {}
	local allGroups = {}
	local previousTownInsert = ""
	
	data.id = lineId
	data.name = getName(lineId)
	local lineComponent, err = getLine(lineId)
	if not lineComponent then
		return nil, err
	end
	
	for _, stop in ipairs(lineComponent.stops) do
		local stationGroupId = stop.stationGroup
		local townId = getTownIdByStationGroup(stationGroupId)
		if allTowns[townId] ~= nil and previousTownInsert ~= townId then
			data.isReturn = true
		end
		if allTowns[townId] == nil then
			table.insert(data.towns, getName(townId))
			table.insert(data.townIds, townId)
		end
		if allGroups[stationGroupId] == nil then
			table.insert(data.groups, getName(stationGroupId))
			table.insert(data.groupIds, stationGroupId)
		end
		
		allGroups[stationGroupId] = getName(stationGroupId)
		allTowns[townId] = getName(townId)
		previousTownInsert = townId
	end
	
	if data.towns[1] then
		data.firstTown = data.towns[1]
	end
	if data.towns[#data.towns] then
		data.lastTown = data.towns[#data.towns]
	end
	if #data.towns == 1 then
		data.isLocal = true
	end
	if #data.towns > 2 then
		for i = 2, #data.towns - 1 do
			table.insert(data.viaTowns, data.towns[i])
		end
	end
		
	if data.groups[1] then
		data.firstGroup = data.groups[1]
	end
	if data.groups[#data.groups] then
		data.lastGroup = data.groups[#data.groups]
	end
	if #data.groups > 2 then
		for i = 2, #data.groups - 1 do
			table.insert(data.viaGroups, data.groups[i])
		end
	end
	
	return data
end

function generateBaseName(lineData)
	if not lineData then
		return nil, "Line data is nil"
	end
	
	local basename = prefix .. lineData.firstTown
	
	if lineData.isLocal then
		basename = basename .. " - local"
		if #lineData.groups > 0 then
			basename = basename .. " via " .. getInitials(lineData.groups)
		end
	else
		basename = basename .. " - " .. lineData.lastTown
		if #lineData.viaTowns > 0 then
			basename = basename .. " via " .. getInitials(lineData.viaTowns)
		end
	end
	
	return basename
end

function renameLines()
	-- Retrieve all the line IDs
	local lineIds = getPlayerLines()

	-- Loop through each line ID
	for lineKey, lineId in ipairs(lineIds) do
		local lineData, err = getLineData(lineId)

		if not lineData then
			debugPrint("HTD Script; Error getting line data: " .. (err or "Unknown error"))
			return
		end
		
		-- Check if the name is default or starts with prefix
		if lineData.name and (isUpdatableName(lineData.name) or lineData.name:sub(1, 1) == prefix) then
			local baseName, err = generateBaseName(lineData)
			
			if not baseName then
				debugPrint("HTD Script; Error generating base name: " .. (err or "Unknown error"))
				return
			end
			
			-- Determine if the lineId is already associated with a different baseName
			local previousBaseName = nil
			for name, ids in pairs(nameTable) do
				for index, id in ipairs(ids) do
					if id == lineId then
						previousBaseName = name
						break
					end
				end
			end

			-- If the lineId is found under a different baseName, remove it
			if previousBaseName and previousBaseName ~= baseName then
				for index, id in ipairs(nameTable[previousBaseName]) do
					if id == lineId then
						table.remove(nameTable[previousBaseName], index)
						break
					end
				end
			end

			-- Check if baseName exists in the tracking table and append lineId
			if not nameTable[baseName] then
				nameTable[baseName] = {}
			end

			-- Check if the lineId is already in the tracking table
			local isLineIdPresent = false
			for _, id in ipairs(nameTable[baseName]) do
				if id == lineId then
					isLineIdPresent = true
					break
				end
			end

			-- Append the lineId to the baseName tracking if not present
			if not isLineIdPresent then
				table.insert(nameTable[baseName], lineId)
			end

			-- Determine position number (unused)
			local positionNumber
			for idx, id in ipairs(nameTable[baseName]) do
				if id == lineId then
					positionNumber = idx
					break
				end
			end

			-- Construct the final name with position number
			local newName = baseName .. " #" .. lineKey

			-- Only rename and print if the new name is different from the current name
			if newName ~= lineData.name then
				-- Rename the line using the new name
				api.cmd.sendCommand(api.cmd.make.setName(lineId, newName))
				
				-- Cleanup: Remove empty entries in nameTable
				for name, ids in pairs(nameTable) do
					if #ids == 0 then
						nameTable[name] = nil
					end
				end

				-- Print the new name of the line using debugPrint
				debugPrint("HTD script; Line renamed: " .. newName)
				debugPrint("HTD script; Listing name table")
				debugPrint(nameTable)
			end
		end
	end
end



function data()
	return {
		update = renameLines
	}
end
