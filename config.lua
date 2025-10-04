-- Configuration module for the mining turtle
local config = {}

-- Load config files
local function loadconfig(filepath)
    local dir = "mint/"
    if not fs and _G.fs then
        fs = _G.fs
    end
    if not fs.exists(dir .. filepath) then
        error("Config file not found: " .. filepath)
    end
    return dofile(dir .. filepath)
end

-- Attempt to load .env file
local function init()
    -- Create default .env file if it doesn't exist
    if not fs and _G.fs then
        fs = _G.fs
    end

    if not fs.exists("mint/.env") then
        local default_env = {
            minerid = "turtle1",
            fuel_threshold = 100,
            inventory_threshold = 10,
            ore_slots = 10,
            fuel_slots = 3,
            peripheral_slots = 3,
            trash_types = { "minecraft:cobblestone", "minecraft:dirt", "minecraft:gravel" },
            fuel_types = { "minecraft:lava_bucket", "minecraft:bucket" },
            peripheral_types = { "minecraft:diamond_pickaxe", "computercraft:wireless_modem_advanced", "advanced_peripherals:end_automata_core" }
        }
        config.save_config(".env", default_env)
    end

    local dotenv = loadconfig(".env")
    assert(dotenv.minerid ~= nil, "minerid not set in .env")

    -- Set default values for mining thresholds if not present
    dotenv.fuel_threshold = dotenv.fuel_threshold or 100
    dotenv.inventory_threshold = dotenv.inventory_threshold or 10

    -- Set default values for inventory slot allocation
    dotenv.ore_slots = dotenv.ore_slots or 10
    dotenv.fuel_slots = dotenv.fuel_slots or 3
    dotenv.peripheral_slots = dotenv.peripheral_slots or 3

    -- Set default values for item classification lists if not present
    dotenv.trash_types = dotenv.trash_types or {}
    dotenv.fuel_types = dotenv.fuel_types or {}
    dotenv.peripheral_types = dotenv.peripheral_types or {}

    config.dotenv = dotenv

    -- Set up minerstate if it doesn't exist - this is a state file, not config
    if not fs.exists("mint/.minerstate") then
        config.minerstate = {
            lookdir = 0, -- 0=north, 1=east, 2=south, 3=west
            step = 0,    -- Which main step in the mining process
            substep = 0, -- Progress through current step
            zdir = nil   -- Will be set by miner.lua
        }
    else
        config.minerstate = loadconfig(".minerstate")
        -- Validate minerstate
        assert(config.minerstate.lookdir >= 0 and config.minerstate.lookdir <= 3, "Invalid lookdir")
        assert(config.minerstate.step ~= nil and config.minerstate.substep ~= nil, "Miner step/substep missing")
    end

    return true
end

-- Function to initialize minerstate with zdir
function config.init_minerstate(zdir)
    assert(zdir == 0 or zdir == 1, "zdir must be 0 for negative or 1 for positive")

    -- Set zdir in minerstate
    config.minerstate.zdir = zdir

    -- Save updated minerstate
    config.save_config(".minerstate", config.minerstate)

    print("Initialized minerstate with zdir: " .. zdir)
    return config.minerstate
end

-- Save config to file (replaces entire file)
function config.save_config(filepath, configdata)
    if not fs and _G.fs then
        fs = _G.fs
    end
    local file = fs.open("mint/" .. filepath, "w")
    file.write("return {\n")
    for key, value in pairs(configdata) do
        if type(value) == "string" then
            file.write(string.format('  %s = "%s",\n', key, value))
        else
            file.write(string.format('  %s = %s,\n', key, tostring(value)))
        end
    end
    file.write("}\n")
    file.close()
end

-- Initialize on module load
init()

return config
