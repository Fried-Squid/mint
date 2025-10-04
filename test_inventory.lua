-- Simple test script for inventory management system on a real turtle
local inventory = require("inventory")
local config = require("config")

-- Ensure we have access to the turtle API
if not turtle and _G.turtle then
    turtle = _G.turtle
end

print("=== Inventory Management Test ===")
print("This test will organize your turtle's inventory")
print("Place items in the turtle before running")
print()

-- Initialize test config
local test_config = {
    dotenv = {
        minerid = "test_turtle",
        ore_slots = 10,
        fuel_slots = 3,
        peripheral_slots = 3,
        trash_types = { "minecraft:cobblestone", "minecraft:dirt", "minecraft:gravel", "minecraft:diorite", "minecraft:andesite", "minecraft:granite" },
        fuel_types = { "minecraft:lava_bucket", "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block" },
        peripheral_types = { "minecraft:diamond_pickaxe", "computercraft:wireless_modem_advanced", "advanced_peripherals:end_automata_core" }
    }
}

-- Print current inventory state
function print_inventory()
    print("Current Inventory:")
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            print(string.format("  Slot %2d: %s (x%d)", slot, item.name, item.count))
        else
            print(string.format("  Slot %2d: empty", slot))
        end
    end
end

-- Create inventory instance
local inv = inventory.create(test_config)
inventory.load_from_config(inv, test_config)

-- Print configuration
print("Inventory configuration:")
print(string.format("  Ore slots: %d (slots %d-%d)",
    test_config.dotenv.ore_slots,
    inv.ore_sack.end_slot + 1,
    inv.ore_sack.start_slot + 1))
print(string.format("  Fuel slots: %d (slots %d-%d)",
    test_config.dotenv.fuel_slots,
    inv.fuel_sack.end_slot + 1,
    inv.fuel_sack.start_slot + 1))
print(string.format("  Peripheral slots: %d (slots %d-%d)",
    test_config.dotenv.peripheral_slots,
    inv.peripherals_sack.end_slot + 1,
    inv.peripherals_sack.start_slot + 1))
print()

-- Show initial inventory state
print("Initial inventory state:")
print_inventory()
print()

-- Run inventory update
print("Organizing inventory...")
inventory.update(inv)

-- Show final inventory state
print()
print("Final inventory state after processing:")
print_inventory()
print()

-- Print categorized items
print("=== Items After Categorization ===")

print("Ore Sack:")
for i, item in ipairs(inv.ore_sack.contents) do
    print(string.format("  %s (x%d) in slot %d", item.name, item.qty, item.slot + 1))
end
print()

print("Fuel Sack:")
for i, item in ipairs(inv.fuel_sack.contents) do
    print(string.format("  %s (x%d) in slot %d", item.name, item.qty, item.slot + 1))
end
print()

print("Peripherals Sack:")
for i, item in ipairs(inv.peripherals_sack.contents) do
    print(string.format("  %s (x%d) in slot %d", item.name, item.qty, item.slot + 1))
end
print()

print("Trash (Dropped Items):")
for i, item in ipairs(inv.trash_sack.contents) do
    print(string.format("  %s (x%d) was dropped", item.name, item.qty))
end
print()

print("=== Inventory Test Complete ===")
