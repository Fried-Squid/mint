-- savehome.lua - Script to save the current position as "home" waypoint
-- For use with the mining turtle equipped with an End Automata Core

local inventory = require("inventory")

-- Function to save home point
local function saveHome()
    print("=== Saving Home Waypoint ===")

    -- Create inventory tracking if needed
    local config = require("config")
    local inv = inventory.create(config)
    inventory.load_from_config(inv, config)

    -- First update inventory to know what we have
    print("Scanning inventory...")
    inventory.update(inv)

    -- Step 1: Equip the end automata core
    print("Equipping End Automata Core...")
    if not inventory.equip_automata_core(inv) then
        print("ERROR: Failed to equip automata core!")
        print("Make sure an advancedperipherals:end_automata_core is in your peripherals sack")
        return false
    end

    -- Step 2: Get the peripheral and save the waypoint
    local core = peripheral.find("endAutomata")
    if not core then
        print("ERROR: End Automata Core not detected as a peripheral!")
        print("Make sure the core is properly equipped on the right side")
        inventory.equip_pickaxe(inv) -- Attempt to re-equip pickaxe
        return false
    end

    -- Step 3: Save current position as "home"
    print("Saving current position as 'home'...")
    local success = core.savePoint("home")
    if not success then
        print("ERROR: Failed to save home waypoint!")
        inventory.equip_pickaxe(inv)
        return false
    end

    print("SUCCESS: Home waypoint saved!")
    print("Current waypoints:")
    local points = core.points()
    if points then
        for name, _ in pairs(points) do
            print(" - " .. name)
        end
    end

    -- Step 4: Re-equip the pickaxe for mining
    print("Re-equipping mining pickaxe...")
    if not inventory.equip_pickaxe(inv) then
        print("WARNING: Failed to re-equip pickaxe")
    end

    return true
end

-- Run the save home function
saveHome()
