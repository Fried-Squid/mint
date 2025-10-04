-- Simple logging module for the mining turtle
local logger = {}

-- Log levels
logger.LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

-- Current log level threshold - only messages at this level or higher will be printed
logger.current_level = logger.LEVELS.INFO

-- Level names for printing
local level_names = {
    [logger.LEVELS.DEBUG] = "DEBUG",
    [logger.LEVELS.INFO] = "INFO",
    [logger.LEVELS.WARN] = "WARN",
    [logger.LEVELS.ERROR] = "ERROR"
}

-- Set the minimum log level
function logger.set_level(level)
    if type(level) == "number" and level >= 1 and level <= 4 then
        logger.current_level = level
        logger.info("Log level set to " .. level_names[level])
    else
        logger.error("Invalid log level: " .. tostring(level))
    end
end

-- Internal function to log a message at a specific level
local function log_at_level(level, message)
    -- Only log if the level meets the threshold
    if level >= logger.current_level then
        -- Print the message with timestamp and level
        local timestamp = os.date("%H:%M:%S")
        print(string.format("[%s][%s] %s", timestamp, level_names[level], message))
    end
end

-- Log a debug message
function logger.debug(message)
    log_at_level(logger.LEVELS.DEBUG, message)
end

-- Log an info message
function logger.info(message)
    log_at_level(logger.LEVELS.INFO, message)
end

-- Log a warning message
function logger.warn(message)
    log_at_level(logger.LEVELS.WARN, message)
end

-- Log an error message
function logger.error(message)
    log_at_level(logger.LEVELS.ERROR, message)
end

-- Log a table's contents (useful for debugging)
function logger.dump_table(table_data, description, max_depth)
    max_depth = max_depth or 3 -- Default maximum depth
    description = description or "Table dump"

    local function format_table(tbl, depth, path)
        if depth > max_depth then
            return "  [max depth reached]"
        end

        local result = {}
        local indent = string.rep("  ", depth)

        for k, v in pairs(tbl) do
            local key_str = tostring(k)
            local value_type = type(v)
            local current_path = path .. "." .. key_str

            if value_type == "table" then
                table.insert(result, indent .. key_str .. " = {")
                table.insert(result, format_table(v, depth + 1, current_path))
                table.insert(result, indent .. "}")
            else
                local value_str
                if value_type == "string" then
                    value_str = '"' .. tostring(v) .. '"'
                else
                    value_str = tostring(v)
                end
                table.insert(result, indent .. key_str .. " = " .. value_str)
            end
        end

        return table.concat(result, "\n")
    end

    local dump_str = format_table(table_data, 1, "")
    logger.debug(description .. ":\n" .. dump_str)
end

return logger
