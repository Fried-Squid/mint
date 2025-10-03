local API = {}

function API.init(dotenv_config)
    API.dotenv = dotenv_config
end

function API.encode_courier_request(x, y, z, fuel_needed)
    return string.format("%d,%d,%d,%d", x, y, z, fuel_needed)
end

function API.decode_courier_response(response)
    local channel, message = response:match("^([^,]+),(.+)$")
    return channel, message
end

function API.send_courier_request(body)
    local response = http.post(API.dotenv:read("server_url"), body)
    if response then
        local content = response.readAll()
        response.close()
        return content
    end
    return nil
end

-- API function to request current config from server
function API.request_config_sync()
    local body = string.format("minerid=%s&action=get_config", API.dotenv:read("minerid"))
    return API.send_courier_request(body)
end

-- Decode config sync response from server
function API.decode_config_response(response)
    local status, config_type, data = response:match("^([^,]+),([^,]+),(.+)$")
    
    if status ~= "ok" then
        return nil, "Config sync failed: " .. (data or "unknown error")
    end
    
    -- Parse key=value pairs
    local config = {}
    for key, value in data:gmatch("([^&=]+)=([^&]+)") do
        local num = tonumber(value)
        config[key] = num or value
    end
    
    return config_type, config
end

-- Main sync function - checks server and replaces local files if different
function API.sync_configs(dotenv, tunnelstate, minerstate)
    local response = API.request_config_sync()
    if not response then
        print("Failed to contact server")
        return false
    end
    
    local config_type, new_config = API.decode_config_response(response)
    if not config_type then
        print("Error: " .. tostring(new_config))
        return false
    end
    
    -- Determine which config to update
    local config
    if config_type == "tunnelstate" then
        config = tunnelstate
    elseif config_type == "minerstate" then
        config = minerstate
    elseif config_type == "dotenv" then
        config = dotenv
    else
        print("Unknown config type: " .. config_type)
        return false
    end
    
    -- Get all current keys for comparison
    local current_keys = {}
    for key, _ in pairs(new_config) do
        current_keys[key] = config:unsafe_read(key)
    end
    
    -- Compare configs
    local needs_update = false
    for key, value in pairs(new_config) do
        if current_keys[key] ~= value then
            needs_update = true
            break
        end
    end
    
    -- Replace if different
    if needs_update then
        print("Config mismatch detected, updating " .. config_type)
        
        local keys = {}
        local vals = {}
        for key, value in pairs(new_config) do
            table.insert(keys, key)
            table.insert(vals, value)
        end
        
        config:unsafe_write_many(keys, vals)
        
        print("Config updated successfully")
        return true
    else
        print("Config already up to date")
        return true
    end
end

return API