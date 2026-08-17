-- PalCaptureExporter 0.1.0
-- Read-only Palworld capture-count exporter for UE4SS.

local UEHelpers = require("UEHelpers")

-- Change this if F8 conflicts with another mod.
local HOTKEY = Key.F8
local OUTPUT_FILENAME = "pal_capture_data.json"

local EXPORTER_VERSION = "0.1.0"
local PREFIX = "[PalCaptureExporter] "
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

local function asCaptureCount(value, id)
    value = unwrap(value)

    local number
    if type(value) == "number" then
        number = value
    else
        number = tonumber(asText(value))
    end

    if number == nil or number < 0 or number ~= math.floor(number) then
        error(string.format(
            "Invalid capture count for %s: %s",
            tostring(id),
            tostring(asText(value))
        ))
    end
    return number
end

local function jsonString(value)
    value = tostring(value)
    local escaped = {}

    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte == 34 then
            table.insert(escaped, '\\"')
        elseif byte == 92 then
            table.insert(escaped, "\\\\")
        elseif byte == 8 then
            table.insert(escaped, "\\b")
        elseif byte == 9 then
            table.insert(escaped, "\\t")
        elseif byte == 10 then
            table.insert(escaped, "\\n")
        elseif byte == 12 then
            table.insert(escaped, "\\f")
        elseif byte == 13 then
            table.insert(escaped, "\\r")
        elseif byte < 32 then
            table.insert(escaped, string.format("\\u%04x", byte))
        else
            table.insert(escaped, string.char(byte))
        end
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

local function collectCaptureCounts()
    local controller = UEHelpers.GetPlayerController()
    if not isValid(controller) then
        error("No local player controller. Load fully into a world and try again.")
    end

    local playerState = controller:GetPalPlayerState()
    if not isValid(playerState) then
        error("GetPalPlayerState() did not return a valid player state.")
    end

    local recordData = playerState:GetRecordData()
    if not isValid(recordData) then
        error("GetRecordData() did not return valid player record data.")
    end

    local captureMap = recordData["PalCaptureCount"]
    if captureMap == nil then
        error("PalCaptureCount was unavailable on the player record data.")
    end

    local items = captureMap["Items"]
    if items == nil then
        error("PalCaptureCount.Items was unavailable on this UE4SS build.")
    end

    local pals = {}
    local seen = {}
    local itemCount = #items

    for index = 1, itemCount do
        local entry = items[index]
        if entry == nil then
            error("PalCaptureCount.Items contained an empty entry at index " .. index .. ".")
        end

        local id = asText(entry["Key"])
        if id == nil or id == "" then
            error("Capture-count entry " .. index .. " had no readable Pal ID.")
        end
        if seen[id] then
            error("Duplicate Pal ID in capture-count data: " .. id)
        end

        local captureCount = asCaptureCount(entry["Value"], id)
        seen[id] = true
        table.insert(pals, {
            id = id,
            captureCount = captureCount
        })
    end

    table.sort(pals, function(left, right)
        return left.id < right.id
    end)

    return pals
end

local function buildJson(pals)
    local positiveCount = 0
    local zeroCount = 0
    for _, pal in ipairs(pals) do
        if pal.captureCount > 0 then
            positiveCount = positiveCount + 1
        else
            zeroCount = zeroCount + 1
        end
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
        "    \"field\": \"PalPlayerRecordData.PalCaptureCount.Items\"",
        "  },",
        "  \"summary\": {",
        "    \"entryCount\": " .. tostring(#pals) .. ",",
        "    \"positiveCountEntries\": " .. tostring(positiveCount) .. ",",
        "    \"zeroCountEntries\": " .. tostring(zeroCount),
        "  },",
        "  \"pals\": ["
    }

    for index, pal in ipairs(pals) do
        table.insert(lines, "    {")
        table.insert(lines, "      \"id\": " .. jsonString(pal.id) .. ",")
        table.insert(lines, "      \"captureCount\": " .. tostring(pal.captureCount))
        if index < #pals then
            table.insert(lines, "    },")
        else
            table.insert(lines, "    }")
        end
    end

    table.insert(lines, "  ]")
    table.insert(lines, "}")
    return table.concat(lines, "\n") .. "\n"
end

local function writeExport(json)
    local path = outputPath()
    local file, openError = io.open(path, "w")
    if not file then
        error("Could not open export file: " .. tostring(openError))
    end

    local writeOk, writeError = file:write(json)
    file:close()
    if not writeOk then
        error("Could not write export file: " .. tostring(writeError))
    end
    return path
end

local function exportCaptureData()
    local pals = collectCaptureCounts()
    local json = buildJson(pals)
    local path = writeExport(json)
    log(string.format("Exported %d capture-count entries to: %s", #pals, path))
end

log("Loaded. Enter a world, then press F8 to export capture counts.")

RegisterKeyBind(HOTKEY, function()
    if running then return end
    running = true

    ExecuteInGameThread(function()
        local ok, exportError = xpcall(exportCaptureData, debug.traceback)
        if not ok then
            log("EXPORT FAILED: " .. tostring(exportError))
        end
        running = false
    end)
end)
