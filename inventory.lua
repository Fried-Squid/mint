-- Inventory module for the mining turtle

-- Ensure we have access to the turtle API
if not turtle and _G.turtle then
    turtle = _G.turtle
end
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

    -- Reserve 2 slots for trash, account for that in validation
    local trash_slots = 2
    local total_slots = ore_slots + fuel_slots + peripheral_slots + trash_slots
    assert(total_slots <= 16, "Total sack slots exceed turtle inventory capacity")

    -- Calculate slot ranges for each sack (in reverse)
    -- Assuming 16 slots total in turtle inventory (0-15)
    local peripheral_start = 16 - 1 -- 0-based, so 15 is the max slot
    local peripheral_end = peripheral_start - peripheral_slots + 1

    -- Add trash sack (2 slots) before peripherals
    local trash_start = peripheral_end - 1
    local trash_end = trash_start - trash_slots + 1

    local fuel_start = trash_end - 1
    local fuel_end = fuel_start - fuel_slots + 1

    local ore_start = fuel_end - 1
    local ore_end = ore_start - ore_slots + 1

    return {
        -- Original unfiltered inventory contents
        raw_contents = {},

        -- Specialized sacks with slot ranges
        ore_sack = inventory.create_sack(ore_slots, ore_start, ore_end),
        fuel_sack = inventory.create_sack(fuel_slots, fuel_start, fuel_end),
        trash_sack = inventory.create_sack(2, trash_start, trash_end), -- Real slots for trash before peripherals
        peripherals_sack = inventory.create_sack(peripheral_slots, peripheral_start, peripheral_end),

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

    -- 5. Check if fuel is needed and refuel if necessary
    -- Use the config fuel threshold if available
    local threshold = (config and config.dotenv and config.dotenv.fuel_threshold) or 1000
    inventory.check_fuel(inv, threshold)
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

   - inventory.check_trash_sack(inv) - If trash sack is full, calls inventory.empty_trash_sack()
     - This dumps ALL trash items at once, not just individual items

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
3. If the item is trash, it goes to trash_sack and when that sack becomes full,
   we drop ALL trash items at once using inventory.empty_trash_sack()

This approach keeps the inventory organized and optimized for mining operations.
]] --

-- Quick check for new items in slots 0 and 1
-- Returns "process_single" if we have [item, empty]
-- Returns "process_full" otherwise
function inventory.quick_check(inv)
    -- Check slots 0 and 1 (adjust for Lua's 1-based indexing)
    local slot0_item = turtle.getItemDetail(1)
    local slot1_item = turtle.getItemDetail(2)

    -- If slot 0 has an item and slot 1 is empty, we have a single new item
    if slot0_item and not slot1_item then
        return "process_single"
    end

    -- Otherwise, we need full processing
    return "process_full"
end

-- Process a single new item in the given slot
function inventory.process_single_item(inv, slot)
    -- Get details of the item
    local item = turtle.getItemDetail(slot + 1)
    if not item then
        return -- No item to process
    end

    -- Add to raw contents for tracking
    table.insert(inv.raw_contents, {
        name = item.name,
        qty = item.count,
        slot = slot
    })

    -- Check item type and handle accordingly
    if inventory.is_trash(inv, item.name) then
        -- If trash sack is full, empty it first
        if inv.trash_sack.used_slots >= 3 then
            inventory.empty_trash_sack(inv)
        end

        -- Add to trash sack (conceptual, not a real slot)
        table.insert(inv.trash_sack.contents, {
            name = item.name,
            qty = item.count,
            slot = -1 -- Virtual slot
        })
        inv.trash_sack.used_slots = inv.trash_sack.used_slots + 1

        -- Drop the item
        inventory.drop_item(slot)
    elseif inventory.is_peripheral(inv, item.name) then
        -- Find a slot in peripherals sack
        local target_slot = inventory.find_slot_in_sack(inv, inv.peripherals_sack)
        if target_slot then
            -- Move to peripherals sack
            if inventory.move_item(slot, target_slot) then
                -- Update sack contents
                table.insert(inv.peripherals_sack.contents, {
                    name = item.name,
                    qty = item.count,
                    slot = target_slot
                })
                inv.peripherals_sack.used_slots = inv.peripherals_sack.used_slots + 1
            end
        end
    elseif inventory.is_fuel(inv, item.name) then
        -- Find a slot in fuel sack
        local target_slot = inventory.find_slot_in_sack(inv, inv.fuel_sack)
        if target_slot then
            -- Move to fuel sack
            if inventory.move_item(slot, target_slot) then
                -- Update sack contents
                table.insert(inv.fuel_sack.contents, {
                    name = item.name,
                    qty = item.count,
                    slot = target_slot
                })
                inv.fuel_sack.used_slots = inv.fuel_sack.used_slots + 1
            end
        end
    else
        -- Treat as ore
        local target_slot = inventory.find_slot_in_sack(inv, inv.ore_sack)
        if target_slot then
            -- Move to ore sack
            if inventory.move_item(slot, target_slot) then
                -- Update sack contents
                table.insert(inv.ore_sack.contents, {
                    name = item.name,
                    qty = item.count,
                    slot = target_slot
                })
                inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1
            end
        end
    end
end

-- Process all sacks to ensure items are in the correct places
function inventory.process_sacks(inv)
    -- Scan inventory to get current state
    inventory.scan(inv)

    -- Track which slots we've already processed
    local processed_slots = {}

    -- Clear sack contents
    inv.peripherals_sack.contents = {}
    inv.peripherals_sack.used_slots = 0
    inv.fuel_sack.contents = {}
    inv.fuel_sack.used_slots = 0
    inv.ore_sack.contents = {}
    inv.ore_sack.used_slots = 0
    inv.trash_sack.contents = {}
    inv.trash_sack.used_slots = 0

    -- Process each slot in the inventory
    for _, item in ipairs(inv.raw_contents) do
        local slot = item.slot
        local name = item.name

        -- Check which sack this slot belongs to physically
        local in_peripheral_range = (slot >= inv.peripherals_sack.end_slot and slot <= inv.peripherals_sack.start_slot)
        local in_trash_range = (slot >= inv.trash_sack.end_slot and slot <= inv.trash_sack.start_slot)
        local in_fuel_range = (slot >= inv.fuel_sack.end_slot and slot <= inv.fuel_sack.start_slot)
        local in_ore_range = (slot >= inv.ore_sack.end_slot and slot <= inv.ore_sack.start_slot)

        -- Check which sack this item should be in logically
        local is_peripheral = inventory.is_peripheral(inv, name)
        local is_fuel = inventory.is_fuel(inv, name)
        local is_trash = inventory.is_trash(inv, name)

        -- Skip slots we've already processed
        if processed_slots[slot] then
            goto continue
        end

        -- Handle based on item type and current location
        if is_trash then
            if in_trash_range then
                -- Item is already in the right sack
                table.insert(inv.ore_sack.contents, {
                    name = name,
                    qty = item.qty,
                    slot = slot
                })
                inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1
                processed_slots[slot] = true
            else
                -- Item needs to be moved to trash sack or dropped
                local target_slot = inventory.find_slot_in_sack(inv, inv.trash_sack)
                if target_slot then
                    -- Move to trash sack
                    if inventory.move_item(slot, target_slot) then
                        table.insert(inv.trash_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.trash_sack.used_slots = inv.trash_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[target_slot] = true
                    end
                else
                    -- If trash sack is full, just drop it
                    inventory.drop_item(slot)
                    processed_slots[slot] = true
                end
            end
        elseif is_peripheral then
            if in_peripheral_range then
                -- Check if the item is already at the highest available position
                local highest_available = inventory.find_slot_in_sack(inv, inv.peripherals_sack)
                if highest_available and highest_available > slot then
                    -- Move to a higher position
                    if inventory.move_item(slot, highest_available) then
                        table.insert(inv.peripherals_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = highest_available
                        })
                        inv.peripherals_sack.used_slots = inv.peripherals_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[highest_available] = true
                    end
                else
                    -- Item is already at a good position
                    table.insert(inv.peripherals_sack.contents, {
                        name = name,
                        qty = item.qty,
                        slot = slot
                    })
                    inv.peripherals_sack.used_slots = inv.peripherals_sack.used_slots + 1
                    processed_slots[slot] = true
                end
            else
                -- Item needs to be moved to peripherals sack
                local target_slot = inventory.find_slot_in_sack(inv, inv.peripherals_sack)
                if target_slot then
                    if inventory.move_item(slot, target_slot) then
                        table.insert(inv.peripherals_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.peripherals_sack.used_slots = inv.peripherals_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[target_slot] = true
                    end
                end
            end
        elseif is_fuel then
            if in_fuel_range then
                -- Check if the item is already at the highest available position
                local highest_available = inventory.find_slot_in_sack(inv, inv.fuel_sack)
                if highest_available and highest_available > slot then
                    -- Move to a higher position
                    if inventory.move_item(slot, highest_available) then
                        table.insert(inv.fuel_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = highest_available
                        })
                        inv.fuel_sack.used_slots = inv.fuel_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[highest_available] = true
                    end
                else
                    -- Item is already at a good position
                    table.insert(inv.fuel_sack.contents, {
                        name = name,
                        qty = item.qty,
                        slot = slot
                    })
                    inv.fuel_sack.used_slots = inv.fuel_sack.used_slots + 1
                    processed_slots[slot] = true
                end
            else
                -- Item needs to be moved to fuel sack
                local target_slot = inventory.find_slot_in_sack(inv, inv.fuel_sack)
                if target_slot then
                    if inventory.move_item(slot, target_slot) then
                        table.insert(inv.fuel_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.fuel_sack.used_slots = inv.fuel_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[target_slot] = true
                    end
                end
            end
        else
            -- Treat as ore
            if in_ore_range then
                -- Check if the item is already at the highest available position
                local highest_available = inventory.find_slot_in_sack(inv, inv.ore_sack)
                if highest_available and highest_available > slot then
                    -- Move to a higher position
                    if inventory.move_item(slot, highest_available) then
                        table.insert(inv.ore_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = highest_available
                        })
                        inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[highest_available] = true
                    end
                else
                    -- Item is already at a good position
                    table.insert(inv.ore_sack.contents, {
                        name = name,
                        qty = item.qty,
                        slot = slot
                    })
                    inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1
                    processed_slots[slot] = true
                end
            else
                -- Item needs to be moved to ore sack
                local target_slot = inventory.find_slot_in_sack(inv, inv.ore_sack)
                if target_slot then
                    if inventory.move_item(slot, target_slot) then
                        table.insert(inv.ore_sack.contents, {
                            name = name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1
                        processed_slots[slot] = true
                        processed_slots[target_slot] = true
                    end
                end
            end
        end
        ::continue::
    end
end

-- Process unassigned items in raw_contents
function inventory.process_unassigned(inv)
    -- Track slots that are now part of a sack
    -- Track which slots we've already processed
    local assigned_slots = {}

    -- Mark all slots in sacks as assigned
    for _, item in ipairs(inv.peripherals_sack.contents) do
        assigned_slots[item.slot] = true
    end

    for _, item in ipairs(inv.trash_sack.contents) do
        assigned_slots[item.slot] = true
    end

    for _, item in ipairs(inv.fuel_sack.contents) do
        assigned_slots[item.slot] = true
    end

    for _, item in ipairs(inv.ore_sack.contents) do
        assigned_slots[item.slot] = true
    end

    -- Process items not yet in a sack
    for _, item in ipairs(inv.raw_contents) do
        if not assigned_slots[item.slot] then
            -- Item is unassigned, categorize and handle
            if inventory.is_trash(inv, item.name) then
                -- Add to trash sack for later processing
                table.insert(inv.trash_sack.contents, {
                    name = item.name,
                    qty = item.qty,
                    slot = item.slot
                })
                inv.trash_sack.used_slots = inv.trash_sack.used_slots + 1

                -- Mark as assigned
                assigned_slots[item.slot] = true
                if target_slot then
                    assigned_slots[target_slot] = true
                end
            elseif inventory.is_peripheral(inv, item.name) then
                local target_slot = inventory.find_slot_in_sack(inv, inv.peripherals_sack)
                if target_slot then
                    if inventory.move_item(item.slot, target_slot) then
                        table.insert(inv.peripherals_sack.contents, {
                            name = item.name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.peripherals_sack.used_slots = inv.peripherals_sack.used_slots + 1

                        -- Mark as assigned
                        assigned_slots[item.slot] = true
                        if target_slot then
                            assigned_slots[target_slot] = true
                        end
                    end
                end
            elseif inventory.is_fuel(inv, item.name) then
                local target_slot = inventory.find_slot_in_sack(inv, inv.fuel_sack)
                if target_slot then
                    if inventory.move_item(item.slot, target_slot) then
                        table.insert(inv.fuel_sack.contents, {
                            name = item.name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.fuel_sack.used_slots = inv.fuel_sack.used_slots + 1

                        -- Mark as assigned
                        assigned_slots[item.slot] = true
                    end
                end
            else
                -- Treat as ore
                local target_slot = inventory.find_slot_in_sack(inv, inv.ore_sack)
                if target_slot then
                    if inventory.move_item(item.slot, target_slot) then
                        table.insert(inv.ore_sack.contents, {
                            name = item.name,
                            qty = item.qty,
                            slot = target_slot
                        })
                        inv.ore_sack.used_slots = inv.ore_sack.used_slots + 1

                        -- Mark as assigned
                        assigned_slots[item.slot] = true
                    end
                end
            end
        end
    end
end

-- Check if trash sack is full and empty it if needed
function inventory.check_trash_sack(inv)
    -- Check if trash sack is at or near capacity
    if inv.trash_sack.used_slots >= 3 then
        -- Empty the entire trash sack
        inventory.empty_trash_sack(inv)
    end
end

-- Empty the entire trash sack (drop all items)
function inventory.empty_trash_sack(inv)
    -- Drop every item in the trash sack
    for _, item in ipairs(inv.trash_sack.contents) do
        -- Drop the item from its slot
        inventory.drop_item(item.slot)
    end

    -- Clear the trash sack contents
    inv.trash_sack.contents = {}

    -- Reset used slots counter
    inv.trash_sack.used_slots = 0

    print("Trash sack emptied")
end

-- Check fuel level and refuel if needed
function inventory.check_fuel(inv, threshold)
    -- Get current fuel level
    local fuel_level = turtle.getFuelLevel()

    -- If fuel is unlimited, no need to refuel
    if fuel_level == "unlimited" then
        return
    end

    -- Use provided threshold or config threshold or default 1000
    local fuel_threshold = threshold or (config and config.dotenv.fuel_threshold) or 1000

    -- Check if we need to refuel (below threshold)
    if fuel_level < fuel_threshold then
        return inventory.refuel(inv)
    end

    return false
end

-- Refuel the turtle from items in the fuel sack
function inventory.refuel(inv)
    local original_slot = turtle.getSelectedSlot()
    local refueled = false

    -- Try to refuel from fuel sack
    for _, item in ipairs(inv.fuel_sack.contents) do
        -- Skip buckets (we don't want to consume these)
        if not string.find(item.name, "bucket") then
            -- Select the fuel item
            turtle.select(item.slot + 1)

            -- Try to refuel with it
            if turtle.refuel() then
                print("Refueled with " .. item.name)
                refueled = true
            end
        end
    end

    -- Return to original slot
    turtle.select(original_slot)

    return refueled
end

-- Load item classification lists and slot configuration from .env
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

    -- Add trash sack (2 slots) before peripherals
    local trash_slots = 2
    local trash_start = peripheral_end - 1
    local trash_end = trash_start - trash_slots + 1

    local fuel_start = trash_end - 1
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

    inv.trash_sack.slots_max = 2
    inv.trash_sack.start_slot = trash_start
    inv.trash_sack.end_slot = trash_end

    inv.peripherals_sack.slots_max = peripheral_slots
    inv.peripherals_sack.start_slot = peripheral_start
    inv.peripherals_sack.end_slot = peripheral_end
end

-- Scan the turtle's inventory and update raw_contents
function inventory.scan(inv)
    -- Clear current raw_contents
    inv.raw_contents = {}

    -- Scan all 16 slots (0-15) of the turtle's inventory
    for slot = 0, 15 do
        local item = turtle.getItemDetail(slot + 1) -- +1 because Lua is 1-indexed but CC slots are 0-indexed
        if item then
            -- Add to raw_contents with slot information
            table.insert(inv.raw_contents, {
                name = item.name,
                qty = item.count,
                slot = slot
            })
        end
    end

    return inv.raw_contents
end

-- Check if an item is of a specific type
function inventory.is_item_type(inv, item_name, type_list)
    -- Check if item_name is in the type_list
    for _, type_name in ipairs(type_list) do
        if item_name == type_name then
            return true
        end
    end
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
    -- If sack is already full, return nil
    if sack.used_slots >= sack.slots_max then
        return nil
    end

    -- Track which slots are already used in this sack and
    -- which physical slots already have items
    local used_slots = {}
    local occupied_slots = {}

    -- Mark slots that are already being used in this sack
    for _, item in ipairs(sack.contents) do
        used_slots[item.slot] = true
    end

    -- Check which slots are physically occupied
    for slot = sack.start_slot, sack.end_slot, -1 do
        -- Make sure slot is valid (0-15)
        if slot >= 0 and slot <= 15 then
            local detail = turtle.getItemDetail(slot + 1)
            if detail then
                occupied_slots[slot] = true
            end
        end
    end

    -- Search from start_slot (highest) down to end_slot (lowest)
    for slot = sack.start_slot, sack.end_slot, -1 do
        -- Check if this slot is available (not used and not occupied)
        if not used_slots[slot] and not occupied_slots[slot] then
            return slot
        end
    end

    -- No available slots found
    return nil
end

-- Move an item from one slot to another
function inventory.move_item(from_slot, to_slot)
    -- Select the source slot (+1 for Lua indexing)
    turtle.select(from_slot + 1)

    -- Move the entire stack to the destination slot (+1 for Lua indexing)
    return turtle.transferTo(to_slot + 1)
end

-- Drop an item from a specific slot
function inventory.drop_item(slot)
    -- Select the slot to drop from (+1 for Lua indexing)
    turtle.select(slot + 1)

    -- Drop the entire stack
    return turtle.drop()
end

-- Equip an item from the peripherals sack
function inventory.equip(inv, item_name)
    -- Find the item in peripherals_sack
    for _, item in ipairs(inv.peripherals_sack.contents) do
        if item.name == item_name then
            -- Select the item
            turtle.select(item.slot + 1)

            -- Try to equip on right side first
            local success = turtle.equipRight()

            -- Update equipped status if successful
            if success then
                inv.equipped = item_name
                return true
            end

            return false
        end
    end

    -- Item not found in peripherals sack
    return false
end

-- Equip the diamond pickaxe this does not work
-- TODO: FIX THIS
-- Calling an equip function does not force an Inventory rescan (
-- should probably lazy force a rescan of the sack / use a swap pointer )
-- meaning equipping item1 stops item2 from being equipped until update()
-- is called
function inventory.equip_pickaxe(inv)
    -- Look for pickaxe in peripherals sack
    for _, item in ipairs(inv.peripherals_sack.contents) do
        if string.find(item.name, "pickaxe") then
            -- Select the item
            turtle.select(item.slot + 1)

            -- Equip on right side only
            local success = turtle.equipRight()

            -- Update equipped status if successful
            if success then
                print("Equipped diamond pickaxe")
                inv.equipped = "pickaxe"
                return true
            end

            return false
        end
    end

    print("No pickaxe found in peripherals sack")
    return false
end

-- Equip the end automata core this does work
function inventory.equip_automata_core(inv)
    -- Look for end automata core in peripherals sack
    for _, item in ipairs(inv.peripherals_sack.contents) do
        if string.find(item.name, "end_automata_core") then
            -- Select the item
            turtle.select(item.slot + 1)

            -- Equip on right side only
            local success = turtle.equipRight()

            -- Update equipped status if successful
            if success then
                print("Equipped end automata core")
                inv.equipped = "core"

                -- Try to get the peripheral
                local attempts = 0
                while not peripheral.find("endAutomata") and attempts < 5 do
                    os.sleep(0.5)
                    attempts = attempts + 1
                end

                return true
            end

            return false
        end
    end

    print("No end automata core found in peripherals sack")
    return false
end

-- Check if the ore sack is full
function inventory.is_ore_sack_full(inv)
    return inv.ore_sack.used_slots >= inv.ore_sack.slots_max
end

-- Handle teleportation when needed (ore sack full or low fuel)
function inventory.handle_teleport(inv, force)
    -- Update inventory first
    inventory.update(inv)

    -- Check conditions for teleporting
    local fuel_level = turtle.getFuelLevel()
    local ore_full = inventory.is_ore_sack_full(inv)

    if force or ore_full or (fuel_level ~= "unlimited" and fuel_level < 5000) then
        -- Equip the automata core
        if not inventory.equip_automata_core(inv) then
            print("Failed to equip automata core, cannot teleport")
            return false
        end

        -- Get the end automata peripheral
        local core = peripheral.find("endAutomata")
        if not core then
            print("Failed to find endAutomata peripheral")
            inventory.equip_pickaxe(inv)
            return false
        end

        -- Save current position as "latest"
        print("Saving current position as 'latest'")
        core.savePoint("latest")

        -- Teleport to home if it exists
        print("Attempting to teleport home")
        if not core.warpToPoint("home") then
            print("Failed to teleport to home, home not set")
            inventory.equip_pickaxe(inv)
            return false
        end

        print("Successfully teleported to home")
        return true
    end

    return false
end

-- Return to the latest position after restocking
function inventory.return_from_home(inv)
    -- Equip the automata core
    if not inventory.equip_automata_core(inv) then
        print("Failed to equip automata core, cannot teleport back")
        return false
    end

    -- Get the end automata peripheral
    local core = peripheral.find("endAutomata")
    if not core then
        print("Failed to find endAutomata peripheral")
        inventory.equip_pickaxe(inv)
        return false
    end

    -- Teleport to latest position
    print("Teleporting back to mining location")
    local success = core.warpToPoint("latest")

    -- Re-equip the pickaxe
    inventory.equip_pickaxe(inv)

    return success
end

-- Unload a stack to an adjacent inventory on the specified side
-- side can be "front", "back", "left", "right", "up", or "down"
-- Returns true if successful, false otherwise
function inventory.unload_to_inventory(inv, slot, side, count)
    -- Validate parameters
    if not slot or slot < 0 or slot > 15 then
        print("Invalid slot: " .. tostring(slot))
        return false, "Invalid slot"
    end

    -- Validate side
    if not side then
        side = "front" -- Default to front
    end

    -- Map side to corresponding turtle function
    local drop_funcs = {
        front = turtle.drop,
        up = turtle.dropUp,
        down = turtle.dropDown,
    }

    -- Handle left/right/back by turning first
    local original_dir = nil
    if side == "left" then
        original_dir = inv.equipped and inv.equipped.lookdir
        turtle.turnLeft()
        drop_funcs[side] = turtle.drop
    elseif side == "right" then
        original_dir = inv.equipped and inv.equipped.lookdir
        turtle.turnRight()
        drop_funcs[side] = turtle.drop
    elseif side == "back" then
        original_dir = inv.equipped and inv.equipped.lookdir
        turtle.turnRight()
        turtle.turnRight()
        drop_funcs[side] = turtle.drop
    end

    local drop_func = drop_funcs[side]
    if not drop_func then
        return false, "Invalid side: " .. side
    end

    -- Select the slot
    turtle.select(slot + 1)

    -- Get item details before dropping
    local item = turtle.getItemDetail(slot + 1)
    if not item then
        -- No item in this slot
        return false, "No item in slot " .. (slot + 1)
    end

    -- Try to drop the item
    local success
    if count then
        -- Drop specified count
        success = drop_func(count)
    else
        -- Drop entire stack
        success = drop_func()
    end

    -- Restore original direction if needed
    if original_dir then
        -- Turn back to original direction
        if side == "left" then
            turtle.turnRight()
        elseif side == "right" then
            turtle.turnLeft()
        elseif side == "back" then
            turtle.turnRight()
            turtle.turnRight()
        end
    end

    return success
end

-- Get fuel level as a percentage of maximum
function inventory.get_fuel_percentage(inv)
    local fuel_level = turtle.getFuelLevel()
    local fuel_limit = turtle.getFuelLimit()

    -- Handle unlimited fuel
    if fuel_level == "unlimited" then
        return 100
    end

    -- Calculate percentage
    return math.floor((fuel_level / fuel_limit) * 100)
end

-- Unload an entire sack to an adjacent inventory
-- side can be "front", "back", "left", "right", "up", or "down"
-- Returns number of slots successfully unloaded
function inventory.unload_sack_to_inventory(inv, sack_name, side)
    -- Validate parameters
    if not sack_name then
        return 0, "No sack specified"
    end

    -- Get the specified sack
    local sack
    if sack_name == "ore" then
        sack = inv.ore_sack
    elseif sack_name == "fuel" then
        sack = inv.fuel_sack
    elseif sack_name == "peripheral" or sack_name == "peripherals" then
        sack = inv.peripherals_sack
    elseif sack_name == "trash" then
        sack = inv.trash_sack
    else
        return 0, "Invalid sack name: " .. sack_name
    end

    if not sack or not sack.contents then
        return 0, "Sack not found or empty"
    end

    -- Keep track of how many slots we unloaded
    local unloaded_count = 0

    -- Remember original selected slot
    local original_slot = turtle.getSelectedSlot()

    -- Unload each item in the sack
    for _, item in ipairs(sack.contents) do
        local success = inventory.unload_to_inventory(inv, item.slot, side)
        if success then
            unloaded_count = unloaded_count + 1
        end
    end

    -- Restore original selected slot
    turtle.select(original_slot)

    -- If we unloaded items, we need to update our inventory
    if unloaded_count > 0 then
        inventory.scan(inv)
        sack.contents = {}
        sack.used_slots = 0
    end

    return unloaded_count
end

-- Return the module
return inventory
