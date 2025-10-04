-- Inventory module for the mining turtle
-- Okay so to explain
-- CC treats the inventory as a slot-based model but we effectively want buckets (sacks makes more contextual sense)
-- When items come in they come in on the minimum free slot ONLY if they cant fill an existing sack.
-- So what this means functionally is that a sack we can nicely treat a sack as a partition on the slot-based storage.
-- So lets first assign these slots though to be filled in REVERSE by the inventory manager.
-- For example with 8 ore 6 fuel 2 peripheral_slots we set slots 15-16 to be peripheral_slots
-- slots 8-14 as fuel and 1-7 as ore.
-- When a peripheral is pulled in (more on that in a sec) we place it in SLOT 16 - i.e. the maximum numbered slot within the sacks range
-- So what this leaves us if we have the usual config of full fuel and peripheral_slots is we keep a pointer of end_of_sack and we starting from
-- the minimum number of the eariest sack in the inventory (i.e. search the sack [FROM end_of_start TO min] with the lowest minium first
-- unless, then if we find no blank spaces, we search the next lowest minimum in the same way)
-- and anything the cursor hovers over in this operation is an unassigned item and we can either move the pointer of the current sack
-- to include in that sack or move to a sack (rare unless we pick up coal and we want to treat that as fuel but we'll see)
-- or drop it if it is trash (!!THUS REMOVING NEED FOR A TRASH SACK). We march the pointer to the minimum (we set a flag NO_FURTHER_SEARCH)
-- if we find an empty space as minecraft hasnt filled that space but we still need to finish searching this sack)
-- Now one issue is we should really check if the target slot in a sack is full until trying to move to it, NOT just checking if
-- theres less max_slots then free_slots as minecraft could have put an item in there. ACTUALLY, to avoid this we can just
-- call update on every turtle_inventory event and before kicking into full processing we check slot 0 and 1 and if its [item, blank]
-- just move the item to a new slot in the target or drop it - if blank,blank noop as we picked up an item we had a slot for, if [item, item]
-- do the full update process. Actually have a trash sack but whenever its full empty it. Like every time we would trash, if that trash fills the sack
-- drop the whole sack.
local inventory = {}

-- Sack type definition
-- A Sack represents a categorized portion of the turtle's inventory
-- with tracking for capacity and usage
--[[
Sack Type Structure:
- contents: List of tuples in format {name = "item_name", qty = quantity, slot = actual_inventory_slot}
- slots_max: Maximum number of inventory slots this sack can use
- used_slots: Number of inventory slots currently used by this sack
- start_slot: Starting slot in the turtle inventory (highest numbered slot in range)
- end_slot: Ending slot in the turtle inventory (lowest numbered slot in range)
]]

-- Constructor function for creating a new Sack
function inventory.create_sack(slots_max, start_slot, end_slot)
    return {
        -- Contents is a list of tuples {name = string, qty = number, slot = number}
        contents = {},

        -- Maximum slots this sack can use
        slots_max = slots_max or 0,

        -- Number of slots currently used
        used_slots = 0,

        -- Range of turtle inventory slots (filled in reverse)
        start_slot = start_slot, -- highest numbered slot in range
        end_slot = end_slot      -- lowest numbered slot in range
    }
end

-- Inventory type definition
-- The Inventory type contains specialized sacks for different types of items
--[[
Inventory Type Structure:
- raw_contents: Original unfiltered inventory contents from turtle
- ore_sack: Sack for mining resources
- fuel_sack: Sack for fuel items
- peripherals_sack: Sack for equippable items
- trash_sack: Sack for trash items (emptied when full)
- trash_types: List of item names that should be dropped
- fuel_types: List of item names considered as fuel
- peripheral_types: List of item names considered as peripherals
- current_slot: Current slot being processed during inventory update
- no_further_search: Flag to indicate if we found an empty space
]]

-- Constructor function for creating a new Inventory
-- Uses slot configuration from config
function inventory.create(config)
    local ore_slots = config.dotenv.ore_slots
    local fuel_slots = config.dotenv.fuel_slots
    local peripheral_slots = config.dotenv.peripheral_slots

    -- Validate total slots don't exceed turtle capacity
    local total_slots = ore_slots + fuel_slots + peripheral_slots
    assert(total_slots <= 16, "Total sack slots exceed turtle inventory capacity")

    -- Calculate slot ranges for each sack (in reverse)
    -- Assuming 16 slots total in turtle inventory (0-15)
    local peripheral_start = 16 - 1 -- 0-based, so 15 is the max slot
    local peripheral_end = peripheral_start - peripheral_slots + 1

    local fuel_start = peripheral_end - 1
    local fuel_end = fuel_start - fuel_slots + 1

    local ore_start = fuel_end - 1
    local ore_end = ore_start - ore_slots + 1

    return {
        -- Original unfiltered inventory contents
        raw_contents = {},

        -- Specialized sacks with slot ranges
        ore_sack = inventory.create_sack(ore_slots, ore_start, ore_end),
        fuel_sack = inventory.create_sack(fuel_slots, fuel_start, fuel_end),
        peripherals_sack = inventory.create_sack(peripheral_slots, peripheral_start, peripheral_end),
        trash_sack = inventory.create_sack(3, -1, -3), -- Special range to indicate not in main inventory

        -- Item classification lists
        trash_types = {},
        fuel_types = {},
        peripheral_types = {},

        -- Currently equipped item (can be "modem", "core", "pickaxe", or nil)
        equipped = nil,

        -- Inventory processing state
        current_slot = 0,
        no_further_search = false
    }
end

-- Inventory update function stub
function inventory.update(inv)
    -- TODO: Implement full inventory updating logic

    -- 1. Quick check for new items in slots 0 and 1
    -- If slot 0 has item and slot 1 is empty, process just that slot
    -- If both slots have items or other patterns, do full processing
    local quick_check_result = inventory.quick_check(inv)
    if quick_check_result == "process_single" then
        -- Process just the new item
        inventory.process_single_item(inv, 0)
        return
    end

    -- 2. Process each slot in each sack, working from max slot to min
    -- - Start with peripherals (highest slots), then fuel, then ore
    -- - Identify items in wrong sacks and move them to correct sacks
    inventory.process_sacks(inv)

    -- 3. For each unassigned item (in raw_contents):
    -- - If it's a trash item, move to trash sack (or drop if trash sack full)
    -- - If it's a fuel/peripheral, move to appropriate sack if space available
    -- - Otherwise, treat as ore and put in ore sack
    inventory.process_unassigned(inv)

    -- 4. If trash sack is full, empty it (drop all items)
    inventory.check_trash_sack(inv)
end

--[[
EXPLANATION OF INVENTORY SYSTEM:

This inventory system works with the following sequence of function calls:

1. First-time setup:
   - inventory.create(config) - Creates inventory structure with configured sack sizes
   - inventory.load_from_config(inv, config) - Loads item types and slot configurations

2. After mining a block or any inventory change:
   - inventory.update(inv) - Main update function that gets called

3. Update flow:
   - inventory.scan(inv) - Scan all turtle slots to update raw_contents
   - inventory.quick_check(inv) - Check if we have just one new item (optimization)
     - If [item, empty], call inventory.process_single_item(inv, 0)
     - This is a fast path for common case of just mining one block

4. For full processing:
   - inventory.process_sacks(inv) - Process each sack in reverse slot order
     - For peripherals_sack (slots 15-13 in default config):
       - Check if items are actually peripherals
       - If not, move to correct sack or mark as unassigned
     - Similarly for fuel_sack (slots 12-10) and ore_sack (slots 9-0)

   - inventory.process_unassigned(inv) - Process items not yet in a sack
     - For each item, check type with inventory.is_trash(), inventory.is_fuel(), etc.
     - Find appropriate slot with inventory.find_slot_in_sack()
     - Move item with inventory.move_item() or drop with inventory.drop_item()

   - inventory.check_trash_sack(inv) - If trash sack is full, empty it

5. When equipping items:
   - inventory.equip(inv, item_name) - Equips specified peripheral

The key to this system is that we maintain a logical division of the turtle's
physical inventory slots, filling each section from highest slot number to lowest:

With default config (ore=10, fuel=3, peripheral=3):
Slots 15-13: Peripherals (filled from 15 down)
Slots 12-10: Fuel (filled from 12 down)
Slots 9-0: Ore (filled from 9 down)

When the turtle mines a block:
1. The block appears in the lowest available slot (typically slot 0)
2. We identify its type and move it to the appropriate sack's highest available slot
3. If the item is trash, it goes to trash_sack and is dropped when that sack is full

This approach keeps the inventory organized and optimized for mining operations.
]] --

-- Quick check for new items in slots 0 and 1
-- Returns "process_single" if we have [item, empty]
-- Returns "process_full" otherwise
function inventory.quick_check(inv)
    -- TODO: Check if slot 0 has an item and slot 1 is empty
    -- If so, we just process that single item
    -- Otherwise, we do a full inventory process
    return "process_full"
end

-- Process a single new item in the given slot
function inventory.process_single_item(inv, slot)
    -- TODO: Process a single new item
    -- 1. Identify item type (trash, fuel, peripheral, ore)
    -- 2. Move to appropriate sack or drop if trash
end

-- Process all sacks to ensure items are in the correct places
function inventory.process_sacks(inv)
    -- TODO: Process all sacks
    -- 1. Start with peripherals sack (highest slots)
    -- 2. Then fuel sack
    -- 3. Then ore sack
    -- 4. Move items to correct sacks if they're in the wrong one
end

-- Process unassigned items in raw_contents
function inventory.process_unassigned(inv)
    -- TODO: Process unassigned items
    -- 1. For each item in raw_contents
    -- 2. Categorize as trash, fuel, peripheral, or ore
    -- 3. Move to appropriate sack or drop if trash
end

-- Check if trash sack is full and empty it if needed
function inventory.check_trash_sack(inv)
    -- TODO: Check if trash sack is full
    -- If full, drop ALL items in trash sack at once (not just one)
    -- This empties the entire trash sack in one go
end

-- Empty the entire trash sack (drop all items)
function inventory.empty_trash_sack(inv)
    -- TODO: Drop every item in the trash sack
    -- 1. IterateLoad item classification lists and slot configuration from .env
function inventory.load_from_config(inv, config)
    -- Load item classification lists
    inv.trash_types = config.dotenv.trash_types or {}
    inv.fuel_types = config.dotenv.fuel_types or {}
    inv.peripheral_types = config.dotenv.peripheral_types or {}

    -- Update sack sizes and slot ranges based on config
    local ore_slots = config.dotenv.ore_slots
    local fuel_slots = config.dotenv.fuel_slots
    local peripheral_slots = config.dotenv.peripheral_slots

    -- Calculate slot ranges for each sack (in reverse)
    local peripheral_start = 16 - 1 -- 0-based, so 15 is the max slot
    local peripheral_end = peripheral_start - peripheral_slots + 1

    local fuel_start = peripheral_end - 1
    local fuel_end = fuel_start - fuel_slots + 1

    local ore_start = fuel_end - 1
    local ore_end = ore_start - ore_slots + 1

    -- Update sack configurations
    inv.ore_sack.slots_max = ore_slots
    inv.ore_sack.start_slot = ore_start
    inv.ore_sack.end_slot = ore_end

    inv.fuel_sack.slots_max = fuel_slots
    inv.fuel_sack.start_slot = fuel_start
    inv.fuel_sack.end_slot = fuel_end

    inv.peripherals_sack.slots_max = peripheral_slots
    inv.peripherals_sack.start_slot = peripheral_start
    inv.peripherals_sack.end_slot = peripheral_end
end

-- Scan the turtle's inventory and update raw_contents
function inventory.scan(inv)
    -- TODO: Scan turtle inventory
    -- 1. Use turtle.getItemDetail for each slot
    -- 2. Update inv.raw_contents with current inventory
end

-- Check if an item is of a specific type
function inventory.is_item_type(inv, item_name, type_list)
    -- TODO: Check if item_name is in type_list
    -- Returns true if item is of the specified type
    return false
end

-- Check if an item is trash
function inventory.is_trash(inv, item_name)
    return inventory.is_item_type(inv, item_name, inv.trash_types)
end

-- Check if an item is fuel
function inventory.is_fuel(inv, item_name)
    return inventory.is_item_type(inv, item_name, inv.fuel_types)
end

-- Check if an item is peripheral
function inventory.is_peripheral(inv, item_name)
    return inventory.is_item_type(inv, item_name, inv.peripheral_types)
end

-- Find an available slot in a specific sack
function inventory.find_slot_in_sack(inv, sack)
    -- TODO: Find an available slot in the given sack
    -- Search from start_slot to end_slot
    -- Return nil if no slot is available
    return nil
end

-- Move an item from one slot to another
function inventory.move_item(from_slot, to_slot)
    -- TODO: Use turtle.select and turtle.transferTo
    -- to move an item from one slot to another
end

-- Drop an item from a specific slot
function inventory.drop_item(slot)
    -- TODO: Drop the item in the specified slot
end

-- Equip an item from the peripherals sack
function inventory.equip(inv, item_name)
    -- TODO: Find the item in peripherals_sack and equip it
    -- Update inv.equipped
end

-- Return the module
return inventory
