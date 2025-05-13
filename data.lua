-- Shop Stock and Weather Monitor
print("🛒 Shop Stock and Weather Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"
local CHECK_INTERVAL = 5  -- Check every 5 seconds
local MAX_RETRIES = 3

-- Cache to track changes
local Cache = {
    seedStock = {},
    gearStock = {},
    currentWeather = "None",
    weatherDuration = 0,
    lastUpdate = 0,
    errorCount = 0
}

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
end

-- Function to detect changes in stock data
local function hasChanges(oldData, newData)
    -- Check weather changes
    if oldData.weather.type ~= newData.weather.type or 
       oldData.weather.duration ~= newData.weather.duration then
        return true
    end
    
    -- Check seeds
    for seedName, newStock in pairs(newData.seeds) do
        if oldData.seeds[seedName] ~= newStock then
            return true
        end
    end
    
    -- Check for new or removed seeds
    local oldSeedCount, newSeedCount = 0, 0
    for _ in pairs(oldData.seeds) do oldSeedCount = oldSeedCount + 1 end
    for _ in pairs(newData.seeds) do newSeedCount = newSeedCount + 1 end
    if oldSeedCount ~= newSeedCount then
        return true
    end
    
    -- Check gear
    for gearName, newStock in pairs(newData.gear) do
        if oldData.gear[gearName] ~= newStock then
            return true
        end
    end
    
    -- Check for new or removed gear
    local oldGearCount, newGearCount = 0, 0
    for _ in pairs(oldData.gear) do oldGearCount = oldGearCount + 1 end
    for _ in pairs(newData.gear) do newGearCount = newGearCount + 1 end
    if oldGearCount ~= newGearCount then
        return true
    end
    
    return false
end

-- Function to send data to API
local function sendToAPI(data)
    local success, response = pcall(function()
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
        
        -- Send request using the supported REQUEST function
        return request({
            Url = API_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonStr
        })
    end)
    
    if not success then
        warn("❌ Failed to send data:", response)
        Cache.errorCount = Cache.errorCount + 1
        
        if Cache.errorCount >= MAX_RETRIES then
            warn("⚠️ Max retry attempts reached")
            Cache.errorCount = 0
            return false
        end
        
        print("🔄 Retrying in 5 seconds...")
        wait(5)
        return sendToAPI(data)
    end
    
    Cache.errorCount = 0
    print("✅ Data sent successfully")
    return true
end

-- Anti-AFK function
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        print("🔄 Anti-AFK triggered")
    end)
end

-- Setup weather event listener
local function setupWeatherListener()
    print("🌦️ Setting up weather event listener...")
    
    -- Fix the syntax for connecting to the weather event
    local success, conn = pcall(function()
        return game.ReplicatedStorage.GameEvents.WeatherEventStarted.OnClientEvent:Connect(function(weatherType, duration)
            print("🌦️ Weather event detected:", weatherType, duration)
            
            -- Update weather cache
            Cache.currentWeather = weatherType or "None"
            Cache.weatherDuration = duration or 0
            
            -- Force an immediate update to the API
            local currentData = collectStockData()
            sendToAPI(currentData)
            
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
        warn("⚠️ Failed to set up weather listener:", conn)
    else
        print("✅ Weather listener set up successfully")
    end
end

-- Main monitoring function
local function startMonitoring()
    print("🛒 Shop Stock and Weather Monitor Started")
    
    -- Setup anti-AFK
    pcall(setupAntiAFK)
    
    -- Setup weather listener
    pcall(setupWeatherListener)
    
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
        
        -- Send initial data
        sendToAPI(initialData)
    else
        warn("❌ Failed to collect initial data:", initialData)
    end
    
    -- Main monitoring loop
    while true do
        local success, currentData = pcall(collectStockData)
        
        if success then
            local currentTime = os.time()
            
            -- Create a comparison object with the same structure as currentData
            local oldData = {
                seeds = Cache.seedStock,
                gear = Cache.gearStock,
                weather = {
                    type = Cache.currentWeather,
                    duration = Cache.weatherDuration
                }
            }
            
            local hasStockChanges = hasChanges(oldData, currentData)
            local timeForceUpdate = (currentTime - Cache.lastUpdate) >= 300  -- Force update every 5 minutes
            
            if hasStockChanges or timeForceUpdate then
                print("📊 Changes detected or force update triggered")
                
                if sendToAPI(currentData) then
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
                end
            else
                print("📊 No changes detected")
            end
        else
            warn("❌ Error collecting data:", currentData)
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- Start the monitoring
startMonitoring()
