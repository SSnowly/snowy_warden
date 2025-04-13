local disallowedServers = json.decode(LoadResourceFile(GetCurrentResourceName(), "servers.json"))
local pendingVerifications = {}

local function Log(discordId, badServers, reason)
    if Config.Logger == "discord" then
        local fields = {}
        for i, server in ipairs(badServers) do
            table.insert(fields, {
                ["name"] = string.format("Blacklisted Server #%d", i),
                ["value"] = string.format("**%s**\nType: %s\nID: %s", server.name, server.type, server.id),
                ["inline"] = false
            })
        end

        local payload = {
            embeds = {
                {
                    title = "Discord Verification Failed",
                    description = string.format("User with Discord ID `%s` was denied access.", discordId),
                    color = 15158332, -- Red color
                    fields = fields,
                    footer = {
                        text = os.date("%Y-%m-%d %H:%M:%S")
                    }
                }
            }
        }
        PerformHttpRequest(Config.Discord.WebhookURL, function(err, text, headers) end, "POST", json.encode(payload), {["Content-Type"] = "application/json"})
    elseif Config.Logger == "ox" then
        lib.logger(discordId, "Discord Verification Log", badServers, reason)
    elseif Config.Logger == "file" then
        local logFile = LoadResourceFile(GetCurrentResourceName(), "logs.txt")
        if logFile then
            local currentContent = LoadResourceFile(GetCurrentResourceName(), "logs.txt")
            local newContent = string.format("[%s] (%s) %s servers found\n", os.date("%Y-%m-%d %H:%M:%S"), discordId, #badServers)
            SaveResourceFile(GetCurrentResourceName(), "logs.txt", currentContent .. newContent, -1)
        end
    end
end

local function checkDisallowedServers(guilds)
    local blacklistedGuilds = {}
    for _, guild in pairs(guilds) do
        for _, banned in pairs(disallowedServers) do
            if guild.id == banned.serverid then
                table.insert(blacklistedGuilds, {
                    id = guild.id,
                    name = guild.name,
                    type = banned.type
                })
            end
        end
    end
    return #blacklistedGuilds > 0 and blacklistedGuilds or false
end

local function exchangeCodeForToken(code, cb)
    local data = ("client_id=%s&client_secret=%s&grant_type=authorization_code&code=%s&redirect_uri=%s"):format(
        Config.Discord.ClientId,
        Config.Discord.ClientSecret,
        code,
        Config.Discord.RedirectUri
    )

    PerformHttpRequest('https://discord.com/api/oauth2/token', function(statusCode, text, headers)
        if statusCode ~= 200 then
            print('^1[Discord Auth] Token exchange failed:', statusCode, text)
            cb(false)
            return
        end

        local token = json.decode(text)
        if token and token.access_token then
            cb(token.access_token)
        else
            print('^1[Discord Auth] Invalid token response:', text)
            cb(false)
        end
    end, 'POST', data, {
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ['Content-Length'] = tostring(#data)
    })
end

local function getUserGuilds(accessToken, cb)
    PerformHttpRequest('https://discord.com/api/users/@me/guilds', function(statusCode, text, headers)
        if statusCode ~= 200 then
            print('^1[Discord Auth] Failed to get user guilds:', statusCode, text)
            cb(false)
            return
        end

        local guilds = json.decode(text)
        if guilds then
            cb(guilds)
        else
            print('^1[Discord Auth] Invalid guilds response:', text)
            cb(false)
        end
    end, 'GET', '', {
        ['Authorization'] = 'Bearer ' .. accessToken,
        ['Content-Type'] = 'application/json'
    })
end

local function getUserInfo(accessToken, cb)
    PerformHttpRequest('https://discord.com/api/users/@me', function(statusCode, text, headers)
        if statusCode ~= 200 then
            print('^1[Discord Auth] Failed to get user info:', statusCode, text)
            cb(false)
            return
        end

        local info = json.decode(text)
        if info then
            cb(info)
        else
            print('^1[Discord Auth] Invalid user info response:', text)
            cb(false)
        end
    end, 'GET', '', {
        ['Authorization'] = 'Bearer ' .. accessToken,
        ['Content-Type'] = 'application/json'
    })
end

SetHttpHandler(function(req, res)
    if req.method == 'POST' and req.path == '/cancel' then
        local data = json.decode(req.data)
        if data and data.discordId and pendingVerifications[data.discordId] then
            pendingVerifications[data.discordId].verified = true
            pendingVerifications[data.discordId].cancelled = true
            res.writeHead(200, {['Content-Type'] = 'application/json'})
            res.write(json.encode({status = 'success'}))
            res.send()
            return
        end
    end

    if req.method == 'GET' and req.path:find("^/auth") then
        local discordCode = req.path:match("code=([^&]+)")

        if not discordCode then
            res.writeHead(400, {['Content-Type'] = 'application/json'})
            res.write(json.encode({error = 'Invalid auth code'}))
            res.send()
            return
        end

        exchangeCodeForToken(discordCode, function(accessToken)
            if not accessToken then
                res.writeHead(400, {['Content-Type'] = 'application/json'})
                res.write(json.encode({error = 'Failed to exchange code for token'}))
                res.send()
                return
            end

            getUserInfo(accessToken, function(userInfo)
                if not userInfo or not userInfo.id then
                    res.writeHead(400, {['Content-Type'] = 'application/json'})
                    res.write(json.encode({error = 'Failed to get user info'}))
                    res.send()
                    return
                end

                getUserGuilds(accessToken, function(guilds)
                    if not guilds then
                        res.writeHead(400, {['Content-Type'] = 'application/json'})
                        res.write(json.encode({error = 'Failed to get user guilds'}))
                        res.send()
                        return
                    end

                    local blacklistedGuilds = checkDisallowedServers(guilds)
                    local isBanned = blacklistedGuilds ~= false
                    local data = pendingVerifications[userInfo.id]

                    if not data then
                        res.writeHead(400, {['Content-Type'] = 'application/json'})
                        res.write(json.encode({error = 'No pending verification found'}))
                        res.send()
                        return
                    end
                    if blacklistedGuilds then
                        data.verified = true
                        data.banned = true

                        local serverList = ""
                        for i, guild in ipairs(blacklistedGuilds) do
                            serverList = serverList .. string.format("%s (%s)", guild.name, guild.type)
                            if i < #blacklistedGuilds then
                                serverList = serverList .. "\n"
                            end
                        end
                        -- Format the ban message as a card
                        data.banReason = [=[
                        {
                            "type": "AdaptiveCard",
                            "version": "1.0",
                            "body": [
                                {
                                    "type": "Container",
                                    "items": [
                                        {
                                            "type": "TextBlock",
                                            "text": "Access Denied",
                                            "size": "large",
                                            "weight": "bolder",
                                            "color": "attention",
                                            "horizontalAlignment": "center"
                                        },
                                        {
                                            "type": "TextBlock",
                                            "text": "]=] .. string.format("You are in %d blacklisted Discord server(s):", #blacklistedGuilds) .. [=[",
                                            "wrap": true,
                                            "horizontalAlignment": "center"
                                        }
                                    ]
                                },
                                {
                                    "type": "Container",
                                    "style": "attention",
                                    "items": [
                                        {
                                            "type": "TextBlock",
                                            "text": "]=] .. table.concat(
                                                (function()
                                                    local list = {}
                                                    for i, guild in ipairs(blacklistedGuilds) do
                                                        table.insert(list, string.format("%d. %s (%s)", i, guild.name, guild.type))
                                                    end
                                                    return list
                                                end)(), "\\n"
                                            ) .. [=[",
                                            "wrap": true,
                                            "spacing": "medium",
                                            "color": "attention",
                                            "horizontalAlignment": "center"
                                        }
                                    ]
                                }
                            ]
                        }]=]
                        Log(userInfo.id, blacklistedGuilds, serverList)
                    else
                        data.verified = true
                        data.banned = false
                    end

                    res.writeHead(200, {
                        ['Content-Type'] = 'text/html',
                        ['Cache-Control'] = 'no-cache, no-store, must-revalidate',
                        ['Pragma'] = 'no-cache',
                        ['Expires'] = '0'
                    })
                    res.write([[
                        <html>
                            <head>
                                <title>Authentication ]] .. (isBanned and "Failed" or "Complete") .. [[</title>
                                <style>
                                    * {
                                        margin: 0;
                                        padding: 0;
                                        box-sizing: border-box;
                                        font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, system-ui, Roboto, sans-serif;
                                    }
                                    body {
                                        background: linear-gradient(135deg, #1e1e2e, #2d2d3d);
                                        min-height: 100vh;
                                        display: flex;
                                        align-items: center;
                                        justify-content: center;
                                        color: #fff;
                                    }
                                    .container {
                                        background: rgba(255, 255, 255, 0.1);
                                        backdrop-filter: blur(10px);
                                        padding: 2rem;
                                        border-radius: 12px;
                                        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
                                        text-align: center;
                                        max-width: 90%;
                                        width: 400px;
                                        animation: fadeIn 0.5s ease-out;
                                    }
                                    @keyframes fadeIn {
                                        from { opacity: 0; transform: translateY(20px); }
                                        to { opacity: 1; transform: translateY(0); }
                                    }
                                    h1 {
                                        font-size: 24px;
                                        margin-bottom: 1rem;
                                        color: #fff;
                                    }
                                    .icon {
                                        width: 60px;
                                        height: 60px;
                                        border-radius: 50%;
                                        margin: 0 auto 1.5rem;
                                        position: relative;
                                        animation: scaleIn 0.3s ease-out 0.2s both;
                                    }
                                    .icon.success {
                                        background: #4CAF50;
                                    }
                                    .icon.error {
                                        background: #f44336;
                                    }
                                    @keyframes scaleIn {
                                        from { transform: scale(0); }
                                        to { transform: scale(1); }
                                    }
                                    .icon.success:after {
                                        content: '';
                                        width: 30px;
                                        height: 15px;
                                        border: 4px solid #fff;
                                        border-top: none;
                                        border-right: none;
                                        position: absolute;
                                        top: 50%;
                                        left: 50%;
                                        transform: translate(-50%, -60%) rotate(-45deg);
                                        animation: checkmark 0.2s ease-out 0.5s both;
                                    }
                                    .icon.error:before,
                                    .icon.error:after {
                                        content: '';
                                        position: absolute;
                                        width: 4px;
                                        height: 30px;
                                        background: #fff;
                                        top: 50%;
                                        left: 50%;
                                    }
                                    .icon.error:before {
                                        transform: translate(-50%, -50%) rotate(45deg);
                                        animation: crossmark1 0.2s ease-out 0.5s both;
                                    }
                                    .icon.error:after {
                                        transform: translate(-50%, -50%) rotate(-45deg);
                                        animation: crossmark2 0.2s ease-out 0.5s both;
                                    }
                                    @keyframes checkmark {
                                        from { opacity: 0; }
                                        to { opacity: 1; }
                                    }
                                    @keyframes crossmark1 {
                                        from { opacity: 0; transform: translate(-50%, -50%) rotate(45deg) scale(0.5); }
                                        to { opacity: 1; transform: translate(-50%, -50%) rotate(45deg) scale(1); }
                                    }
                                    @keyframes crossmark2 {
                                        from { opacity: 0; transform: translate(-50%, -50%) rotate(-45deg) scale(0.5); }
                                        to { opacity: 1; transform: translate(-50%, -50%) rotate(-45deg) scale(1); }
                                    }
                                    p {
                                        color: rgba(255, 255, 255, 0.9);
                                        line-height: 1.5;
                                        margin-bottom: 1rem;
                                    }
                                    .error-details {
                                        background: rgba(244, 67, 54, 0.1);
                                        border: 1px solid rgba(244, 67, 54, 0.3);
                                        padding: 1rem;
                                        border-radius: 8px;
                                        margin: 1rem 0;
                                        font-size: 0.9rem;
                                        color: rgba(255, 255, 255, 0.8);
                                        text-align: left;
                                        white-space: pre-line;
                                    }
                                    .close-text {
                                        color: rgba(255, 255, 255, 0.6);
                                        font-size: 0.9rem;
                                    }
                                </style>
                            </head>
                            <body>
                                <div class="container">
                                    <div class="icon ]] .. (isBanned and "error" or "success") .. [["></div>
                                    <h1>]] .. (isBanned and "Authentication Failed" or "Authentication Complete") .. [[</h1>
                                    ]] .. (isBanned and [[
                                    <p>Access Denied</p>
                                    <div class="error-details">]] .. (blacklistedGuilds and string.format("Found in %d blacklisted servers:\n\n%s", #blacklistedGuilds, table.concat(
                                        (function()
                                            local list = {}
                                            for i, guild in ipairs(blacklistedGuilds) do
                                                table.insert(list, string.format("%d. %s (%s)", i, guild.name, guild.type))
                                            end
                                            return list
                                        end)(), "\n"
                                    )) or "Error getting server details") .. [[</div>
                                    ]] or [[
                                    <p>Your Discord verification was successful.</p>
                                    <p>No blacklisted servers found.</p>
                                    ]]) .. [[
                                </div>
                            </body>
                        </html>
                    ]])
                    res.send()
                end)
            end)
        end)
    else
        res.writeHead(404, {['Content-Type'] = 'application/json'})
        res.write(json.encode({error = 'Not found'}))
        res.send()
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local player = source
    local identifiers = GetPlayerIdentifiers(player)
    local discordId

    deferrals.defer()
    Wait(0)

    for _, v in pairs(identifiers) do
        if string.find(v, "discord:") then
            discordId = string.sub(v, 9)
            break
        end
    end

    Wait(0)

    if not discordId then
        deferrals.done("You must have discord open to join this server.")
        return
    end

    pendingVerifications[discordId] = {
        player = player,
        verified = false,
        banned = false,
        banReason = nil,
        timestamp = os.time()
    }

    while true do
        if pendingVerifications[discordId] and pendingVerifications[discordId].verified then
            if pendingVerifications[discordId].cancelled then
                deferrals.presentCard([=[
                {
                    "type": "AdaptiveCard",
                    "version": "1.0",
                    "body": [
                        {
                            "type": "Container",
                            "items": [
                                {
                                    "type": "TextBlock",
                                    "text": "Verification Cancelled",
                                    "size": "large",
                                    "weight": "bolder",
                                    "color": "warning",
                                    "horizontalAlignment": "center"
                                },
                                {
                                    "type": "TextBlock",
                                    "text": "You cancelled the verification process.",
                                    "wrap": true,
                                    "horizontalAlignment": "center"
                                }
                            ]
                        }
                    ]
                }]=])
                Wait(5000)
                deferrals.done("Verification cancelled.")
            elseif pendingVerifications[discordId].banned then
                deferrals.presentCard(pendingVerifications[discordId].banReason)
                Wait(5000)
                deferrals.done("Access denied - You are in blacklisted Discord servers.")
            else
                deferrals.done()
            end
            pendingVerifications[discordId] = nil
            break
        end

        deferrals.presentCard([=[
        {
            "type": "AdaptiveCard",
            "version": "1.0",
            "body": [
                {
                    "type": "Container",
                    "items": [
                        {
                            "type": "TextBlock",
                            "text": "Discord Verification Required",
                            "size": "large",
                            "weight": "bolder",
                            "horizontalAlignment": "center",
                            "spacing": "large"
                        },
                        {
                            "type": "TextBlock",
                            "text": "Click the button below to be able to join the server.",
                            "wrap": true,
                            "horizontalAlignment": "center",
                            "spacing": "medium"
                        }
                    ]
                },
                {
                    "type": "Container",
                    "spacing": "large",
                    "items": [
                        {
                            "type": "ActionSet",
                            "horizontalAlignment": "center",
                            "actions": [
                                {
                                    "type": "Action.OpenUrl",
                                    "title": "Verify with Discord",
                                    "url": "]=] .. string.format("https://discord.com/api/oauth2/authorize?client_id=%s&redirect_uri=%s&response_type=code&scope=guilds", Config.Discord.ClientId, Config.Discord.RedirectUri) .. [=[",
                                    "style": "positive"
                                },
                                {
                                    "type": "Action.Submit",
                                    "title": "Cancel",
                                    "style": "destructive",
                                    "data": {
                                        "action": "cancel",
                                        "discordId": "]=] .. discordId .. [=["
                                    }
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    ]=], function(data)
        if data.action == "cancel" then
            pendingVerifications[discordId].cancelled = true
        end
    end)
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for discordId, data in pairs(pendingVerifications) do
            if (now - data.timestamp) > 300 then
                pendingVerifications[discordId] = nil
            end
        end
    end
end)

