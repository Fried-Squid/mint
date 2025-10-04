-- Mint - Main Wrapper Script
-- This script provides a simple interface for running mint modules in ComputerCraft

-- 1. Module discovery
function discoverModules(mintRoot)
    local modules = {}
    local systemDirs = {
        ["config_defaults"] = true,
        ["config_templates"] = true,
        ["configs"] = true,
        ["mintlib"] = true
    }

    -- List the root directories
    local items = fs.list(mintRoot)
    for _, item in ipairs(items) do
        local path = fs.combine(mintRoot, item)
        -- Skip system directories and files
        if fs.isDir(path) and not systemDirs[item] and item:sub(1, 1) ~= "." then
            -- Check if this directory has a main.lua file
            if fs.exists(fs.combine(path, "main.lua")) then
                table.insert(modules, item)
            end
        end
    end

    return modules
end

function findWants(modulePath, mintRoot)
    local missing = {}
    local wantsPath = fs.combine(modulePath, ".wants")

    -- Check if .wants file exists
    if not fs.exists(wantsPath) then
        return missing
    end

    -- Load .wants file
    local wantsFile = fs.open(wantsPath, "r")
    if not wantsFile then
        return missing
    end

    local content = wantsFile.readAll()
    wantsFile.close()

    -- Parse the wants file
    local wants = {}
    local success, result = pcall(function()
        return load("return " .. content)()
    end)

    if success and type(result) == "table" then
        wants = result
    else
        print("Warning: Could not parse .wants file for " .. modulePath)
        return missing
    end

    -- Check for each wanted config
    for _, configName in ipairs(wants) do
        -- Remove leading dot if present
        local fileName = configName:match("^%.(.+)") or configName

        -- Check if it exists in configs
        local configsPath = fs.combine(mintRoot, "mint/configs", fs.getName(modulePath))
        local configPath = fs.combine(configsPath, fileName)

        if not fs.exists(configPath) then
            table.insert(missing, configName)
        end
    end

    return missing
end

function copyDefault(configName, moduleDir, mintRoot)
    -- Format: .module.config or just .config
    local defaultPath = fs.combine(mintRoot, "config_defaults", configName)

    -- Check if default exists
    if not fs.exists(defaultPath) then
        print("Warning: Default config " .. configName .. " not found")
        return false
    end

    -- Determine target directory
    local configsDir = fs.combine(mintRoot, "mint/configs", moduleDir)
    if not fs.exists(configsDir) then
        fs.makeDir(configsDir)
    end

    -- Strip leading dot for target filename
    local targetName = configName:match("^%.(.+)") or configName
    local targetPath = fs.combine(configsDir, targetName)

    -- Copy the file
    fs.copy(defaultPath, targetPath)
    print("Copied " .. configName .. " to " .. targetPath)

    return true
end

-- Main function to run modules
local function run(...)
    local args = { ... }

    if #args < 1 then
        print("Usage: mint run <module> [arguments]")
        return false
    end

    local command = args[1]

    -- Handle commands
    if command == "run" then
        if #args < 2 then
            print("Usage: mint run <module> [arguments]")
            return false
        end

        local moduleName = args[2]
        local moduleArgs = {}

        for i = 3, #args do
            table.insert(moduleArgs, args[i])
        end

        -- Find the mint root directory
        local currentDir = shell.dir()
        local mintRoot = nil

        -- Check if we're in the mint directory
        if fs.exists(fs.combine(currentDir, "mintlib")) then
            mintRoot = currentDir
            -- Check if mint is in a subdirectory
        elseif fs.exists(fs.combine(currentDir, "mint", "mintlib")) then
            mintRoot = fs.combine(currentDir, "mint")
            shell.setDir(mintRoot)
            -- Check if mint is in root
        elseif fs.exists("/mint/mintlib") then
            mintRoot = "/mint"
            shell.setDir(mintRoot)
        end

        if not mintRoot then
            print("Error: Could not find mint installation")
            return false
        end

        -- Get modules
        local modules = discoverModules(mintRoot)
        local moduleFound = false

        for _, m in ipairs(modules) do
            if m == moduleName then
                moduleFound = true
                break
            end
        end

        if not moduleFound then
            print("Error: Module '" .. moduleName .. "' not found")
            print("Available modules: " .. table.concat(modules, ", "))
            return false
        end

        -- Ensure configs directory exists
        local configPath = fs.combine(mintRoot, "mint/configs")
        if not fs.exists(configPath) then
            fs.makeDir(configPath)
        end

        -- Check for module config directory
        local moduleConfigDir = fs.combine(mintRoot, "mint/configs", moduleName)
        if not fs.exists(moduleConfigDir) then
            fs.makeDir(moduleConfigDir)
        end

        -- Check module wants
        local modulePath = fs.combine(mintRoot, moduleName)
        local missing = findWants(modulePath, mintRoot)

        -- Copy default configs for missing wants
        for _, configName in ipairs(missing) do
            copyDefault(configName, moduleName, mintRoot)
        end

        -- Load and run the module
        local modulePath = fs.combine(moduleName, "main")
        -- Temporarily modify package path to include mint root
        local oldPath = package.path
        package.path = fs.combine(mintRoot, "?.lua") .. ";" ..
            fs.combine(mintRoot, "?/init.lua") .. ";" ..
            package.path
        local success, module = pcall(require, modulePath)

        -- Restore package path
        package.path = oldPath

        if not success or not module then
            print("Error loading module: " .. tostring(module))
            return false
        end

        if type(module.run) ~= "function" then
            print("Error: Module doesn't have a 'run' function")
            return false
        end

        return module.run(table.unpack(moduleArgs))
    elseif command == "setup" then
        -- Find mint root
        local currentDir = shell.dir()
        local mintRoot = nil

        if fs.exists(fs.combine(currentDir, "mintlib")) then
            mintRoot = currentDir
        elseif fs.exists(fs.combine(currentDir, "mint", "mintlib")) then
            mintRoot = fs.combine(currentDir, "mint")
        elseif fs.exists("/mint/mintlib") then
            mintRoot = "/mint"
        end

        if not mintRoot then
            print("Error: Could not find mint installation")
            return false
        end

        -- Create configs directory if needed
        local configsDir = fs.combine(mintRoot, "mint/configs")
        if not fs.exists(configsDir) then
            fs.makeDir(configsDir)
            print("Created configs directory")
        end

        -- Process each module
        local modules = discoverModules(mintRoot)

        for _, module in ipairs(modules) do
            local modulePath = fs.combine(mintRoot, module)
            local moduleConfigDir = fs.combine(mintRoot, "mint/configs", module)

            -- Create module config directory if needed
            if not fs.exists(moduleConfigDir) then
                fs.makeDir(moduleConfigDir)
                print("Created config directory for " .. module)
            end

            -- Process module wants
            local missing = findWants(modulePath, mintRoot)

            for _, configName in ipairs(missing) do
                copyDefault(configName, module, mintRoot)
            end
        end

        print("Setup completed")
        return true
    elseif command == "help" then
        print("Mint Wrapper Usage:")
        print("  mint run <module> [arguments] - Run a module")
        print("  mint setup                    - Setup config directories")
        print("  mint help                     - Show this help message")
        return true
    else
        print("Unknown command: " .. command)
        print("Use 'mint help' for usage information")
        return false
    end
end

-- If this script is run directly
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
    discoverModules = discoverModules,
    findWants = findWants,
    copyDefault = copyDefault
}
