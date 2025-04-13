# Snowy Warden

A FiveM resource that provides Discord-based server protection through OAuth2 verification and server membership checks.

## Features

- 🔒 **Discord OAuth2 Integration**
  - Secure verification process
  - Modern, responsive UI
  - Automatic timeout handling

- 🛡️ **Server Protection**
  - Checks user's Discord servers
  - Prevents users in blacklisted servers from joining
  - Configurable blacklist categories (CHEATING, LEAKING, RESELLING)

- 📝 **Detailed Logging**
  - Discord webhook support
  - ox_lib logger support
  - File logging option
  - Detailed error tracking

- 💅 **Modern UI**
  - Adaptive Cards for all screens
  - Animated success/error indicators
  - Clean, responsive design
  - User-friendly messages

## Setup

1. Create a Discord Application:
   - Go to [Discord Developer Portal](https://discord.com/developers/applications)
   - Create a new application
   - Note down the Client ID and Client Secret
   - Add your redirect URI (e.g., `http://yourserver:30120/snowy_warden/auth`) <-- The snowy_warden part is required as that is the resource name!

2. Set up configuration files:
   - Copy `config.example.lua` to `config.lua`
   - Copy `servers.example.json` to `servers.json`
   - Update both files with your settings

3. Configure the resource:
   ```lua
   -- config.lua
   Config = {
       Logger = "discord" -- Options: "discord", "ox", "file"
       Discord = {
           ClientId = "your_client_id",
           ClientSecret = "your_client_secret",
           RedirectUri = "http://yourserver:30120/snowy_warden/auth",
           WebhookURL = "your_discord_webhook_url" -- Optional, for logging
       },
   }
   ```

4. Add to your server.cfg:
   ```cfg
   ensure snowy_warden
   ```

## How it Works

1. When a player connects, they must verify through Discord
2. The resource checks their Discord servers
3. If they're in any blacklisted servers:
   - They see which servers are blacklisted
   - Connection is denied
   - Log is generated (if configured)
4. If clean:
   - Player is allowed to connect
   - Verification status is cleared

## Customization

- Customize UI messages and styling in the AdaptiveCard templates
- Adjust verification flow timings
- Configure different logging methods

## Requirements

- FiveM/RedM server
- Discord application
- Your server's ip address
- resource has to be named **snowy_warden**

## Security Note

The following files contain sensitive data and are not included in the repository:
- `servers.json` (Blacklisted server IDs)

Please use the example files as templates and never commit your actual configuration files.
