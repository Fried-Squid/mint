-- Miner Module - Main Entry Point
local Mint = require("mintlib.mint")
local API = require("miner.api")

-- Initialize Mint and open configs
local function init()
    local mint = Mint.new("miner")
    local dotenv = mint:config("miner.env")
    local tunnelstate = mint:config("tunnel.state")
    local minerstate = mint:config("miner.state")

    -- Initialize API with dotenv
    API.init(dotenv)

    -- Assertions for dotenv
    assert(dotenv:read("minerid") ~= nil, "minerid not set in .env")
    assert(dotenv:read("server_url") ~= nil, "serverurl not set")

    -- Assertions for tunnelstate
    assert(tunnelstate:read("xpos") and tunnelstate:read("ypos") and tunnelstate:read("zpos"),
        "Tunnel position incomplete")
    assert(tunnelstate:read("zdir") == 0 or tunnelstate:read("zdir") == 1,
        "Tunnel zdir not set correctly")
    assert(tunnelstate:read("id"), "Tunnel ID missing")

    -- Assertions for minerstate
    assert(minerstate:read("lookdir") >= 0 and minerstate:read("lookdir") <= 3,
        "Invalid lookdir")
    assert(minerstate:read("step") and minerstate:read("substep"),
        "Miner step/substep missing")

    return mint, dotenv, tunnelstate, minerstate
end

local function run()
    print("Starting miner...")

    -- Load configurations
    local mint, dotenv, tunnelstate, minerstate = init()

    print("Configuration loaded successfully")

    -- 2 step stub
    step()
    step()
    
    mint:close_all()

    return true
end

-- Module exports for the package manager
local Miner = {
    run = function(...)
        local args = { ... }
        local command = args[1] or "run"

        if command == "run" then
            return run()
        elseif command == "status" then
            print("Checking miner status...")
            local mint, _, tunnelstate, minerstate = init()

            print("Tunnel position: " .. tunnelstate:read("xpos") .. ", " ..
                tunnelstate:read("ypos") .. ", " .. tunnelstate:read("zpos"))
            print("Current step: " .. minerstate:read("step"))

            mint:close_all()
            return true
        else
            print("Unknown command: " .. command)
            print("Available commands: run, status")
            return false
        end
    end
}

return Miner
