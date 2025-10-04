-- Mint - Main Wrapper Script
-- This script provides a simple interface for running mint modules in ComputerCraft

-- Utility functions for paths
local function joinPath(...)
    return table.concat({ ... }, "/"):gsub("//", "/")
end

-- Find the mint root directory
local function findMintRoot()
    local current_dir = shell.dir()

    -- Check if we're in the mint directory
    if fs.exists(joinPath(current_dir, "mintlib")) then
        return current_dir
    end

    -- Check if mint is a subdirectory
    if fs.exists(joinPath(current_dir, "mint", "mintlib")) then
        return joinPath(current_dir, "mint")
    end

    -- Check if mint is in the root
    if fs.exists("/mint/mintlib") then
        return "/mint"
    end

    -- Not found
    return nil
end

-- Discover available modules by scanning directories
local function discoverModules(mint_root)
    local modules = {}
    local system_dirs = {
        ["config_defaults"] = true,
        ["config_templates"] = true,
        ["configs"] = true,
        ["mintlib"] = true
    }

    -- List the root directories
    local items = fs.list(mint_root)
    for _, item in ipairs(items) do
        local path = joinPath(mint_root, item)
        -- Skip system directories and files
        if fs.isDir(path) and not system_dirs[item] and item:sub(1, 1) ~= "." then
            -- Check if this directory has a main.lua file
            if fs.exists(joinPath(path, "main.lua")) then
                table.insert(modules, item)
            end
        end
    end

    return modules
end

-- Ensure config directories exist
local function ensureConfigs(mint_root)
    local configs_dir = joinPath(mint_root, "configs")

    -- Create main configs directory if needed
    if not fs.exists(configs_dir) then
        fs.makeDir(configs_dir)
        print("Created configs directory")
    end

    -- Discover modules
    local modules = discoverModules(mint_root)

    -- Create config directories for each module
    for _, module in ipairs(modules) do
        local module_config_dir = joinPath(configs_dir, module)

        -- Create the module config directory if needed
        if not fs.exists(module_config_dir) then
            fs.makeDir(module_config_dir)
            print("Created config directory for " .. module)

            -- Check for default configs
            local defaults_dir = joinPath(mint_root, "config_defaults", module)
            if fs.exists(defaults_dir) then
                -- Copy default configs
                for _, file in ipairs(fs.list(defaults_dir)) do
                    local src_path = joinPath(defaults_dir, file)
                    local dest_path = joinPath(module_config_dir, file)

                    if not fs.exists(dest_path) and not fs.isDir(src_path) then
                        fs.copy(src_path, dest_path)
                        print("Copied default config: " .. file .. " for " .. module)
                    end
                end
            end
        end

        -- Check for template configs
        local template_path = joinPath(mint_root, "config_templates", "." .. module .. ".env.template")
        local env_path = joinPath(module_config_dir, "env.lua")

        if fs.exists(template_path) and not fs.exists(env_path) then
            print("Setting up " .. env_path .. " from template")

            -- Load the template
            local template_content
            local file = fs.open(template_path, "r")
            if file then
                local content = file.readAll()
                file.close()

                -- Execute the template content to get the table
                template_content = load("return " .. content)()

                -- Write new config file
                file = fs.open(env_path, "w")
                file.write("return {\n")
                for key, value_type in pairs(template_content) do
                    local default_value

                    -- Set sensible defaults based on type
                    if value_type == "string" then
                        default_value = '""'
                    elseif value_type == "number" then
                        default_value = "0"
                    elseif value_type == "boolean" then
                        default_value = "false"
                    else
                        default_value = "nil"
                    end

                    file.write("    " .. key .. " = " .. default_value .. ",\n")
                end
                file.write("}\n")
                file.close()
                print("Created config file: " .. env_path)
            end
        end
    end

    return true
end

-- Load a module
local function loadModule(mint_root, module_name)
    local module_path = joinPath(mint_root, module_name, "main")
    local old_package_path = package.path

    -- Temporarily modify package path to include the mint root
    package.path = joinPath(mint_root, "?.lua") .. ";" ..
        joinPath(mint_root, "?/init.lua") .. ";" ..
        package.path

    -- Try to require the module
    local success, module = pcall(function()
        return require(module_path)
    end)

    -- Restore package path
    package.path = old_package_path

    if success and module then
        return module
    else
        print("Error loading module '" .. module_name .. "': " .. (module or "unknown error"))
        return nil
    end
end

-- Main run function
local function run(...)
    local args = { ... }

    -- Find mint root
    local mint_root = findMintRoot()
    if not mint_root then
        print("Error: Could not find mint installation")
        return false
    end

    -- Switch to mint root directory
    local old_dir = shell.dir()
    shell.setDir(mint_root)

    -- No arguments, show help
    if #args < 1 then
        print("Usage: mint run <module> [arguments]")
        local modules = discoverModules(mint_root)
        print("Available modules: " .. table.concat(modules, ", "))
        shell.setDir(old_dir)
        return false
    end

    local command = args[1]

    if command == "run" then
        if #args < 2 then
            print("Usage: mint run <module> [arguments]")
            local modules = discoverModules(mint_root)
            print("Available modules: " .. table.concat(modules, ", "))
            shell.setDir(old_dir)
            return false
        end

        local module_name = args[2]
        local modules = discoverModules(mint_root)
        local module_found = false

        for _, m in ipairs(modules) do
            if m == module_name then
                module_found = true
                break
            end
        end

        if not module_found then
            print("Error: Module '" .. module_name .. "' not found")
            print("Available modules: " .. table.concat(modules, ", "))
            shell.setDir(old_dir)
            return false
        end

        -- Ensure configs
        ensureConfigs(mint_root)

        -- Load the module
        local module = loadModule(mint_root, module_name)
        if not module then
            shell.setDir(old_dir)
            return false
        end

        -- Get remaining arguments
        local module_args = {}
        for i = 3, #args do
            table.insert(module_args, args[i])
        end

        -- Run the module
        print("Running " .. module_name .. "...")
        local success, result
        if module.run then
            success, result = pcall(module.run, table.unpack(module_args))
        else
            print("Error: Module '" .. module_name .. "' doesn't have a 'run' function")
            success = false
        end

        -- Restore directory
        shell.setDir(old_dir)

        if not success then
            print("Error running " .. module_name .. ": " .. tostring(result))
            return false
        end

        return result
    elseif command == "setup" then
        -- Just setup configs
        local result = ensureConfigs(mint_root)
        print("Mint setup " .. (result and "completed successfully" or "failed"))
        shell.setDir(old_dir)
        return result
    elseif command == "list" then
        -- List available modules
        local modules = discoverModules(mint_root)
        print("Available modules: ")
        for _, module in ipairs(modules) do
            print("  - " .. module)
        end
        shell.setDir(old_dir)
        return true
    elseif command == "help" then
        print("Mint Wrapper Usage:")
        print("  mint run <module> [arguments] - Run a module")
        print("  mint setup                    - Setup config directories")
        print("  mint list                     - List available modules")
        print("  mint help                     - Show this help message")
        print("")

        local modules = discoverModules(mint_root)
        print("Available modules: " .. table.concat(modules, ", "))
        shell.setDir(old_dir)
        return true
    else
        print("Unknown command: " .. command)
        print("Use 'mint help' for usage information")
        shell.setDir(old_dir)
        return false
    end
end

-- If run directly from command line
if not package.loaded[(...)] then
    local args = { ... }
    local success = run(table.unpack(args))

    if not success then
        error("Mint exited with errors", 0)
    end
end

-- Return the API for programmatic usage
return {
    run = run,
    setup = function()
        local mint_root = findMintRoot()
        return mint_root and ensureConfigs(mint_root)
    end,
    list = function()
        local mint_root = findMintRoot()
        return mint_root and discoverModules(mint_root)
    end
}
