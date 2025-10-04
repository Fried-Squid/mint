-- Loader module to manage paths and requirements
local loader = {}

-- Set up the package path for proper module loading in ComputerCraft
-- This allows modules to be required using dot notation (e.g., require("mint.config"))
function loader.setup_paths()
    -- Ensure we include the current directory and standard Lua paths
    package.path = package.path .. ";/?;/?.lua"
    return true
end

-- Require a module with proper error handling
function loader.require(module_name)
    loader.setup_paths()

    local success, module = pcall(require, module_name)
    if success then
        return module
    else
        print("Failed to load module: " .. module_name)
        print("Error: " .. tostring(module))
        return nil
    end
end

-- Check if a module exists
function loader.module_exists(module_name)
    loader.setup_paths()

    local success = pcall(require, module_name)
    return success
end

-- Ensure turtle API is available
function loader.ensure_turtle()
    if not turtle and _G.turtle then
        _G.turtle = turtle
        return true
    elseif turtle then
        return true
    else
        print("Warning: Turtle API not available")
        return false
    end
end

-- Return the module
return loader
