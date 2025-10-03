local AbstractConfig = require("mintlib.config")

local Mint = {}
Mint.__index = Mint

function Mint.new()
    local self = setmetatable({}, Mint)
    self.configs = {}
    return self
end

function Mint:open(target, config_name)
    -- Check if this config is already loaded
    local cache_key = config_name
    if self.configs[cache_key] then
        -- Register this target if not already registered
        self.configs[cache_key]:register_target(target)
        return Config.new(self.configs[cache_key], target)
    end
    
    -- Build paths
    local config_path = "mint/configs/" .. target .. "/" .. config_name .. ".lua"
    local template_path = "mint/configs/" .. target .. "/" .. config_name .. ".template.lua"
    
    -- Check if config exists
    if not fs.exists(config_path) then
        error("Config not found: " .. config_path)
    end
    
    -- Check if template exists
    if not fs.exists(template_path) then
        error("Template not found: " .. template_path)
    end
    
    -- Create the AbstractConfig instance
    local abstract_config = AbstractConfig.new(config_name, template_path, config_path)
    
    -- Register this target
    abstract_config:register_target(target)
    
    -- Cache it
    self.configs[cache_key] = abstract_config
    
    -- Return a Config wrapper bound to this target
    return Config.new(abstract_config, target)
end

function Mint:close_all()
    for _, config in pairs(self.configs) do
        config:close()
    end
end

-- Config wrapper class
Config = {}
Config.__index = Config

function Config.new(abstract_config, target)
    local self = setmetatable({}, Config)
    self.abstract_config = abstract_config
    self.target = target
    return self
end

function Config:read(key)
    return self.abstract_config:read(self.target, key)
end

function Config:unsafe_read(key)
    return self.abstract_config:unsafe_read(self.target, key)
end

function Config:write(key, val)
    self.abstract_config:write(self.target, key, val)
end

function Config:unsafe_write(key, val)
    self.abstract_config:unsafe_write(self.target, key, val)
end

function Config:write_many(keys, vals)
    self.abstract_config:write_many(self.target, keys, vals)
end

function Config:unsafe_write_many(keys, vals)
    self.abstract_config:unsafe_write_many(self.target, keys, vals)
end

function Config:is_valid()
    return self.abstract_config.metadata.validity
end

function Config:close()
    self.abstract_config:deregister_target(self.target)
    self.abstract_config:close()
end

return Mint