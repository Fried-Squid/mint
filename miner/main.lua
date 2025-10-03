-- Miner Module - Main Entry Point
-- This file is the entry point for the miner module when called from the launcher

local Mint = require("mintlib.mint")
local API = require("miner.api")
local MinerImpl = require("miner.miner")

-- Module exports
local Miner = {}

-- Command implementations
local commands = {}

-- Run the miner operations
function commands.start(args)
    print("Starting miner...")

    -- Create mint instance with UUID
    local mint = Mint.new("miner")

    -- Load configurations with simplified API
    local env = mint:config("miner.env")
    local tunnelstate = mint:config("tunnel.state")
    local minerstate = mint:config("miner.state")

    -- Initialize API with config
    API.init(env)

    -- Validate configurations
    if not validateConfigs(env, tunnelstate, minerstate) then
        print("Configuration validation failed")
        return false
    end

    -- Run the mining operations
    local success = MinerImpl.run(mint, env, tunnelstate, minerstate)

    -- Clean up
    mint:close_all()

    return success
end

-- Show miner status
function commands.status(args)
    print("Checking miner status...")

    local mint = Mint.new("miner")
    local minerstate = mint:config("miner.state")
    local tunnelstate = mint:config("tunnel.state")

    print("=== Miner Status ===")
    print("Current step: " .. minerstate:read("step"))
    print("Current substep: " .. minerstate:read("substep"))
    print("Looking direction: " .. minerstate:read("lookdir"))

    print("\n=== Tunnel Status ===")
    print("Position: " .. tunnelstate:read("xpos") .. ", " ..
        tunnelstate:read("ypos") .. ", " .. tunnelstate:read("zpos"))
    print("Tunnel direction: " .. (tunnelstate:read("zdir") == 0 and "-Z" or "+Z"))
    print("Tunnel ID: " .. tunnelstate:read("id"))

    mint:close_all()
    return true
end

-- Configure miner settings
function commands.config(args)
    print("Configuring miner...")

    local mint = Mint.new("miner")
    local env = mint:config("miner.env")

    if #args == 0 then
        -- Display current configuration
        print("=== Miner Configuration ===")
        print("Miner ID: " .. (env:read("minerid") or "not set"))
        print("Server URL: " .. (env:read("server_url") or "not set"))
    else
        -- Set configuration values
        local key = args[1]
        local value = args[2]

        if not value then
            print("Usage: miner config <key> <value>")
            return false
        end

        env:write(key, value)
        print("Set " .. key .. " = " .. value)
    end

    mint:close_all()
    return true
end

-- Reset miner state
function commands.reset(args)
    print("Resetting miner state...")

    local mint = Mint.new("miner")
    local minerstate = mint:config("miner.state")

    minerstate:write("step", 0)
    minerstate:write("substep", 0)
    minerstate:write("lookdir", 0)

    print("Miner state has been reset")
    mint:close_all()
    return true
end

-- Validate all required configurations
function validateConfigs(env, tunnelstate, minerstate)
    local valid = true

    -- Validate environment config
    if not env:read("minerid") then
        print("Error: minerid not set in .env")
        valid = false
    end

    if not env:read("server_url") then
        print("Error: server_url not set")
        valid = false
    end

    -- Validate tunnel state
    if not (tunnelstate:read("xpos") and tunnelstate:read("ypos") and tunnelstate:read("zpos")) then
        print("Error: Tunnel position incomplete")
        valid = false
    end

    if not (tunnelstate:read("zdir") == 0 or tunnelstate:read("zdir") == 1) then
        print("Error: Tunnel zdir not set correctly")
        valid = false
    end

    if not tunnelstate:read("id") then
        print("Error: Tunnel ID missing")
        valid = false
    end

    -- Validate miner state
    if not (minerstate:read("lookdir") >= 0 and minerstate:read("lookdir") <= 3) then
        print("Error: Invalid lookdir")
        valid = false
    end

    if not (minerstate:read("step") and minerstate:read("substep")) then
        print("Error: Miner step/substep missing")
        valid = false
    end

    return valid
end

-- Main run function, called by launcher
function Miner.run(...)
    local args = { ... }
    local command = args[1] or "start"
    table.remove(args, 1)

    if not commands[command] then
        print("Unknown command: " .. command)
        print("Available commands: start, status, config, reset")
        return false
    end

    return commands[command](args)
end

return Miner
