-- Mint Startup Script
-- This script makes the 'mint' command available from anywhere

-- Find the mint path
local function find_mint_path()
    -- Check current directory
    if fs.exists("mint.lua") then
        return shell.dir()
    end

    -- Check if we're in the mint directory
    if fs.exists("./mint.lua") then
        return "."
    end

    -- Check if mint is in parent directory
    if fs.exists("../mint.lua") then
        return ".."
    end

    -- Check absolute path
    if fs.exists("/mint/mint.lua") then
        return "/mint"
    end

    return nil
end

-- Install the mint command
local function install_mint_command()
    local mint_path = find_mint_path()

    if not mint_path then
        print("Mint installation not found")
        return false
    end

    -- Create a shell alias/command for mint
    shell.setAlias("mint", mint_path .. "/mint.lua")

    -- Check if we're already in /mint or have set up a global path
    if shell.dir() ~= mint_path and not fs.exists("/mint") then
        -- Create a global shortcut if possible
        if fs.exists("/") then
            fs.makeDir("/mint")
            for _, item in ipairs(fs.list(mint_path)) do
                fs.copy(mint_path .. "/" .. item, "/mint/" .. item)
            end
            print("Created global /mint installation")
            shell.setAlias("mint", "/mint/mint.lua")
        end
    end

    print("Mint command installed successfully")
    return true
end

-- Run initial setup
local success = install_mint_command()

-- Let the user know mint is ready
if success then
    print("Type 'mint help' for usage information")

    -- Auto-setup configs
    local mint = require("mint")
    if mint then
        mint.setup()
    end
end
