-- Movement module for the mining turtle
local movement = {}
local config = require("mint/config.lua")

-- Ensure turtle API is available
if not turtle and _G.turtle then
    turtle = _G.turtle
end

-- Set the turtle's facing direction
function movement.setlook(wishdir)
    assert(wishdir <= 3 and wishdir >= 0, "cannot set erroneous lookdir")

    local curdir = config.minerstate.lookdir
    if curdir ~= wishdir then
        -- Calculate shortest rotation direction
        local diff = wishdir - curdir

        -- Normalize to -2 to 2 range, then pick shortest path
        if diff > 2 then
            diff = diff - 4
        elseif diff < -2 then
            diff = diff + 4
        end

        local binding = (diff > 0) and turtle.turnRight or turtle.turnLeft
        local steps = math.abs(diff)

        for i = 1, steps do
            binding()
            curdir = (curdir + (diff > 0 and 1 or -1)) % 4
            config.minerstate.lookdir = curdir

            -- Write config to file immediately in case of crash
            config.save_config(".minerstate", config.minerstate)
        end
    end
end

-- Force horizontal movement, digging if necessary
function movement.forcemove_h(blocks)
    for i = 1, blocks do
        local ok = turtle.forward()
        if not ok then
            turtle.dig()
            ok = turtle.forward()
            if not ok then
                return false, "blocked after dig"
            end
        end

        -- Increment substep and wrap at 64
        config.minerstate.substep = (config.minerstate.substep + 1) % 64

        -- Save state after each block moved
        config.save_config(".minerstate", config.minerstate)
    end
    return true
end

-- Force vertical movement, digging if necessary
function movement.forcemove_v(blocks, dir) -- 0 down 1 up
    assert(dir == 0 or dir == 1, "dir must be 0 for down 1 for up")

    local movebind = (dir == 0) and turtle.down or turtle.up
    local digbind  = (dir == 0) and turtle.digDown or turtle.digUp

    for i = 1, blocks do
        local ok = movebind()
        if not ok then
            digbind()
            ok = movebind()
            if not ok then
                return false, "blocked after dig"
            end
        end

        -- Increment substep and wrap at 64
        config.minerstate.substep = (config.minerstate.substep + 1) % 64

        -- Save state after each block moved
        config.save_config(".minerstate", config.minerstate)
    end
    return true
end

return movement
