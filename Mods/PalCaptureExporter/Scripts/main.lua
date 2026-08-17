-- PalCaptureExporter 0.2.0
-- Read-only Palworld capture-count and catalogue exporter for UE4SS.

local UEHelpers = require("UEHelpers")

local HOTKEY = Key.F8 -- Change this if F8 conflicts with another mod.
local OUTPUT_FILENAME = "pal_capture_data.json"
local EXPORTER_VERSION = "0.2.0"
local PREFIX = "[PalCaptureExporter] "

local MONSTER_TABLE_PATH = "/Game/Pal/DataTable/Character/DT_PalMonsterParameter"
local NAME_TABLE_PATHS = {
    "/Game/Pal/DataTable/Text/DT_PalNameText",
    "/Game/Pal/DataTable/Text/DT_PalNameText_Common"
}

local running = false

local function log(message)
    print(PREFIX .. tostring(message) .. "\n")
end

local function isValid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

local function asText(value)
    value = unwrap(value)
    if value == nil then return nil end
    if type(value) ~= "userdata" then return tostring(value) end
    local ok, result = pcall(function() return value:ToString() end)
    if ok then return tostring(result) end
    return tostring(value)
end

local function asNumber(value)
    value = unwrap(value)
    if type(value) == "number" then return value end
    return tonumber(asText(value))
end

local function asBoolean(value)
    value = unwrap(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    local text = string.lower(tostring(asText(value)))
    if text == "true" or text == "1" then return true end
    if text == "false" or text == "0" then return false end
    return nil
end

local function readField(row, fieldName)
    local ok, value = pcall(function() return row[fieldName] end)
    if not ok then return nil, false end
    return unwrap(value), true
end

local function asCaptureCount(value, id)
    local number = asNumber(value)
    if number == nil or number < 0 or number ~= math.floor(number) then
        error(string.format("Invalid capture count for %s: %s", tostring(id), tostring(asText(value))))
    end
    return number
end

local function jsonString(value)
    value = tostring(value)
    local escaped = {}
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte == 34 then table.insert(escaped, '\\"')
        elseif byte == 92 then table.insert(escaped, "\\\\")
        elseif byte == 8 then table.insert(escaped, "\\b")
        elseif byte == 9 then table.insert(escaped, "\\t")
        elseif byte == 10 then table.insert(escaped, "\\n")
        elseif byte == 12 then table.insert(escaped, "\\f")
        elseif byte == 13 then table.insert(escaped, "\\r")
        elseif byte < 32 then table.insert(escaped, string.format("\\u%04x", byte))
        else table.insert(escaped, string.char(byte)) end
    end
    return '"' .. table.concat(escaped) .. '"'
end

local function outputPath()
    local source = debug.getinfo(1, "S").source
    if type(source) == "string" and source:sub(1, 1) == "@" then
        local scriptDirectory = source:sub(2):match("^(.*[\\/])")
        if scriptDirectory then
            local modDirectory = scriptDirectory:gsub("[\\/]Scripts[\\/]?$", "")
            local separator = source:find("\\", 1, true) and "\\" or "/"
            return modDirectory .. separator .. OUTPUT_FILENAME
        end
    end
    return OUTPUT_FILENAME
end

local function loadDataTable(assetPath)
    LoadAsset(assetPath)
    local objectName = assetPath:match("([^/]+)$")
    local dataTable = StaticFindObject(assetPath .. "." .. objectName)
    if isValid(dataTable) then return dataTable end
    return nil
end

local function collectCaptureCounts()
    local controller = UEHelpers.GetPlayerController()
    if not isValid(controller) then error("No local player controller. Load fully into a world and try again.") end

    local playerState = controller:GetPalPlayerState()
    if not isValid(playerState) then error("GetPalPlayerState() did not return a valid player state.") end

    local recordData = playerState:GetRecordData()
    if not isValid(recordData) then error("GetRecordData() did not return valid player record data.") end

    local captureMap = recordData["PalCaptureCount"]
    if captureMap == nil then error("PalCaptureCount was unavailable on the player record data.") end
    local items = captureMap["Items"]
    if items == nil then error("PalCaptureCount.Items was unavailable on this UE4SS build.") end

    local counts, entries = {}, {}
    for index = 1, #items do
        local entry = items[index]
        if entry == nil then error("PalCaptureCount.Items contained an empty entry at index " .. index .. ".") end
        local id = asText(entry["Key"])
        if id == nil or id == "" then error("Capture-count entry " .. index .. " had no readable Pal ID.") end
        if counts[id] ~= nil then error("Duplicate Pal ID in capture-count data: " .. id) end
        local count = asCaptureCount(entry["Value"], id)
        counts[id] = count
        table.insert(entries, {id=id, captureCount=count})
    end
    return counts, entries
end

local function collectEnglishNames()
    local nameTable, resolvedPath
    for _, path in ipairs(NAME_TABLE_PATHS) do
        nameTable = loadDataTable(path)
        if nameTable then resolvedPath = path break end
    end
    if not nameTable then error("Could not resolve the English Pal name DataTable.") end

    local names = {}
    local rowNames = nameTable:GetRowNames()
    for _, rawRowName in ipairs(rowNames) do
        local rowName = asText(rawRowName)
        local row = nameTable:FindRow(rowName)
        if row ~= nil then
            local textData, ok = readField(row, "TextData")
            local displayName = ok and asText(textData) or nil
            if displayName and displayName ~= "" then names[string.lower(rowName)] = displayName end
        end
    end
    return names, resolvedPath
end

local function candidateIsCanonical(candidate)
    return string.lower(candidate.nameKey) == string.lower("PAL_NAME_" .. candidate.id)
end

local function chooseCandidate(group, captureCounts)
    local best, bestScore
    for _, candidate in ipairs(group) do
        local score = 0
        if captureCounts[candidate.id] ~= nil then score = score + 100000 end
        if candidateIsCanonical(candidate) then score = score + 10000 end
        if not candidate.id:find("Quest_", 1, true)
                and not candidate.id:find("SUMMON_", 1, true)
                and not candidate.id:find("_Oilrig", 1, true) then
            score = score + 1000
        end
        score = score - #candidate.id
        if best == nil or score > bestScore or (score == bestScore and candidate.id < best.id) then
            best, bestScore = candidate, score
        end
    end
    return best
end

local function collectCatalogue(captureCounts, names)
    local monsterTable = loadDataTable(MONSTER_TABLE_PATH)
    if not monsterTable then error("Could not resolve the Pal monster parameter DataTable.") end

    local groups = {}
    for _, rawRowName in ipairs(monsterTable:GetRowNames()) do
        local id = asText(rawRowName)
        local row = monsterTable:FindRow(id)
        if row ~= nil then
            local isPalValue, isPalOk = readField(row, "IsPal")
            local zukanValue, zukanOk = readField(row, "ZukanIndex")
            local suffixValue, suffixOk = readField(row, "ZukanIndexSuffix")
            local isBossValue, isBossOk = readField(row, "IsBoss")
            local isTowerValue, isTowerOk = readField(row, "IsTowerBoss")
            local isRaidValue, isRaidOk = readField(row, "IsRaidBoss")
            local overrideValue, overrideOk = readField(row, "OverrideNameTextID")

            if isPalOk and zukanOk and suffixOk and isBossOk and isTowerOk and isRaidOk and overrideOk then
                local zukanIndex = asNumber(zukanValue)
                if asBoolean(isPalValue) == true and zukanIndex and zukanIndex > 0
                        and asBoolean(isBossValue) ~= true
                        and asBoolean(isTowerValue) ~= true
                        and asBoolean(isRaidValue) ~= true then
                    local nameKey = "PAL_NAME_" .. id
                    local overrideNameKey = asText(overrideValue)
                    if overrideNameKey and overrideNameKey ~= "" and overrideNameKey ~= "None" then
                        nameKey = overrideNameKey
                    end
                    local groupKey = string.lower(nameKey)
                    if groups[groupKey] == nil then groups[groupKey] = {} end
                    table.insert(groups[groupKey], {
                        id=id,
                        nameKey=nameKey,
                        paldeckIndex=zukanIndex,
                        paldeckSuffix=asText(suffixValue) or ""
                    })
                end
            end
        end
    end

    local pals, mappedCaptureIds = {}, {}
    for groupKey, group in pairs(groups) do
        local chosen = chooseCandidate(group, captureCounts)
        for _, candidate in ipairs(group) do
            if captureCounts[candidate.id] ~= nil then mappedCaptureIds[candidate.id] = true end
        end
        table.insert(pals, {
            id=chosen.id,
            name=names[groupKey],
            nameKey=chosen.nameKey,
            paldeckIndex=chosen.paldeckIndex,
            paldeckSuffix=chosen.paldeckSuffix,
            captureCount=captureCounts[chosen.id] or 0
        })
    end

    table.sort(pals, function(left, right)
        if left.paldeckIndex ~= right.paldeckIndex then return left.paldeckIndex < right.paldeckIndex end
        if left.paldeckSuffix ~= right.paldeckSuffix then return left.paldeckSuffix < right.paldeckSuffix end
        return left.id < right.id
    end)
    return pals, mappedCaptureIds
end

local function collectUnmapped(entries, mappedCaptureIds)
    local unmapped = {}
    for _, entry in ipairs(entries) do
        if not mappedCaptureIds[entry.id] then table.insert(unmapped, entry) end
    end
    table.sort(unmapped, function(left, right) return left.id < right.id end)
    return unmapped
end

local function appendCaptureRow(lines, pal, indent, trailingComma)
    table.insert(lines, indent .. "{")
    table.insert(lines, indent .. "  \"id\": " .. jsonString(pal.id) .. ",")
    if pal.nameKey then
        table.insert(lines, indent .. "  \"name\": " .. (pal.name and jsonString(pal.name) or "null") .. ",")
        table.insert(lines, indent .. "  \"nameKey\": " .. jsonString(pal.nameKey) .. ",")
        table.insert(lines, indent .. "  \"paldeckIndex\": " .. tostring(pal.paldeckIndex) .. ",")
        table.insert(lines, indent .. "  \"paldeckSuffix\": " .. jsonString(pal.paldeckSuffix) .. ",")
    end
    table.insert(lines, indent .. "  \"captureCount\": " .. tostring(pal.captureCount))
    table.insert(lines, indent .. "}" .. (trailingComma and "," or ""))
end

local function buildJson(pals, unmapped, nameTablePath)
    local captured, uncaught, totalCaptures = 0, 0, 0
    for _, pal in ipairs(pals) do
        totalCaptures = totalCaptures + pal.captureCount
        if pal.captureCount > 0 then captured = captured + 1 else uncaught = uncaught + 1 end
    end

    local lines = {
        "{",
        "  \"schemaVersion\": 1,",
        "  \"exporterVersion\": " .. jsonString(EXPORTER_VERSION) .. ",",
        "  \"gameVersion\": null,",
        "  \"exportedAt\": " .. jsonString(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. ",",
        "  \"source\": {",
        "    \"platform\": \"WinGDK\",",
        "    \"access\": \"UE4SS runtime\",",
        "    \"field\": \"PalPlayerRecordData.PalCaptureCount.Items\",",
        "    \"monsterTable\": " .. jsonString(MONSTER_TABLE_PATH) .. ",",
        "    \"nameTable\": " .. jsonString(nameTablePath),
        "  },",
        "  \"summary\": {",
        "    \"entryCount\": " .. tostring(#pals) .. ",",
        "    \"positiveCountEntries\": " .. tostring(captured) .. ",",
        "    \"zeroCountEntries\": " .. tostring(uncaught) .. ",",
        "    \"totalCaptures\": " .. tostring(totalCaptures) .. ",",
        "    \"unmappedCaptureEntryCount\": " .. tostring(#unmapped),
        "  },",
        "  \"pals\": ["
    }
    for index, pal in ipairs(pals) do appendCaptureRow(lines, pal, "    ", index < #pals) end
    table.insert(lines, "  ],")
    table.insert(lines, "  \"unmappedCaptureEntries\": [")
    for index, entry in ipairs(unmapped) do appendCaptureRow(lines, entry, "    ", index < #unmapped) end
    table.insert(lines, "  ]")
    table.insert(lines, "}")
    return table.concat(lines, "\n") .. "\n"
end

local function writeExport(json)
    local path = outputPath()
    local file, openError = io.open(path, "w")
    if not file then error("Could not open export file: " .. tostring(openError)) end
    local writeOk, writeError = file:write(json)
    file:close()
    if not writeOk then error("Could not write export file: " .. tostring(writeError)) end
    return path
end

local function exportCaptureData()
    local captureCounts, captureEntries = collectCaptureCounts()
    local names, nameTablePath = collectEnglishNames()
    local pals, mappedCaptureIds = collectCatalogue(captureCounts, names)
    local unmapped = collectUnmapped(captureEntries, mappedCaptureIds)
    local json = buildJson(pals, unmapped, nameTablePath)
    local path = writeExport(json)

    local uncaught, missingNames = 0, 0
    for _, pal in ipairs(pals) do
        if pal.captureCount == 0 then uncaught = uncaught + 1 end
        if pal.name == nil then missingNames = missingNames + 1 end
    end
    log(string.format("Exported %d Paldeck species (%d uncaught) to: %s", #pals, uncaught, path))
    if missingNames > 0 then log(string.format("Warning: %d catalogue names were unresolved.", missingNames)) end
    if #unmapped > 0 then log(string.format("Preserved %d non-catalogue capture entries separately.", #unmapped)) end
end

log("Loaded. Enter a world, then press F8 to export the complete capture catalogue.")

RegisterKeyBind(HOTKEY, function()
    if running then return end
    running = true
    ExecuteInGameThread(function()
        local ok, exportError = xpcall(exportCaptureData, debug.traceback)
        if not ok then log("EXPORT FAILED: " .. tostring(exportError)) end
        running = false
    end)
end)
