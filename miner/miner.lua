local Mint = require("mintlib.mint")
local API = require("miner.api")

-- Initialize Mint instance with module name
local mint = Mint.new("miner")

-- Load configurations with simplified API
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

print("Configuration loaded successfully")

-- Miner movement functions

function setlook(wishdir)
    assert(wishdir <= 3 and wishdir >= 0, "cannot set erroneous lookdir")

    local curdir = minerstate:read("lookdir")
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
            minerstate:write("lookdir", curdir)
        end
    end
end

function forcemove_h(blocks)
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
        local substep = minerstate:read("substep")
        minerstate:write("substep", (substep + 1) % 64)
    end
    return true
end

function forcemove_v(blocks, dir) -- 0 down 1 up
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
        local substep = minerstate:read("substep")
        minerstate:write("substep", (substep + 1) % 64)
    end
    return true
end

function step()
    -- We assume we start FACING the top left block on even (incl 0 steps) and the BOTTOM left on odd.
    -- Therefore our first move is always a dig forward:
    forcemove_h(1) -- step=x/1

    -- After this we set the up/down dir:
    local current_step = minerstate:read("step")
    local vdir = (current_step % 2 ~= 0) and 1 or 0

    -- We now set lookdir to face along RIGHT which depends on the tunnel direction. If tunnel direction is
    -- 1 (+Z) we are moving to -X to face right, else +X. +X is 00_2, -X is 10_2 so 2
    local zdir = tunnelstate:read("zdir")
    if zdir == 0 then
        setlook(0) -- + zdir -> -X
    else
        setlook(2) -- - zdir -> +X
    end

    for i = 1, 7 do
        forcemove_h(7)              -- forcemove along row
        forcemove_v(1, vdir)        -- move vdir
        local currlook = minerstate:read("lookdir")
        setlook((currlook + 2) % 4) -- swap look sign bit (2 becomes 0, 0 becomes 2)
    end

    -- Finally we forcemove 7 along the final row:
    forcemove_h(7)

    minerstate:write("step", current_step + 1) -- inc step

    -- now we set the final look to the tunnel direction. +Z is 01_2 = 1 -Z is 11_2 = 3
    if zdir == 0 then
        setlook(3)
    else
        setlook(1)
    end

    -- We are now ready to start step AGAIN.
end

-- Main execution
step()
step()

-- Close configs when done
mint:close_all()
