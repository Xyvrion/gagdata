-- Shop Stock and Weather Monitor with API Data Management and Health Monitoring
print("🛒 Shop Stock and Weather Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/api/data"
local API_AUTH_KEY = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1371909907716112465/02IHVPmNEadS6nTwcseKNPHPwjIxK2P4raUE4tzgaqz_NO3vGaIAbF8aN76wVM5-YnPO"
local CHECK_INTERVAL = 1  -- Check every 5 seconds
local HEALTH_CHECK_INTERVAL = 15  -- Send health update every 60 seconds
local MAX_RETRIES = 3

-- Cache to track changes
local Cache = {
    seedStock = {},
    gearStock = {},
    currentWeather = "None",
    weatherDuration = 0,
    lastUpdate = 0,
    lastHealthUpdate = 0,
    errorCount = 0,
    successfulUpdates = 0,
    failedUpdates = 0
}

-- Function to send health logs to Discord webhook
local function sendHealthLog(message, isError)
    local success, response = pcall(function()
        local currentTime = os.date("%Y-%m-%d %H:%M:%S")
        local statusEmoji = isError and "❌" or "✅"
        
        local content = string.format("**%s Health Monitor** %s\n```\n[%s] %s\n```", 
            game.Players.LocalPlayer.Name, 
            statusEmoji,
            currentTime, 
            message)
        
        return request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = string.format('{"content":"%s"}', content:gsub('"', '\\"'):gsub('\n', '\\n'))
        })
    end)
    
    if not success then
        warn("❌ Failed to send health log:", response)
    end
    
    return success
end

-- Function to send detailed health report to Discord
local function sendHealthReport()
    local uptime = os.time() - Cache.lastUpdate
    local hours = math.floor(uptime / 3600)
    local minutes = math.floor((uptime % 3600) / 60)
    local seconds = uptime % 60
    
    local healthReport = string.format([[
**📊 Health Report**

**Status**: Online
**Uptime**: %02d:%02d:%02d
**Player**: %s
**Game ID**: %s

**Statistics**:
• Successful Updates: %d
• Failed Updates: %d
• Current Weather: %s
• Weather Duration: %s
• Seed Items: %d
• Gear Items: %d
• Last Update: <t:%d:R>

**System Info**:
• Memory Usage: %.2f MB
]],
        hours, minutes, seconds,
        game.Players.LocalPlayer.Name,
        game.PlaceId,
        Cache.successfulUpdates,
        Cache.failedUpdates,
        Cache.currentWeather,
        Cache.weatherDuration,
        #Cache.seedStock,
        #Cache.gearStock,
        Cache.lastUpdate,
        collectgarbage("count") / 1024
    )
    
    local success, response = pcall(function()
        return request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = string.format('{"content":"%s"}', healthReport:gsub('"', '\\"'):gsub('\n', '\\n'))
        })
    end)
    
    if not success then
        warn("❌ Failed to send health report:", response)
    end
    
    return success
end

-- Function to check stock for a specific item
local function checkStock(fruit, shopType)
    for _, des in pairs(game.Players.LocalPlayer.PlayerGui[shopType].Frame.ScrollingFrame:GetDescendants()) do
        if des.Name == "Stock_Text" and des.Parent.Parent.Name == fruit then
            return string.match(des.Text, "%d+")
        end
    end
    return "0"
end

-- Function to get all available seed names
local function getAvailableSeedNames()
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("Seed_Shop")
    if not shopUI then return {} end

    local names = {}
    local scroll = shopUI.Frame.ScrollingFrame
    for _, item in pairs(scroll:GetChildren()) do
        if item:IsA("Frame") and not item.Name:match("_Padding$") then
            table.insert(names, item.Name)
        end
    end
    return names
end

-- Function to get all available gear names
local function getAvailableGearNames()
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("Gear_Shop")
    if not shopUI then return {} end

    local names = {}
    local scroll = shopUI.Frame.ScrollingFrame
    for _, item in pairs(scroll:GetChildren()) do
        if item:IsA("Frame") and not item.Name:match("_Padding$") then
            table.insert(names, item.Name)
        end
    end
    return names
end

-- Function to collect all stock data
local function collectStockData()
    -- Create a completely new data object (old data gets garbage collected)
    local data = {
        seeds = {},
        gear = {},
        weather = {
            type = Cache.currentWeather,
            duration = Cache.weatherDuration
        },
        timestamp = os.time(),
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId
    }
    
    -- Collect seed data (fresh collection, not using old data)
    local seedNames = getAvailableSeedNames()
    for _, seedName in ipairs(seedNames) do
        local stock = checkStock(seedName, "Seed_Shop")
        data.seeds[seedName] = stock
    end
    
    -- Collect gear data (fresh collection, not using old data)
    local gearNames = getAvailableGearNames()
    for _, gearName in ipairs(gearNames) do
        local stock = checkStock(gearName, "Gear_Shop")
        data.gear[gearName] = stock
    end
    
    return data
}

-- Function to make API requests (GET, POST, PUT, PATCH, DELETE)
local function makeAPIRequest(method, data)
    local success, response = pcall(function()
        local options = {
            Url = API_ENDPOINT,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_AUTH_KEY
            }
        }
        
        if data then
            -- Convert data to JSON string (simple version)
            local jsonStr = "{"
            
            -- Add timestamp
            jsonStr = jsonStr .. '"timestamp":' .. data.timestamp .. ','
            
            -- Add player info
            jsonStr = jsonStr .. '"playerName":"' .. data.playerName .. '",'
            jsonStr = jsonStr .. '"userId":' .. data.userId .. ','
            
            -- Add weather info
            jsonStr = jsonStr .. '"weather":{'
            jsonStr = jsonStr .. '"type":"' .. data.weather.type .. '",'
            jsonStr = jsonStr .. '"duration":' .. data.weather.duration
            jsonStr = jsonStr .. '},'
            
            -- Add seeds
            jsonStr = jsonStr .. '"seeds":{'
            local first = true
            for name, stock in pairs(data.seeds) do
                if not first then jsonStr = jsonStr .. ',' end
                first = false
                jsonStr = jsonStr .. '"' .. name .. '":"' .. stock .. '"'
            end
            jsonStr = jsonStr .. '},'
            
            -- Add gear
            jsonStr = jsonStr .. '"gear":{'
            first = true
            for name, stock in pairs(data.gear) do
                if not first then jsonStr = jsonStr .. ',' end
                first = false
                jsonStr = jsonStr .. '"' .. name .. '":"' .. stock .. '"'
            end
            jsonStr = jsonStr .. '}'
            
            jsonStr = jsonStr .. "}"
            
            options.Body = jsonStr
        }
        
        -- Send request using the supported REQUEST function
        local result = request(options)
        
        -- Print response for debugging
        print("API Response (" .. method .. "):", result.StatusCode, result.Body and string.sub(result.Body, 1, 100) .. "..." or "No body")
        
        return result
    end)
    
    if not success then
        warn("❌ Failed to make " .. method .. " request:", response)
        sendHealthLog("Failed to make " .. method .. " request: " .. tostring(response), true)
        return false, response
    end
    
    -- Check if the status code indicates success
    if response.StatusCode >= 200 and response.StatusCode < 300 then
        -- Try to parse the response body
        local responseData
        success, responseData = pcall(function()
            -- Simple JSON parser for the specific response structure
            local body = response.Body
            if body and body:match('"success":true') then
                return {success = true}
            else
                return {success = false, message = body}
            end
        end)
        
        if success and responseData.success then
            return true, response
        else
            warn("❌ API request failed with response:", responseData.message or "Unknown error")
            sendHealthLog("API request failed with response: " .. (responseData.message or "Unknown error"), true)
            return false, response
        end
    else
        warn("❌ API request failed with status code:", response.StatusCode)
        sendHealthLog("API request failed with status code: " .. tostring(response.StatusCode), true)
        return false, response
    end
end

-- Function to update data using the appropriate method based on permissions
local function updateAPIData(data)
    print("📤 Updating API data...")
    
    -- Try PUT first (replaces data)
    local success, response = makeAPIRequest("PUT", data)
    
    if success then
        print("✅ Successfully updated API data using PUT")
        return true
    else
        print("⚠️ PUT failed, trying POST...")
        
        -- If PUT fails, try POST (creates new data)
        success, response = makeAPIRequest("POST", data)
        
        if success then
            print("✅ Successfully updated API data using POST")
            return true
        else
            print("⚠️ POST failed, trying PATCH...")
            
            -- If POST fails, try PATCH (updates data partially)
            success, response = makeAPIRequest("PATCH", data)
            
            if success then
                print("✅ Successfully updated API data using PATCH")
                return true
            else
                warn("❌ All update methods failed")
                sendHealthLog("All API update methods failed", true)
                return false
            end
        end
    end
end

-- Function to check current API data
local function checkAPIData()
    print("🔍 Checking current API data...")
    
    local success, response = makeAPIRequest("GET")
    
    if success then
        print("✅ Successfully retrieved API data")
        return true, response
    else
        warn("❌ Failed to retrieve API data")
        sendHealthLog("Failed to retrieve API data", true)
        return false, response
    end
end

-- Anti-AFK function
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        print("🔄 Anti-AFK triggered")
        sendHealthLog("Anti-AFK system triggered", false)
    end)
end

-- Setup weather event listener with detailed error reporting
local function setupWeatherListener()
    print("🌦️ Setting up weather event listener...")
    
    -- Check if the weather event exists
    if not game.ReplicatedStorage:FindFirstChild("GameEvents") then
        warn("❌ GameEvents not found in ReplicatedStorage")
        sendHealthLog("GameEvents not found in ReplicatedStorage", true)
        return false
    end
    
    if not game.ReplicatedStorage.GameEvents:FindFirstChild("WeatherEventStarted") then
        warn("❌ WeatherEventStarted event not found in GameEvents")
        sendHealthLog("WeatherEventStarted event not found in GameEvents", true)
        return false
    end
    
    if not game.ReplicatedStorage.GameEvents.WeatherEventStarted:FindFirstChild("OnClientEvent") then
        warn("❌ OnClientEvent not found in WeatherEventStarted")
        sendHealthLog("OnClientEvent not found in WeatherEventStarted", true)
        return false
    end
    
    -- Fix the syntax for connecting to the weather event
    local success, result = pcall(function()
        return game.ReplicatedStorage.GameEvents.WeatherEventStarted.OnClientEvent:Connect(function(weatherType, duration)
            print("🌦️ Weather event detected:", weatherType, duration)
            sendHealthLog("Weather event detected: " .. tostring(weatherType) .. " (Duration: " .. tostring(duration) .. ")", false)
            
            -- Update weather cache
            Cache.currentWeather = weatherType or "None"
            Cache.weatherDuration = duration or 0
            
            -- Force an immediate update to the API
            local currentData = collectStockData()
            
            -- Update API data
            updateAPIData(currentData)
            
            -- Update cache with new data
            Cache.seedStock = {}  -- Clear old data
            Cache.gearStock = {}  -- Clear old data
            
            -- Copy new data (not references)
            for k, v in pairs(currentData.seeds) do
                Cache.seedStock[k] = v
            end
            
            for k, v in pairs(currentData.gear) do
                Cache.gearStock[k] = v
            end
            
            Cache.lastUpdate = os.time()
        end)
    end)
    
    if not success then
        warn("❌ Failed to set up weather listener: " .. tostring(result))
        sendHealthLog("Failed to set up weather listener: " .. tostring(result), true)
        return false
    else
        print("✅ Weather listener set up successfully")
        sendHealthLog("Weather listener set up successfully", false)
        return true
    end
end

-- Main monitoring function
local function startMonitoring()
    print("🛒 Shop Stock and Weather Monitor Started")
    sendHealthLog("Shop Stock and Weather Monitor Started", false)
    
    -- Setup anti-AFK
    pcall(setupAntiAFK)
    
    -- Check current API data
    local apiCheckSuccess = checkAPIData()
    if not apiCheckSuccess then
        warn("⚠️ Initial API check failed, but continuing anyway")
        sendHealthLog("Initial API check failed, but continuing anyway", true)
    end
    
    -- Setup weather listener with error reporting
    local weatherSetupSuccess = pcall(setupWeatherListener)
    if not weatherSetupSuccess then
        print("⚠️ Weather event listener setup failed, continuing without weather tracking")
        sendHealthLog("Weather event listener setup failed, continuing without weather tracking", true)
    end
    
    -- Initial data collection
    local success, initialData = pcall(collectStockData)
    if success then
        -- Clear old data and store new data (not references)
        Cache.seedStock = {}
        Cache.gearStock = {}
        
        for k, v in pairs(initialData.seeds) do
            Cache.seedStock[k] = v
        end
        
        for k, v in pairs(initialData.gear) do
            Cache.gearStock[k] = v
        end
        
        Cache.lastUpdate = os.time()
        Cache.lastHealthUpdate = os.time()
        
        -- Send initial data
        updateAPIData(initialData)
        sendHealthLog("Initial data collected and sent successfully", false)
        sendHealthReport()
    else
        warn("❌ Failed to collect initial data:", initialData)
        sendHealthLog("Failed to collect initial data: " .. tostring(initialData), true)
    end
    
    -- Main monitoring loop
    while true do
        local success, currentData = pcall(collectStockData)
        
        if success then
            local currentTime = os.time()
            
            -- Force update every time to ensure data is always updated
            print("📊 Updating data...")
            
            -- Update API data
            if updateAPIData(currentData) then
                -- Clear old data and store new data (not references)
                Cache.seedStock = {}
                Cache.gearStock = {}
                
                for k, v in pairs(currentData.seeds) do
                    Cache.seedStock[k] = v
                end
                
                for k, v in pairs(currentData.gear) do
                    Cache.gearStock[k] = v
                end
                
                Cache.lastUpdate = currentTime
                print("📊 Data updated successfully")
                
                -- Check if it's time to send a health report
                if (currentTime - Cache.lastHealthUpdate) >= HEALTH_CHECK_INTERVAL then
                    sendHealthReport()
                    Cache.lastHealthUpdate = currentTime
                end
            else
                warn("❌ Failed to update API data")
                sendHealthLog("Failed to update API data", true)
            end
        else
            warn("❌ Error collecting data:", currentData)
            sendHealthLog("Error collecting data: " .. tostring(currentData), true)
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- Start the monitoring with error handling
local success, errorMsg = pcall(function()
    -- Send startup notification
    sendHealthLog("Script starting up...", false)
    wait(1) -- Wait a bit to ensure the message is sent
    
    -- Start monitoring
    startMonitoring()
end)

if not success then
    warn("❌ Critical error in monitoring script: " .. tostring(errorMsg))
    sendHealthLog("CRITICAL ERROR: " .. tostring(errorMsg), true)
end
