-- Main mining program
local config = require("mint/config")
local movement = require("mint/movement")
local inventory = require("mint/inventory")

print("Miner initialization...")
print("Miner ID: " .. config.dotenv.minerid)

-- Initialize minerstate with zdir (0 for negative Z, 1 for positive Z)
local zdir = 0 -- Default to negative Z direction
config.init_minerstate(zdir)

-- Mining step function
local function step()
    -- We assume we start FACING the top left block on even (incl 0 steps) and the BOTTOM left on odd.
    -- Therefore our first move is always a dig forward:
    movement.forcemove_h(1) -- step=x/1

    -- After this we set the up/down dir:
    local vdir = (config.minerstate.step % 2 ~= 0) and 1 or 0 -- 1 for odd steps, 0 for even

    -- We now set lookdir to face right which depends on the tunnel direction
    -- If zdir is 0 (negative Z), then right is +X (0)
    -- If zdir is 1 (positive Z), then right is -X (2)
    if config.minerstate.zdir == 0 then
        movement.setlook(0) -- Face +X
    else
        movement.setlook(2) -- Face -X
    end

    for i = 1, 7 do
        movement.forcemove_h(7)                               -- forcemove along row
        movement.forcemove_v(1, vdir)                         -- move vdir
        movement.setlook((config.minerstate.lookdir + 2) % 4) -- swap look direction
    end

    -- Finally we forcemove 7 along the final row:
    movement.forcemove_h(7)

    config.minerstate.step = config.minerstate.step + 1 -- inc step

    -- Set final look direction based on zdir
    -- If zdir is 0 (negative Z), face -Z (3)
    -- If zdir is 1 (positive Z), face +Z (1)
    if config.minerstate.zdir == 0 then
        movement.setlook(3) -- Face -Z
    else
        movement.setlook(1) -- Face +Z
    end

    config.save_config(".minerstate", config.minerstate)
    print("Completed mining step " .. config.minerstate.step)
end

-- Check fuel level
local function check_fuel()
    -- Get turtle API if not already defined
    if not turtle and _G.turtle then
        turtle = _G.turtle
    end
    local fuel_level = turtle.getFuelLevel()
    print("Current fuel level: " .. fuel_level)

    -- If fuel is below threshold and not infinite
    if fuel_level < config.dotenv.fuel_threshold and fuel_level ~= "unlimited" then
        print("Fuel below threshold (" .. config.dotenv.fuel_threshold .. ")")
        -- Add refueling logic here if needed
    end
end

-- Main execution
local function main()
    print("Miner program starting...")

    -- Create inventory with slot configuration from config
    local inv = inventory.create(config)
    inventory.load_from_config(inv, config)

    -- Check fuel before starting
    check_fuel()

    -- Execute two mining steps
    print("Beginning mining operations...")
    step()
    print("First step complete")

    step()
    print("Second step complete")

    print("Mining operation completed successfully")
end

-- Run the main function
main()
