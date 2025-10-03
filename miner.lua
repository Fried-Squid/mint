-- Load config files
local function loadconfig(filepath)
    local dir = "mint/"
    if not fs.exists(dir .. filepath) then
        error("Config file not found: " .. filepath)
    end
    return dofile(dir .. filepath)
end

dotenv = loadconfig(".env")
assert(dotenv.minerid ~= nil, "minerid not set in .env")
assert(dotenv.server_url ~= nil, "serverurl not set")

-- State skeleton
tunnelstate = loadconfig(".tunnelstate")
minerstate  = loadconfig(".minerstate")

-- Assertions
assert(tunnelstate.xpos and tunnelstate.ypos and tunnelstate.zpos, "Tunnel position incomplete")
assert(tunnelstate.zdir == 0 or tunnelstate.zdir == 1, "Tunnel zdir not set correctly")
assert(tunnelstate.id, "Tunnel ID missing")
assert(minerstate.lookdir >= 0 and minerstate.lookdir <= 3, "Invalid lookdir")
assert(minerstate.step and minerstate.substep, "Miner step/substep missing")

print("Configuration loaded successfully")

-- API Skeleton
local API = {}

function API.encode_courier_request(x, y, z, fuel_needed)
    return string.format("%d,%d,%d,%d", x, y, z, fuel_needed)
end

function API.decode_courier_response(response)
    local channel, message = response:match("^([^,]+),(.+)$")
    return channel, message
end

function API.send_courier_request(body)
    local response = http.post(dotenv.server_url, body)
    if response then
        local content = response.readAll()
        response.close()
        return content
    end
    return nil
end

-- API function to request current config from server
function API.request_config_sync()
    local body = string.format("minerid=%s&action=get_config", dotenv.minerid)
    return API.send_courier_request(body)
end

-- Decode config sync response from server
function API.decode_config_response(response)
    -- Expected format: "status,config_type,data"
    -- Example: "ok,tunnelstate,xpos=10&ypos=20&zpos=30&id=5"
    local status, config_type, data = response:match("^([^,]+),([^,]+),(.+)$")
    
    if status ~= "ok" then
        return nil, "Config sync failed: " .. (data or "unknown error")
    end
    
    -- Parse key=value pairs
    local config = {}
    for key, value in data:gmatch("([^&=]+)=([^&]+)") do
        -- Try to convert to number if possible
        local num = tonumber(value)
        config[key] = num or value
    end
    
    return config_type, config
end

-- Save config to file (replaces entire file)
function API.save_config(filepath, config)
    local file = fs.open(filepath, "w")
    file.write("return {\n")
    for key, value in pairs(config) do
        if type(value) == "string" then
            file.write(string.format('  %s = "%s",\n', key, value))
        else
            file.write(string.format('  %s = %s,\n', key, tostring(value)))
        end
    end
    file.write("}\n")
    file.close()
end

-- Main sync function - checks server and replaces local files if different
function API.sync_configs()
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
    
    -- Determine which file to update
    local filepath, current_config
    if config_type == "tunnelstate" then
        filepath = ".tunnelstate"
        current_config = tunnelstate
    elseif config_type == "minerstate" then
        filepath = ".minerstate"
        current_config = minerstate
    elseif config_type == "dotenv" then
        filepath = ".env"
        current_config = dotenv
    else
        print("Unknown config type: " .. config_type)
        return false
    end
    
    -- Compare configs
    local needs_update = false
    for key, value in pairs(new_config) do
        if current_config[key] ~= value then
            needs_update = true
            break
        end
    end
    
    -- Replace file if different
    if needs_update then
        print("Config mismatch detected, updating " .. filepath)
        API.save_config(filepath, new_config)
        
        -- Reload the config into memory
        if config_type == "tunnelstate" then
            tunnelstate = loadconfig(filepath)
        elseif config_type == "minerstate" then
            minerstate = loadconfig(filepath)
        elseif config_type == "dotenv" then
            dotenv = loadconfig(filepath)
        end
        
        print("Config updated successfully")
        return true
    else
        print("Config already up to date")
        return true
    end
end

-- Miner movement functions

function setlook(wishdir)
    assert(wishdir <= 3 and wishdir >= 0, "cannot set erroneous lookdir")
    
    local curdir = minerstate.lookdir
    if curdir ~= wishdir then
        -- Calculate shortest rotation direction
        local diff = wishdir - curdir
        
        -- Normalize to -2 to 2 range, then pick shortest path
        if diff > 2 then
            diff = diff - 4
        elseif diff < -2 then
            diff = diff + 4
        end
        
        local binding = (diff > 0) and turtle.turnRight or turtle.turnLeft
        local steps = math.abs(diff)
        
        for i = 1, steps do
            binding()
            curdir = (curdir + (diff > 0 and 1 or -1)) % 4
            minerstate.lookdir = curdir
            
            -- Write config to file immediately in case of crash
            API.save_config(".minerstate", minerstate)
        end
    end
end

function forcemove_h(blocks)
    for i = 1, blocks do
        local ok = turtle.forward()
        if not ok then
            turtle.dig()
            ok = turtle.forward()
            if not ok then
                return false, "blocked after dig"
            end
        end
        
        -- Increment substep and wrap at 64
        minerstate.substep = (minerstate.substep + 1) % 64
        
        -- Save state after each block moved
        API.save_config(".minerstate", minerstate)
    end
    return true
end

function forcemove_v(blocks, dir) -- 0 down 1 up
    assert(dir == 0 or dir == 1, "dir must be 0 for down 1 for up")
    
    local movebind = (dir == 0) and turtle.down or turtle.up
    local digbind  = (dir == 0) and turtle.digDown or turtle.digUp
    
    for i = 1, blocks do
        local ok = movebind()
        if not ok then
            digbind()
            ok = movebind()
            if not ok then
                return false, "blocked after dig"
            end
        end
        
        -- Increment substep and wrap at 64
        minerstate.substep = (minerstate.substep + 1) % 64
        
        -- Save state after each block moved
        API.save_config(".minerstate", minerstate)
    end
    return true
end

function step()
    -- We assume we start FACING the top left block on even (incl 0 steps) and the BOTTOM left on odd.
    -- Therefore our first move is always a dig forward:
    forcemove_h(1) -- step=x/1
    -- After this we set the up/down dir:
    local vdir = (minerstate.step % 2 ~= 0) and 1 or 0 -- this is saying if odd, 1 and 1 else 0 therefore 1 odd 0 even.

    -- We now set lookdir to face along RIGHT which depends on the tunnel direction. If tunnel direction is 
    -- 1 (+Z) we are moving to -X to face right, else +X. +X is 00_2, -X is 10_2 so 2
    if tunnelstate.zdir == 0 then
	setlook(0) -- + zdir -> -X
    else
	setlook(2) -- - zdir -> +X
    end
    for i = 1, 7 do
        forcemove_h(7) -- forcemove along row
	forcemove_v(1, vdir) -- move vdir
	setlook((minerstate.lookdir + 2) % 4) -- swap look sign bit (2 becomes 0, 0 becomes 2)
    end
    -- Finally we forcemove 7 along the final row:
    forcemove_h(7)

    minerstate.step = minerstate.step + 1 -- inc step
    -- now we set the final look to the tunner direction. +Z is 01_2 = 1 -Z is 11_2 = 3
    if tunnelstate.zdir == 0 then
	setlook(3)
    else
	setlook(1)
    end
    -- We are now ready to start step AGAIN.
end

step()
step()


