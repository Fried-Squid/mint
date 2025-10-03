-- Mint Package Manager
-- A package manager for the Mint framework
-- Usage: mint-package.lua <command> <package> [options]

local args = { ... }

-- Load HTTP module for non-ComputerCraft environments
if not http then
    local success, httpModule = pcall(require, "socket.http")
    if success then
        -- Create ComputerCraft-like HTTP interface
        http = {
            get = function(url, headers, binary, timeout)
                local response, status = httpModule.request(url)
                if response and status == 200 then
                    return {
                        readAll = function() return response end,
                        getResponseCode = function() return status end,
                        close = function() end
                    }
                end
                return nil
            end
        }
    else
        -- Fallback for environments without socket.http
        print("Warning: HTTP functionality not available")
        print("This program requires ComputerCraft or lua-socket")
        return
    end
end

-- Load filesystem module for non-ComputerCraft environments
if not fs then
    fs = {
        exists = function(path)
            local file = io.open(path, "r")
            if file then
                file:close()
                return true
            end
            return false
        end,
        makeDir = function(path) os.execute("mkdir -p " .. path) end,
        open = function(path, mode) return io.open(path, mode) end,
        delete = function(path) os.remove(path) end,
        list = function(path)
            local items = {}
            local handle = io.popen("ls " .. path .. " 2>/dev/null")
            if handle then
                for line in handle:lines() do
                    table.insert(items, line)
                end
                handle:close()
            end
            return items
        end,
        combine = function(path1, path2) return path1 .. "/" .. path2 end,
        getDir = function(path) return path:match("(.+)/[^/]*$") or "" end,
        isDir = function(path)
            local handle = io.popen("test -d " .. path .. " && echo yes")
            if handle then
                local result = handle:read("*a")
                handle:close()
                return result:match("yes") ~= nil
            end
            return false
        end,
        getSize = function(path)
            local file = io.open(path, "r")
            if file then
                local size = file:seek("end")
                file:close()
                return size
            end
            return 0
        end,
        move = function(src, dst) os.rename(src, dst) end,
        copy = function(src, dst)
            local srcFile = io.open(src, "rb")
            if srcFile then
                local content = srcFile:read("*a")
                srcFile:close()
                local dstFile = io.open(dst, "wb")
                if dstFile then
                    dstFile:write(content)
                    dstFile:close()
                    return true
                end
            end
            return false
        end
    }
end

-- Load textutils for non-ComputerCraft environments
if not textutils then
    textutils = {
        serialize = function(data)
            if type(data) == "table" then
                local result = "{"
                local first = true
                for k, v in pairs(data) do
                    if not first then result = result .. "," end
                    first = false
                    result = result .. "[" .. textutils.serialize(k) .. "]=" .. textutils.serialize(v)
                end
                return result .. "}"
            elseif type(data) == "string" then
                return '"' .. data:gsub('"', '\\"') .. '"'
            else
                return tostring(data)
            end
        end,
        unserialize = function(str)
            local func = load("return " .. str)
            if func then
                return func()
            end
            return nil
        end,
        serialiseJSON = function(obj)
            return textutils.serialize(obj)
        end,
        unserialiseJSON = function(json)
            return textutils.unserialize(json)
        end
    }
end

-- Load shell for non-ComputerCraft environments
if not shell then
    shell = {
        dir = function() return "." end
    }
end

-- Load os.date if not available
if not os.date then
    os.date = function() return "unknown" end
end

-- Configuration - default values that can be overridden by .mintlinker file
local GITHUB_API = "https://api.github.com"
local GITHUB_RAW = "https://raw.githubusercontent.com"
local PACKAGE_REPO = "Fried-Squid/mint" -- Default repository
local DEFAULT_BRANCH = "main"           -- Default branch
local PACKAGE_MANIFEST = "packages.json"

-- Load repository info from .mintlinker if available
local function loadRepoInfo()
    if fs.exists(".mintlinker") then
        local file = fs.open(".mintlinker", "r")
        if file then
            local content = file.readAll()
            file.close()

            local config = textutils.unserialiseJSON and textutils.unserialiseJSON(content) or
                textutils.unserialize(content)
            if config and config.repository then
                return config.repository.name or PACKAGE_REPO,
                    config.repository.default_branch or DEFAULT_BRANCH,
                    config.package_manifest or PACKAGE_MANIFEST
            end
        end
    end
    return PACKAGE_REPO, DEFAULT_BRANCH, PACKAGE_MANIFEST
end

PACKAGE_REPO, DEFAULT_BRANCH, PACKAGE_MANIFEST = loadRepoInfo()

-- GitHub URL construction helper
local function getGitHubRawUrl(repo, branch, path)
    -- Try modern URL format first
    local urls = {
        string.format("%s/%s/%s/%s", GITHUB_RAW, repo, branch, path),
        string.format("%s/%s/refs/heads/%s/%s", GITHUB_RAW, repo, branch, path)
    }
    return urls
end

-- Directory structure
-- Directory structure - can be overridden by .mintlinker file
local function getDirectoryStructure()
    if fs.exists(".mintlinker") then
        local file = fs.open(".mintlinker", "r")
        if file then
            local content = file.readAll()
            file.close()

            local config = textutils.unserialiseJSON and textutils.unserialiseJSON(content) or
                textutils.unserialize(content)
            if config and config.directories then
                return config.directories.root or "mint",
                    config.directories.packages or ".mint-package",
                    config.directories.cache or ".cache/mint-package",
                    config.directories.configs or ".config/configs",
                    config.directories.templates or ".config/templates"
            end
        end
    end

    -- Default structure
    return "mint", ".mint-package", ".cache/mint-package", ".config/configs", ".config/templates"
end

local MINT_ROOT, PACKAGE_DIR, CACHE_DIR, CONFIG_DIR, TEMPLATE_DIR = getDirectoryStructure()

-- Utility functions
local function printUsage()
    print("Mint Package Manager")
    print()
    print("Usage:")
    print("  mint-package.lua install <package>")
    print("  mint-package.lua update <package>")
    print("  mint-package.lua remove <package>")
    print("  mint-package.lua list")
    print("  mint-package.lua search <query>")
    print("  mint-package.lua info <package>")
    print()
    print("Examples:")
    print("  mint-package.lua install miner")
    print("  mint-package.lua update all")
    print("  mint-package.lua remove courier")
    print()
    print("Commands:")
    print("  install - Install a package")
    print("  update  - Update an installed package")
    print("  remove  - Remove an installed package")
    print("  list    - List installed packages")
    print("  search  - Search available packages")
    print("  info    - Show package information")
end

local function log(message, level)
    level = level or "INFO"
    local timestamp = os.date("%H:%M:%S")
    print(string.format("[%s] %s: %s", timestamp, level, message))
end

local function makeRequest(url, timeout)
    timeout = timeout or 30
    log("GET " .. url)

    local response
    if http and http.get then
        -- ComputerCraft HTTP
        response = http.get(url, {}, false, timeout)
    elseif http and http.request then
        -- Alternative HTTP implementation
        response = http.request(url)
    end

    if not response then
        log("Failed to connect to: " .. url, "ERROR")
        return nil
    end

    local content
    local status = 200

    if type(response) == "table" and response.readAll then
        -- ComputerCraft-style response
        content = response.readAll()
        if response.getResponseCode then
            status = response.getResponseCode()
        end
        if response.close then
            response.close()
        end
    elseif type(response) == "string" then
        -- Direct string response
        content = response
    else
        log("Unknown response type: " .. type(response), "ERROR")
        return nil
    end

    if status ~= 200 then
        log("HTTP " .. status .. " for: " .. url, "ERROR")
        return nil
    end

    return content
end

local function parseJSON(jsonString)
    -- Simple JSON parser for basic GitHub API responses
    if not jsonString then return nil end

    -- Handle arrays
    if jsonString:match("^%s*%[") then
        local items = {}
        local content = jsonString:match("%[(.*)%]")
        if not content then return items end

        local depth = 0
        local current = ""
        local inString = false
        local escaped = false

        for i = 1, #content do
            local char = content:sub(i, i)

            if escaped then
                current = current .. char
                escaped = false
            elseif char == "\\" and inString then
                current = current .. char
                escaped = true
            elseif char == '"' then
                inString = not inString
                current = current .. char
            elseif not inString then
                if char == "{" then
                    depth = depth + 1
                    current = current .. char
                elseif char == "}" then
                    depth = depth - 1
                    current = current .. char
                    if depth == 0 then
                        local item = parseJSON("{" .. current .. "}")
                        if item then table.insert(items, item) end
                        current = ""
                    end
                elseif depth > 0 then
                    current = current .. char
                end
            else
                current = current .. char
            end
        end

        return items
    end

    -- Handle objects
    if jsonString:match("^%s*{") then
        local obj = {}

        -- Extract key-value pairs
        for key, value in jsonString:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
            -- Clean up value
            value = value:gsub("^%s+", ""):gsub("%s+$", "")

            if value:match('^".*"$') then
                -- String value
                obj[key] = value:sub(2, -2):gsub('\\"', '"')
            elseif value == "true" then
                obj[key] = true
            elseif value == "false" then
                obj[key] = false
            elseif value == "null" then
                obj[key] = nil
            elseif tonumber(value) then
                obj[key] = tonumber(value)
            else
                obj[key] = value
            end
        end

        return obj
    end

    return nil
end

local function ensureDirectory(path)
    if not fs.exists(path) then
        fs.makeDir(path)
        log("Created directory: " .. path)
    end
end

local function downloadFile(url, localPath)
    local content = makeRequest(url)
    if not content then
        return false
    end

    -- Ensure parent directory exists
    local parentDir = fs.getDir(localPath)
    if parentDir ~= "" then
        ensureDirectory(parentDir)
    end

    local file = fs.open(localPath, "w")
    if file then
        if file.write then
            -- ComputerCraft-style file handle
            file.write(content)
        else
            -- Standard Lua file handle
            file:write(content)
        end
        if file.close then
            file.close()
        else
            file:close()
        end
        log("Downloaded: " .. localPath)
        return true
    else
        log("Failed to write: " .. localPath, "ERROR")
        return false
    end
end

local function savePackageInfo(packageName, info)
    ensureDirectory(CACHE_DIR)
    local infoPath = fs.combine(CACHE_DIR, packageName .. ".json")

    local file = fs.open(infoPath, "w")
    if file then
        -- Use serialiseJSON instead of serialize for compatibility
        local serialized = textutils.serialiseJSON and textutils.serialiseJSON(info) or textutils.serialize(info)
        file.write(serialized)
        file.close()
        return true
    end
    return false
end

local function loadPackageInfo(packageName)
    local infoPath = fs.combine(CACHE_DIR, packageName .. ".json")
    if not fs.exists(infoPath) then
        return nil
    end

    local file = fs.open(infoPath, "r")
    if file then
        local content = file.readAll()
        file.close()
        -- Use unserialiseJSON instead of unserialize for compatibility
        return textutils.unserialiseJSON and textutils.unserialiseJSON(content) or textutils.unserialize(content)
    end
    return nil
end

local function getPackageManifest()
    -- First try to read the manifest locally
    if fs.exists(PACKAGE_MANIFEST) then
        log("Using local package manifest")
        local file = fs.open(PACKAGE_MANIFEST, "r")
        if file then
            local content = file.readAll()
            file.close()
            return parseJSON(content)
        end
    end

    -- Try from GitHub if local file doesn't exist or can't be parsed
    local urls = getGitHubRawUrl(PACKAGE_REPO, DEFAULT_BRANCH, PACKAGE_MANIFEST)

    -- Try each URL format
    local content
    for _, url in ipairs(urls) do
        content = makeRequest(url)
        if content then
            break
        end
    end

    if not content then
        log("Failed to download package manifest", "ERROR")
        return nil
    end

    return parseJSON(content)
end

local function findPackage(packageName, manifest)
    manifest = manifest or getPackageManifest()
    if not manifest then
        return nil
    end

    for _, package in ipairs(manifest) do
        if package.name == packageName then
            return package
        end
    end

    return nil
end

local function downloadPackageFiles(package, targetDir)
    log(string.format("Downloading package '%s' (v%s)", package.name, package.version))

    ensureDirectory(targetDir)
    local downloadCount = 0
    local errorCount = 0

    -- Download main files
    for _, file in ipairs(package.files) do
        -- Handle subdirectories in path
        local targetPath = fs.combine(targetDir, file.path)
        local targetDir = fs.getDir(targetPath)
        if not fs.exists(targetDir) then
            fs.makeDir(targetDir)
        end
        local success = false

        if file.url then
            -- Use direct URL if provided
            success = downloadFile(file.url, targetPath)
        else
            -- Try both URL formats
            -- First check if it's in this repo directly
            local localPath = file.path

            -- Try to get local path from .mintlinker if available
            if fs.exists(".mintlinker") then
                local mlFile = fs.open(".mintlinker", "r")
                if mlFile then
                    local mlContent = mlFile.readAll()
                    mlFile.close()

                    local mlConfig = textutils.unserialiseJSON and textutils.unserialiseJSON(mlContent) or
                        textutils.unserialize(mlContent)
                    if mlConfig and mlConfig.paths and mlConfig.paths[package.name] then
                        localPath = fs.combine(mlConfig.paths[package.name].code_path or package.name,
                            file.path:match("[^/]+$"))
                    end
                end
            end

            if fs.exists(localPath) then
                log("Using local file: " .. localPath)
                local srcFile = fs.open(localPath, "r")
                if srcFile then
                    local content = srcFile.readAll()
                    srcFile.close()

                    local destFile = fs.open(targetPath, "w")
                    if destFile then
                        destFile.write(content)
                        destFile.close()
                        success = true
                    end
                end
            else
                -- Try GitHub URL
                local filePath = string.format("%s/%s", package.name, file.path)
                local urls = getGitHubRawUrl(PACKAGE_REPO, DEFAULT_BRANCH, filePath)

                for _, url in ipairs(urls) do
                    log("Trying URL: " .. url)
                    success = downloadFile(url, targetPath)
                    if success then
                        break
                    end
                end
            end
        end

        if success then
            downloadCount = downloadCount + 1
        else
            errorCount = errorCount + 1
        end
    end

    -- Download config templates
    if package.templates then
        for _, template in ipairs(package.templates) do
            local targetPath = fs.combine(TEMPLATE_DIR, "." .. package.name .. "." .. template.name .. ".template")
            local success = false

            if template.url then
                -- Use direct URL if provided
                success = downloadFile(template.url, targetPath)
            else
                -- Try both URL formats
                -- First check if template exists locally
                local localTemplatePath = string.format("config_templates/.%s.%s.template", package.name, template.name)

                -- Try to get template path from .mintlinker if available
                if fs.exists(".mintlinker") then
                    local mlFile = fs.open(".mintlinker", "r")
                    if mlFile then
                        local mlContent = mlFile.readAll()
                        mlFile.close()

                        local mlConfig = textutils.unserialiseJSON and textutils.unserialiseJSON(mlContent) or
                            textutils.unserialize(mlContent)
                        if mlConfig and mlConfig.paths and mlConfig.paths[package.name] then
                            for _, tmpl in ipairs(mlConfig.paths[package.name].templates or {}) do
                                if tmpl.name == template.name then
                                    localTemplatePath = tmpl.path
                                    break
                                end
                            end
                        end
                    end
                end

                if fs.exists(localTemplatePath) then
                    log("Using local template: " .. localTemplatePath)
                    local srcFile = fs.open(localTemplatePath, "r")
                    if srcFile then
                        local content = srcFile.readAll()
                        srcFile.close()

                        local destFile = fs.open(targetPath, "w")
                        if destFile then
                            destFile.write(content)
                            destFile.close()
                            success = true
                        end
                    end
                else
                    -- Try GitHub URL
                    local templatePath = string.format("%s/templates/%s", package.name, template.filename)
                    local urls = getGitHubRawUrl(PACKAGE_REPO, DEFAULT_BRANCH, templatePath)

                    for _, url in ipairs(urls) do
                        log("Trying template URL: " .. url)
                        success = downloadFile(url, targetPath)
                        if success then
                            break
                        end
                    end
                end

                if success then
                    downloadCount = downloadCount + 1
                else
                    errorCount = errorCount + 1
                end
            end
        end
    end

    -- Download dependencies
    if package.dependencies then
        for _, dependency in ipairs(package.dependencies) do
            log(string.format("Installing dependency: %s", dependency))
            local manifest = getPackageManifest()
            local dependencyPackage = findPackage(dependency, manifest)

            if dependencyPackage then
                local dependencyDir = fs.combine(PACKAGE_DIR, dependency)
                local success, depDownloadCount, depErrorCount = downloadPackageFiles(dependencyPackage, dependencyDir)

                if success then
                    downloadCount = downloadCount + depDownloadCount
                    errorCount = errorCount + depErrorCount
                else
                    log(string.format("Failed to download dependency: %s", dependency), "ERROR")
                    errorCount = errorCount + 1
                end
            else
                log(string.format("Dependency not found: %s", dependency), "ERROR")
                errorCount = errorCount + 1
            end
        end
    end

    log(string.format("Downloaded %d files with %d errors", downloadCount, errorCount))
    return errorCount == 0, downloadCount, errorCount
end

local function createLauncherScript(package, packageDir)
    if not package.launcher then
        return true
    end

    local launcherPath = fs.combine(MINT_ROOT, package.name .. ".lua")
    local launcherContent = string.format([[
-- Mint Package Launcher for %s (v%s)
-- Auto-generated by mint-package manager

package.path = package.path .. ";%s/?.lua"
local main = require("%s.%s")

local args = {...}
return main.run(unpack(args))
]], package.name, package.version, PACKAGE_DIR, package.name, package.launcher)

    local file = fs.open(launcherPath, "w")
    if file then
        file.write(launcherContent)
        file.close()
        log(string.format("Created launcher: %s", launcherPath))
        return true
    else
        log(string.format("Failed to create launcher: %s", launcherPath), "ERROR")
        return false
    end
end

local function installPackage(packageName)
    log(string.format("Installing package: %s", packageName))

    -- Ensure required directories exist
    ensureDirectory(MINT_ROOT)
    ensureDirectory(PACKAGE_DIR)
    ensureDirectory(CACHE_DIR)
    ensureDirectory(CONFIG_DIR)
    ensureDirectory(TEMPLATE_DIR)

    -- Get package manifest
    local manifest = getPackageManifest()
    if not manifest then
        return false
    end

    -- Find package in manifest
    local package = findPackage(packageName, manifest)
    if not package then
        log(string.format("Package not found: %s", packageName), "ERROR")
        return false
    end

    -- Create package directory
    local packageDir = fs.combine(PACKAGE_DIR, packageName)
    if fs.exists(packageDir) then
        log(string.format("Package already installed: %s", packageName), "WARN")
        log("Use 'mint-package.lua update " .. packageName .. "' to update")
        return false
    end

    -- Download package files
    local success = downloadPackageFiles(package, packageDir)
    if not success then
        log(string.format("Failed to install package: %s", packageName), "ERROR")
        return false
    end

    -- Create launcher script if it doesn't exist locally
    local launcherPath = fs.combine(MINT_ROOT, package.name .. ".lua")
    if not fs.exists(launcherPath) then
        createLauncherScript(package, packageDir)
    else
        log("Launcher script already exists: " .. launcherPath)
    end

    -- Save package info
    savePackageInfo(packageName, package)

    log(string.format("Package installed successfully: %s (v%s)", packageName, package.version))

    -- Print usage instructions if available
    if package.usage then
        print("\nUsage Instructions:")
        print("==================")
        print(package.usage)
    end

    return true
end

local function updatePackage(packageName)
    log(string.format("Updating package: %s", packageName))

    -- Check if package is installed
    local packageDir = fs.combine(PACKAGE_DIR, packageName)
    if not fs.exists(packageDir) then
        log(string.format("Package not installed: %s", packageName), "ERROR")
        log("Use 'mint-package.lua install " .. packageName .. "' to install")
        return false
    end

    -- Get current package info
    local currentInfo = loadPackageInfo(packageName)
    if not currentInfo then
        log(string.format("Package info missing: %s", packageName), "WARN")
    end

    -- Get package manifest
    local manifest = getPackageManifest()
    if not manifest then
        return false
    end

    -- Find package in manifest
    local package = findPackage(packageName, manifest)
    if not package then
        log(string.format("Package no longer available: %s", packageName), "ERROR")
        return false
    end

    -- Check if update is needed
    if currentInfo and currentInfo.version == package.version then
        log(string.format("Package already up to date: %s (v%s)", packageName, package.version))
        return true
    end

    -- Backup current package directory
    local backupDir = fs.combine(CACHE_DIR, packageName .. "_backup")
    if fs.exists(backupDir) then
        fs.delete(backupDir)
    end

    -- Create backup
    ensureDirectory(backupDir)
    local files = fs.list(packageDir)
    for _, file in ipairs(files) do
        local srcPath = fs.combine(packageDir, file)
        local dstPath = fs.combine(backupDir, file)
        if fs.isDir(srcPath) then
            fs.makeDir(dstPath)
            -- Copy directory contents recursively
            local function copyDir(src, dst)
                local items = fs.list(src)
                for _, item in ipairs(items) do
                    local srcItem = fs.combine(src, item)
                    local dstItem = fs.combine(dst, item)
                    if fs.isDir(srcItem) then
                        fs.makeDir(dstItem)
                        copyDir(srcItem, dstItem)
                    else
                        fs.copy(srcItem, dstItem)
                    end
                end
            end
            copyDir(srcPath, dstPath)
        else
            fs.copy(srcPath, dstPath)
        end
    end

    -- Delete current package directory
    fs.delete(packageDir)

    -- Download package files
    local success = downloadPackageFiles(package, packageDir)
    if not success then
        log(string.format("Failed to update package: %s", packageName), "ERROR")
        log("Restoring backup...")

        -- Restore backup
        fs.delete(packageDir)
        local function copyDir(src, dst)
            local items = fs.list(src)
            for _, item in ipairs(items) do
                local srcItem = fs.combine(src, item)
                local dstItem = fs.combine(dst, item)
                if fs.isDir(srcItem) then
                    fs.makeDir(dstItem)
                    copyDir(srcItem, dstItem)
                else
                    fs.copy(srcItem, dstItem)
                end
            end
        end
        copyDir(backupDir, packageDir)
        return false
    end

    -- Update launcher script
    createLauncherScript(package, packageDir)

    -- Save package info
    savePackageInfo(packageName, package)

    -- Clean up backup
    fs.delete(backupDir)

    log(string.format("Package updated successfully: %s (v%s -> v%s)",
        packageName,
        currentInfo and currentInfo.version or "unknown",
        package.version))

    -- Print changelog if available
    if package.changelog then
        print("\nChangelog:")
        print("=========")
        print(package.changelog)
    end

    return true
end

local function removePackage(packageName)
    log(string.format("Removing package: %s", packageName))

    -- Check if package is installed
    local packageDir = fs.combine(PACKAGE_DIR, packageName)
    if not fs.exists(packageDir) then
        log(string.format("Package not installed: %s", packageName), "ERROR")
        return false
    end

    -- Get package info
    local packageInfo = loadPackageInfo(packageName)

    -- Remove launcher script
    local launcherPath = fs.combine(MINT_ROOT, packageName .. ".lua")
    if fs.exists(launcherPath) then
        fs.delete(launcherPath)
        log(string.format("Removed launcher: %s", launcherPath))
    end

    -- Remove config templates
    if packageInfo and packageInfo.templates then
        for _, template in ipairs(packageInfo.templates) do
            local templatePath = fs.combine(TEMPLATE_DIR, "." .. packageName .. "." .. template.name .. ".template")
            if fs.exists(templatePath) then
                fs.delete(templatePath)
                log(string.format("Removed template: %s", templatePath))
            end
        end
    end

    -- Remove package directory
    fs.delete(packageDir)

    -- Remove package info
    local infoPath = fs.combine(CACHE_DIR, packageName .. ".json")
    if fs.exists(infoPath) then
        fs.delete(infoPath)
    end

    log(string.format("Package removed successfully: %s", packageName))
    return true
end

local function listInstalledPackages()
    if not fs.exists(PACKAGE_DIR) then
        log("No packages installed", "INFO")
        return
    end

    local packages = {}
    local dirs = fs.list(PACKAGE_DIR)
    for _, dir in ipairs(dirs) do
        local packageDir = fs.combine(PACKAGE_DIR, dir)
        if fs.isDir(packageDir) then
            local info = loadPackageInfo(dir)
            table.insert(packages, {
                name = dir,
                version = info and info.version or "unknown",
                description = info and info.description or "No description available"
            })
        end
    end

    if #packages == 0 then
        log("No packages installed", "INFO")
        return
    end

    -- Sort alphabetically
    table.sort(packages, function(a, b) return a.name < b.name end)

    print("\nInstalled Packages:")
    print("==================")
    for _, package in ipairs(packages) do
        print(string.format("📦 %s (v%s)", package.name, package.version))
        print("   " .. package.description)
    end
    print(string.format("\nTotal: %d packages installed", #packages))
end

local function searchPackages(query)
    -- Get package manifest
    local manifest = getPackageManifest()
    if not manifest then
        return false
    end

    query = query:lower()
    local results = {}

    for _, package in ipairs(manifest) do
        local nameMatch = package.name:lower():find(query)
        local descMatch = package.description and package.description:lower():find(query)
        local tagsMatch = false

        if package.tags then
            for _, tag in ipairs(package.tags) do
                if tag:lower():find(query) then
                    tagsMatch = true
                    break
                end
            end
        end

        if nameMatch or descMatch or tagsMatch then
            table.insert(results, package)
        end
    end

    -- Sort by relevance
    table.sort(results, function(a, b)
        local aNameMatch = a.name:lower():find(query) ~= nil
        local bNameMatch = b.name:lower():find(query) ~= nil

        if aNameMatch and not bNameMatch then
            return true
        elseif not aNameMatch and bNameMatch then
            return false
        else
            return a.name < b.name
        end
    end)

    print(string.format("\nSearch results for '%s':", query))
    print("===========================" .. string.rep("=", #query))

    if #results == 0 then
        print("No packages found matching your query.")
        return true
    end

    for _, package in ipairs(results) do
        local installed = fs.exists(fs.combine(PACKAGE_DIR, package.name))
        local statusMark = installed and "✅" or "📦"
        print(string.format("%s %s (v%s)", statusMark, package.name, package.version))
        print("   " .. (package.description or "No description available"))
        if package.tags and #package.tags > 0 then
            print("   Tags: " .. table.concat(package.tags, ", "))
        end
    end

    print(string.format("\nTotal: %d packages found", #results))
    return true
end

local function showPackageInfo(packageName)
    -- First check if package is installed locally
    local localInfo = loadPackageInfo(packageName)

    -- Then check the manifest
    local manifest = getPackageManifest()
    if not manifest then
        if not localInfo then
            return false
        end
    end

    local remoteInfo = findPackage(packageName, manifest)

    if not localInfo and not remoteInfo then
        log(string.format("Package not found: %s", packageName), "ERROR")
        return false
    end

    -- Use remote info as base, fall back to local
    local info = remoteInfo or localInfo
    local installed = localInfo ~= nil
    local updateAvailable = installed and remoteInfo and localInfo.version ~= remoteInfo.version

    print(string.format("\nPackage: %s (v%s)", info.name, info.version))
    print(string.string.rep("=", 11 + #info.name + 3 + #info.version))
    print("Status: " .. (installed and "Installed" or "Not installed"))
    if updateAvailable then
        print(string.format("Update: Available (v%s -> v%s)", localInfo.version, remoteInfo.version))
    end

    print("\nDescription:")
    print(info.description or "No description available")

    if info.author then
        print("\nAuthor: " .. info.author)
    end

    if info.dependencies and #info.dependencies > 0 then
        print("\nDependencies:")
        for _, dep in ipairs(info.dependencies) do
            local depInstalled = fs.exists(fs.combine(PACKAGE_DIR, dep))
            print(string.format("- %s %s", dep, depInstalled and "(installed)" or "(not installed)"))
        end
    end

    if info.templates and #info.templates > 0 then
        print("\nConfiguration Templates:")
        for _, template in ipairs(info.templates) do
            print(string.format("- %s: %s", template.name, template.description or "No description"))
        end
    end

    if info.usage then
        print("\nUsage Instructions:")
        print(info.usage)
    end

    if installed and info.files and #info.files > 0 then
        print("\nInstalled Files:")
        for _, file in ipairs(info.files) do
            print("- " .. file.path)
        end
    end

    return true
end

-- Main command handler
local function main()
    -- Use global arg if args is empty (for compatibility)
    local arguments = args
    if #arguments == 0 and arg and #arg > 1 then
        arguments = {}
        for i = 2, #arg do
            table.insert(arguments, arg[i])
        end
    end

    if #arguments == 0 then
        printUsage()
        return
    end

    local command = arguments[1]:lower()

    if command == "install" then
        if #arguments < 2 then
            log("Usage: mint-package.lua install <package>", "ERROR")
            return
        end

        local packageName = arguments[2]
        installPackage(packageName)
    elseif command == "update" then
        if #arguments < 2 then
            log("Usage: mint-package.lua update <package|all>", "ERROR")
            return
        end

        local packageName = arguments[2]

        if packageName == "all" then
            -- Update all installed packages
            if not fs.exists(PACKAGE_DIR) then
                log("No packages installed", "INFO")
                return
            end

            local dirs = fs.list(PACKAGE_DIR)
            local successCount = 0
            local errorCount = 0

            for _, dir in ipairs(dirs) do
                local packageDir = fs.combine(PACKAGE_DIR, dir)
                if fs.isDir(packageDir) then
                    local success = updatePackage(dir)
                    if success then
                        successCount = successCount + 1
                    else
                        errorCount = errorCount + 1
                    end
                end
            end

            log(string.format("Update complete: %d packages updated, %d errors", successCount, errorCount))
        else
            updatePackage(packageName)
        end
    elseif command == "remove" then
        if #arguments < 2 then
            log("Usage: mint-package.lua remove <package>", "ERROR")
            return
        end

        local packageName = arguments[2]
        removePackage(packageName)
    elseif command == "list" then
        listInstalledPackages()
    elseif command == "search" then
        if #arguments < 2 then
            log("Usage: mint-package.lua search <query>", "ERROR")
            return
        end

        local query = arguments[2]
        searchPackages(query)
    elseif command == "info" then
        if #arguments < 2 then
            log("Usage: mint-package.lua info <package>", "ERROR")
            return
        end

        local packageName = arguments[2]
        showPackageInfo(packageName)
    else
        log("Unknown command: " .. command, "ERROR")
        printUsage()
    end
end

-- Run the program
main()
