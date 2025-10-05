-- Main mining program

-- Load modules directly
local config = require("config")
local movement = require("movement")
local inventory = require("inventory")

-- Ensure turtle API is available
if not turtle and _G.turtle then
    turtle = _G.turtle
end

print("Miner initialization...")
print("Miner ID: " .. config.dotenv.minerid)

-- Initialize minerstate with zdir (0 for negative Z, 1 for positive Z)
local zdir = 0 -- Default to negative Z direction
config.init_minerstate(zdir)

-- Create inventory and load config
local inv = inventory.create(config)
inventory.load_from_config(inv, config)

print("Inventory configured:")
print("  Ore sack: " .. config.dotenv.ore_slots .. " slots")
print("  Fuel sack: " .. config.dotenv.fuel_slots .. " slots")
print("  Peripheral sack: " .. config.dotenv.peripheral_slots .. " slots")

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

    -- Update inventory after each step
    inventory.update(inv)
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
        -- Use inventory's refueling function
        print("Attempting to refuel...")
        local refueled = inventory.refuel(inv)
        if refueled then
            print("Successfully refueled. New level: " .. turtle.getFuelLevel())
        else
            print("Failed to refuel automatically")
        end
    end
end

-- Check if ore sack is full
local function check_ore_sack_full()
    -- Update inventory tracking
    inventory.update(inv)

    -- Check if ore sack is at capacity
    if inv.ore_sack.used_slots >= inv.ore_sack.slots_max then
        print("WARNING: Ore sack is full! Mining will stop.")
        return true
    end
    return false
end

-- Main execution
local function main()
    print("Miner program starting...")

    -- Check fuel and inventory before starting
    check_fuel()
    inventory.update(inv)

    -- Execute mining continuously until ore sack is full or out of fuel
    print("Beginning continuous mining operations...")
    print("Will mine until ore sack is full or fuel runs out.")

    local steps_completed = 0
    local continue_mining = true

    while continue_mining do
        -- Check fuel before step
        local fuel_level = turtle.getFuelLevel()
        if fuel_level == "unlimited" then
            print("Fuel: Unlimited")
        else
            print("Fuel: " .. fuel_level)
            if fuel_level < 1000 then
                print("WARNING: Fuel level critical, attempting to refuel...")
                if not inventory.refuel(inv) then
                    print("STOPPING: Not enough fuel to continue")
                    continue_mining = false
                    break
                end
            elseif fuel_level < config.dotenv.fuel_threshold then
                print("Fuel below threshold, refueling...")
                inventory.refuel(inv)
            end
        end

        -- Stop if not enough fuel for a full step (estimated 100 fuel)
        if fuel_level ~= "unlimited" and fuel_level < 100 then
            print("STOPPING: Not enough fuel to safely complete next step")
            continue_mining = false
            break
        end

        -- Execute one mining step
        print("Starting mining step #" .. (steps_completed + 1))
        step()
        steps_completed = steps_completed + 1
        print("Completed mining step #" .. steps_completed)

        -- Check inventory after step
        inventory.update(inv)

        if check_ore_sack_full() then
            print("STOPPING: Ore sack is full. Please empty inventory and restart.")
            continue_mining = false
            break
        end

        -- Brief pause between steps (optional)
        os.sleep(1)
    end

    print("Mining operation ended after " .. steps_completed .. " steps")
    print("Fuel remaining: " .. (turtle.getFuelLevel() == "unlimited" and "Unlimited" or turtle.getFuelLevel()))
    print("Ore sack: " .. inv.ore_sack.used_slots .. "/" .. inv.ore_sack.slots_max .. " slots used")
    print("To restart mining, run the program again")
end

-- Run the main function
main()
