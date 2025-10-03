local AbstractConfig = require("mintlib.config")
local FS = _G.fs -- Get the ComputerCraft filesystem API

local Mint = {}
Mint.__index = Mint

-- Generate a simple UUID
local function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local uuid = string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
    return uuid
end

function Mint.new(module_name)
    local self = setmetatable({}, Mint)
    self.module_name = module_name or "unknown"
    self.uuid = generate_uuid()
    self.configs = {}
    return self
end

function Mint:config(config_name)
    -- Parse config name (format: module.name)
    local module_name, config_type = config_name:match("([^.]+)%.([^.]+)")
    module_name = module_name or self.module_name
    config_type = config_type or config_name

    -- Check if this config is already loaded
    local cache_key = module_name .. "." .. config_type
    if self.configs[cache_key] then
        -- Register this target if not already registered
        self.configs[cache_key]:register_target(self.uuid)
        return Config.new(self.configs[cache_key], self.uuid)
    end

    -- Build paths
    local config_path = "mint/configs/" .. module_name .. "/" .. config_type .. ".lua"
    local template_path = "mint/config_templates/." .. module_name .. "." .. config_type .. ".template"

    -- Create directory if it doesn't exist
    if not FS.exists("mint/configs/" .. module_name) then
        FS.makeDir("mint/configs/" .. module_name)
    end

    -- Check if template exists
    if not FS.exists(template_path) then
        error("Template not found: " .. template_path)
    end

    -- Check if config exists, create from template if it doesn't
    if not FS.exists(config_path) then
        -- Copy template content to create config
        local template_content = dofile(template_path)
        local file = FS.open(config_path, "w")
        file.write("return {\n")
        for key, value in pairs(template_content) do
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

    -- Create the AbstractConfig instance
    local abstract_config = AbstractConfig.new(config_type, template_path, config_path)

    -- Register this target
    abstract_config:register_target(self.uuid)

    -- Cache it
    self.configs[cache_key] = abstract_config

    -- Return a Config wrapper bound to this target
    return Config.new(abstract_config, self.uuid)
end

function Mint:close_all()
    for _, config in pairs(self.configs) do
        config:close()
    end
end

-- Config wrapper class
Config = {}
Config.__index = Config

function Config.new(abstract_config, target_uuid)
    local self = setmetatable({}, Config)
    self.abstract_config = abstract_config
    self.target_uuid = target_uuid
    return self
end

function Config:read(key)
    return self.abstract_config:read(self.target_uuid, key)
end

function Config:unsafe_read(key)
    return self.abstract_config:unsafe_read(self.target_uuid, key)
end

function Config:write(key, val)
    self.abstract_config:write(self.target_uuid, key, val)
end

function Config:unsafe_write(key, val)
    self.abstract_config:unsafe_write(self.target_uuid, key, val)
end

function Config:write_many(keys, vals)
    self.abstract_config:write_many(self.target_uuid, keys, vals)
end

function Config:unsafe_write_many(keys, vals)
    self.abstract_config:unsafe_write_many(self.target_uuid, keys, vals)
end

function Config:is_valid()
    return self.abstract_config.metadata.validity
end

function Config:close()
    self.abstract_config:deregister_target(self.target_uuid)
    self.abstract_config:close()
end

return Mint
