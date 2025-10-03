local AbstractConfig = {}
AbstractConfig.__index = AbstractConfig
local FS = _G.fs -- Get the ComputerCraft filesystem API

local function loadConfig(filepath)
    if not FS.exists(filepath) then
        error("Config file not found: " .. filepath)
    end
    return dofile(filepath)
end

function AbstractConfig.new(name, template_path, filepath)
    local self = setmetatable({}, AbstractConfig)

    -- Initialize metadata
    self.metadata = {
        name = name,
        loaded_time = os.epoch("local"),
        targets = {}, -- Now stores UUID strings instead of module names
        validity = false,
        template = template_path,
        filepath = filepath
    }

    -- Load template
    local template = loadConfig(template_path)
    self.template_spec = template

    -- Load content
    self.content = loadConfig(filepath)

    -- Initialize logging
    self.log_entries = {}
    self.log_count = 0
    self.current_chunk = 0

    -- Ensure cache directory exists
    if not FS.exists(".cache") then
        FS.makeDir(".cache")
    end
    if not FS.exists(".cache/config") then
        FS.makeDir(".cache/config")
    end

    -- Validate content against template
    self:validate()

    return self
end

function AbstractConfig:validate()
    local valid = true

    for key, expected_type in pairs(self.template_spec) do
        if self.content[key] == nil then
            print("Warning: Missing key '" .. key .. "' in config")
            valid = false
        elseif type(self.content[key]) ~= expected_type then
            print("Warning: Key '" .. key .. "' has type '" .. type(self.content[key]) ..
                "' but expected '" .. expected_type .. "'")
            valid = false
        end
    end

    self.metadata.validity = valid
    return valid
end

function AbstractConfig:register_target(uuid)
    for _, existing in ipairs(self.metadata.targets) do
        if existing == uuid then
            return false -- Already registered
        end
    end
    table.insert(self.metadata.targets, uuid)
    return true
end

function AbstractConfig:deregister_target(uuid)
    for i, existing in ipairs(self.metadata.targets) do
        if existing == uuid then
            table.remove(self.metadata.targets, i)
            return true
        end
    end
    return false -- Not found
end

function AbstractConfig:log_operation(operation, target_uuid, key, value)
    local entry = {
        timestamp = os.epoch("local"),
        operation = operation,
        target = target_uuid,
        key = key,
        value = value
    }

    table.insert(self.log_entries, entry)
    self.log_count = self.log_count + 1

    -- Check if we need to flush to disk
    if #self.log_entries >= 100 then
        self:flush_log()
    end
end

function AbstractConfig:flush_log()
    if #self.log_entries == 0 then
        return
    end

    local chunk_file = string.format(".cache/config/%s_chunk_%02d", self.metadata.name, self.current_chunk)
    local file = FS.open(chunk_file, "w")

    file.write("return {\n")
    for i, entry in ipairs(self.log_entries) do
        file.write("    {\n")
        file.write("        timestamp = " .. entry.timestamp .. ",\n")
        file.write("        operation = \"" .. entry.operation .. "\",\n")
        file.write("        target = \"" .. entry.target .. "\",\n")
        file.write("        key = \"" .. entry.key .. "\",\n")
        file.write("        value = ")

        if type(entry.value) == "string" then
            file.write('"' .. entry.value .. '"')
        elseif type(entry.value) == "table" then
            file.write(textutils.serialize(entry.value))
        elseif entry.value == nil then
            file.write("nil")
        else
            file.write(tostring(entry.value))
        end

        file.write("\n    },\n")
    end
    file.write("}\n")

    file.close()

    -- Clear in-memory log and increment chunk counter
    self.log_entries = {}
    self.current_chunk = self.current_chunk + 1
end

function AbstractConfig:read(target_uuid, key)
    if not self.metadata.validity then
        error("Cannot read from invalid config")
    end

    local value = self.content[key]
    self:log_operation("read", target_uuid, key, value)

    return value
end

function AbstractConfig:unsafe_read(target_uuid, key)
    local value = self.content[key]
    self:log_operation("unsafe_read", target_uuid, key, value)

    return value
end

function AbstractConfig:write(target_uuid, key, val)
    if not self.metadata.validity then
        error("Cannot write to invalid config")
    end
    self:unsafe_write(target_uuid, key, val)
end

function AbstractConfig:unsafe_write(target_uuid, key, val)
    self.content[key] = val
    self:log_operation("write", target_uuid, key, val)
    self:save_to_file()
end

function AbstractConfig:write_many(target_uuid, keys, vals)
    if not self.metadata.validity then
        error("Cannot write to invalid config")
    end
    self:unsafe_write_many(target_uuid, keys, vals)
end

function AbstractConfig:unsafe_write_many(target_uuid, keys, vals)
    if #keys ~= #vals then
        error("Keys and values must have the same length")
    end

    for i = 1, #keys do
        self.content[keys[i]] = vals[i]
        self:log_operation("write_many", target_uuid, keys[i], vals[i])
    end

    self:save_to_file()
end

function AbstractConfig:save_to_file()
    local file = FS.open(self.metadata.filepath, "w")

    file.write("return {\n")
    for key, value in pairs(self.content) do
        file.write("    " .. key .. " = ")

        if type(value) == "string" then
            file.write('"' .. value .. '"')
        elseif type(value) == "table" then
            file.write(textutils.serialize(value))
        else
            file.write(tostring(value))
        end

        file.write(",\n")
    end
    file.write("}\n")

    file.close()
end

-- Call this when shutting down to ensure all logs are written
function AbstractConfig:close()
    self:flush_log()
end

return AbstractConfig
