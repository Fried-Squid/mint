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

-- Get a module's wanted configs
local function getModuleWants(mint_root, module_name)
    local wants = {}
    local wants_path = joinPath(mint_root, module_name, ".wants")

    if fs.exists(wants_path) then
        local file = fs.open(wants_path, "r")
        if file then
            local content = file.readAll()
            file.close()

            -- Try to load the wants file
            local fn, err = load("return " .. content)
            if fn then
                local success, result = pcall(fn)
                if success and type(result) == "table" then
                    wants = result
                else
                    print("Warning: Error loading .wants file for " .. module_name)
                end
            else
                print("Warning: Error parsing .wants file for " .. module_name)
            end
        end
    end

    return wants
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

    -- Return early if no modules found
    if #modules == 0 then
        print("Warning: No modules found in " .. mint_root)
        return true
    end

    -- Process each module's configurations
    for _, module in ipairs(modules) do
        local module_config_dir = joinPath(configs_dir, module)

        -- Create the module config directory if needed
        if not fs.exists(module_config_dir) then
            fs.makeDir(module_config_dir)
            print("Created config directory for " .. module)
        end

        -- Get list of configs this module wants
        local wanted_configs = getModuleWants(mint_root, module)

        -- Process module-specific configs
        local defaults_dir = joinPath(mint_root, "config_defaults")
        if fs.exists(defaults_dir) then
            -- Look for files starting with .module.
            for _, file in ipairs(fs.list(defaults_dir)) do
                if file:match("^%." .. module .. "%.") then
                    local src_path = joinPath(defaults_dir, file)
                    local dest_path = joinPath(module_config_dir, file:sub(2)) -- Remove leading dot

                    if fs.exists(src_path) and not fs.isDir(src_path) then
                        if not fs.exists(dest_path) then
                            fs.copy(src_path, dest_path)
                            print("Copied default config: " .. file .. " for " .. module)
                        end
                    end
                end
            end

            -- Process configs wanted by this module
            for _, wanted_config in ipairs(wanted_configs) do
                -- Only process if not already module-specific
                if not wanted_config:match("^%." .. module .. "%.") then
                    local src_path = joinPath(defaults_dir, wanted_config)
                    local dest_path = joinPath(module_config_dir, wanted_config:sub(2)) -- Remove leading dot

                    if fs.exists(src_path) and not fs.isDir(src_path) then
                        if not fs.exists(dest_path) then
                            fs.copy(src_path, dest_path)
                            print("Copied wanted config: " .. wanted_config .. " for " .. module)
                        end
                    else
                        print("Warning: Wanted config " .. wanted_config .. " not found in defaults")
                    end
                end
            end
        end

        -- Check for template configs
        local templates_dir = joinPath(mint_root, "config_templates")
        if fs.exists(templates_dir) then
            -- Look for any templates related to this module
            for _, template_name in ipairs(fs.list(templates_dir)) do
                if template_name:match("^%." .. module .. "%.(.+)%.template$") then
                    local config_type = template_name:match("^%." .. module .. "%.(.+)%.template$")
                    local template_path = joinPath(templates_dir, template_name)
                    local config_path = joinPath(module_config_dir, "." .. module .. "." .. config_type)

                    if fs.exists(template_path) and not fs.exists(config_path) then
                        print("Setting up " .. config_path .. " from template")

                        -- Load the template
                        local template_content = {}
                        local file = fs.open(template_path, "r")
                        if file then
                            local content = file.readAll()
                            file.close()

                            -- Safely execute the template content to get the table
                            local fn, err = load("return " .. content)
                            if fn then
                                local success, result = pcall(fn)
                                if success and result then
                                    template_content = result
                                else
                                    print("Error loading template " ..
                                        wanted_template .. ": " .. tostring(result or "unknown error"))
                                end
                            else
                                print("Error parsing template " ..
                                    wanted_template .. ": " .. tostring(err or "unknown error"))
                            end

                            -- Write new config file
                            file = fs.open(config_path, "w")
                            if file then
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
                                print("Created config file: " .. config_path)
                            end
                        end
                    end
                end

                -- Process wanted templates
                for _, wanted_config in ipairs(wanted_configs) do
                    -- Find matching template
                    local wanted_template = wanted_config .. ".template"
                    local template_path = joinPath(templates_dir, wanted_template)
                    local config_path = joinPath(module_config_dir, wanted_config:sub(2)) -- Remove leading dot

                    if fs.exists(template_path) and not fs.exists(config_path) then
                        print("Setting up " .. config_path .. " from wanted template " .. wanted_template)

                        -- Load the template
                        local template_content = {}
                        local file = fs.open(template_path, "r")
                        if file then
                            local content = file.readAll()
                            file.close()

                            -- Safely execute the template content to get the table
                            local fn, err = load("return " .. content)
                            if fn then
                                local success, result = pcall(fn)
                                if success and result then
                                    template_content = result
                                else
                                    print("Error loading template: " .. (result or "unknown error"))
                                end
                            else
                                print("Error parsing template: " .. (err or "unknown error"))
                            end

                            -- Write new config file
                            file = fs.open(config_path, "w")
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
                            print("Created wanted config file: " .. config_path)
                        else
                            print("Error: Could not open " .. config_path .. " for writing")
                        end
                    end
                end
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

    -- If main.lua doesn't exist or doesn't have a run function,
    -- try to load the module directly
    if not success or not module then
        success, module = pcall(function()
            return require(module_name)
        end)
    end

    -- Restore package path
    package.path = old_package_path

    if success and module then
        return module
    else
        print("Error loading module '" .. module_name .. "': " .. tostring(module or "unknown error"))
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

        -- If not found, check if there are any configs for this module
        -- This handles special modules like 'tunnel' that might not have code
        if not module_found and fs.exists(joinPath(mint_root, "config_defaults")) then
            for _, file in ipairs(fs.list(joinPath(mint_root, "config_defaults"))) do
                if file:match("^%." .. module_name .. "%.") then
                    module_found = true
                    break
                end
            end
        end

        if not module_found then
            print("Error: Module '" .. module_name .. "' not found")
            if #modules > 0 then
                print("Available modules: " .. table.concat(modules, ", "))
            else
                print("No modules found in " .. mint_root)
            end
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
        if #modules > 0 then
            print("Available modules: " .. table.concat(modules, ", "))
        else
            print("No modules found in " .. mint_root)
        end
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
