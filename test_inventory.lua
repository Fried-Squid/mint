-- Test script for the inventory management system

-- Load the helper module for consistent module loading
local loader = dofile("mint/loader.lua")

-- Load modules with proper error handling
local config = loader.require("mint.config")
local inventory = loader.require("mint.inventory")
local logger = loader.require("mint.logger")

-- Set log level to debug for detailed output
logger.set_level(logger.LEVELS.DEBUG)

-- Mock turtle API for testing without an actual turtle
local mock_turtle = {}

-- Mock inventory state
local mock_inventory = {}

-- Initialize mock inventory
function init_mock()
    logger.info("Initializing mock turtle environment")

    -- Create a mock inventory with some items
    mock_inventory = {}
    for i = 1, 16 do
        mock_inventory[i] = nil -- Empty slots
    end

    -- Override turtle functions we'll use
    _G._original_turtle = _G.turtle
    _G.turtle = {
        getItemDetail = function(slot)
            return mock_inventory[slot]
        end,

        select = function(slot)
            logger.debug("Mock: Selected slot " .. slot)
            return true
        end,

        transferTo = function(to_slot)
            local current_slot = nil
            for i = 1, 16 do
                if mock_inventory[i] and mock_inventory[i]._selected then
                    current_slot = i
                    break
                end
            end

            if current_slot then
                logger.info("Mock: Moving item from slot " .. current_slot .. " to " .. to_slot)
                mock_inventory[to_slot] = mock_inventory[current_slot]
                mock_inventory[current_slot] = nil
                mock_inventory[to_slot]._selected = false
                return true
            else
                logger.error("Mock: No slot selected for transfer")
                return false
            end
        end,

        drop = function()
            local current_slot = nil
            for i = 1, 16 do
                if mock_inventory[i] and mock_inventory[i]._selected then
                    current_slot = i
                    break
                end
            end

            if current_slot then
                logger.info("Mock: Dropping item from slot " .. current_slot)
                mock_inventory[current_slot] = nil
                return true
            else
                logger.error("Mock: No slot selected for dropping")
                return false
            end
        end,

        equipLeft = function()
            local current_slot = nil
            for i = 1, 16 do
                if mock_inventory[i] and mock_inventory[i]._selected then
                    current_slot = i
                    break
                end
            end

            if current_slot then
                logger.info("Mock: Equipped item from slot " .. current_slot .. " on left side")
                return true
            else
                logger.error("Mock: No slot selected for equipping")
                return false
            end
        end,

        equipRight = function()
            local current_slot = nil
            for i = 1, 16 do
                if mock_inventory[i] and mock_inventory[i]._selected then
                    current_slot = i
                    break
                end
            end

            if current_slot then
                logger.info("Mock: Equipped item from slot " .. current_slot .. " on right side")
                return true
            else
                logger.error("Mock: No slot selected for equipping")
                return false
            end
        end
    }
end

-- Restore original turtle API
function cleanup_mock()
    if _G._original_turtle then
        _G.turtle = _G._original_turtle
        _G._original_turtle = nil
    end
    logger.info("Restored original turtle environment")
end

-- Add an item to the mock inventory
function add_item(slot, name, count)
    mock_inventory[slot] = {
        name = name,
        count = count or 1,
        _selected = false
    }
    logger.debug("Added " .. name .. " (x" .. (count or 1) .. ") to slot " .. slot)
end

-- Print the current state of the mock inventory
function print_inventory()
    logger.info("Current Mock Inventory:")
    for i = 1, 16 do
        if mock_inventory[i] then
            logger.info("  Slot " .. i .. ": " .. mock_inventory[i].name .. " (x" .. mock_inventory[i].count .. ")")
        else
            logger.debug("  Slot " .. i .. ": empty")
        end
    end
end

-- Test the inventory management system
function run_test()
    logger.info("=== Starting Inventory Test ===")

    -- Initialize mock environment
    init_mock()

    -- Initialize config with test values
    local test_config = {
        dotenv = {
            minerid = "test_turtle",
            ore_slots = 10,
            fuel_slots = 3,
            peripheral_slots = 3,
            trash_types = { "minecraft:cobblestone", "minecraft:dirt", "minecraft:gravel" },
            fuel_types = { "minecraft:lava_bucket", "minecraft:coal" },
            peripheral_types = { "minecraft:diamond_pickaxe", "computercraft:wireless_modem_advanced" }
        }
    }

    -- Create inventory instance
    local inv = inventory.create(test_config)
    inventory.load_from_config(inv, test_config)

    logger.info("Inventory created with configuration:")
    logger.info("  Ore slots: " ..
        test_config.dotenv.ore_slots .. " (slots " .. inv.ore_sack.end_slot .. "-" .. inv.ore_sack.start_slot .. ")")
    logger.info("  Fuel slots: " ..
        test_config.dotenv.fuel_slots .. " (slots " .. inv.fuel_sack.end_slot .. "-" .. inv.fuel_sack.start_slot .. ")")
    logger.info("  Peripheral slots: " ..
        test_config.dotenv.peripheral_slots ..
        " (slots " .. inv.peripherals_sack.end_slot .. "-" .. inv.peripherals_sack.start_slot .. ")")

    -- Add test items to the mock inventory
    add_item(1, "minecraft:iron_ore", 10)                    -- ore (slot 0)
    add_item(2, "minecraft:coal", 5)                         -- fuel (slot 1)
    add_item(3, "minecraft:diamond", 3)                      -- ore (slot 2)
    add_item(4, "minecraft:cobblestone", 64)                 -- trash (slot 3)
    add_item(5, "minecraft:dirt", 32)                        -- trash (slot 4)
    add_item(6, "minecraft:diamond_pickaxe", 1)              -- peripheral (slot 5)
    add_item(15, "minecraft:lava_bucket", 1)                 -- fuel (slot 14)
    add_item(16, "computercraft:wireless_modem_advanced", 1) -- peripheral (slot 15)

    -- Show initial state
    logger.info("Initial mock inventory state:")
    print_inventory()

    -- Run inventory update
    logger.info("Running inventory.update()...")
    inventory.update(inv)

    -- Show final state
    logger.info("Final mock inventory state after processing:")
    print_inventory()

    -- Check sack contents
    logger.info("=== Sack Contents After Processing ===")

    logger.info("Ore Sack:")
    for i, item in ipairs(inv.ore_sack.contents) do
        logger.info("  " .. item.name .. " (x" .. item.qty .. ") in slot " .. item.slot)
    end

    logger.info("Fuel Sack:")
    for i, item in ipairs(inv.fuel_sack.contents) do
        logger.info("  " .. item.name .. " (x" .. item.qty .. ") in slot " .. item.slot)
    end

    logger.info("Peripherals Sack:")
    for i, item in ipairs(inv.peripherals_sack.contents) do
        logger.info("  " .. item.name .. " (x" .. item.qty .. ") in slot " .. item.slot)
    end

    logger.info("Trash Sack:")
    for i, item in ipairs(inv.trash_sack.contents) do
        logger.info("  " .. item.name .. " (x" .. item.qty .. ") in slot " .. item.slot)
    end

    -- Test equipping a peripheral
    logger.info("Testing equip function with diamond pickaxe")
    local equip_result = inventory.equip(inv, "minecraft:diamond_pickaxe")
    logger.info("Equip result: " .. tostring(equip_result))
    logger.info("Equipped item: " .. tostring(inv.equipped))

    -- Cleanup
    cleanup_mock()
    logger.info("=== Inventory Test Complete ===")
end

-- Run the test
run_test()
