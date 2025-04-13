Config = {

    Logger = "discord", -- "file", "discord", "ox"
    Discord = {
        ClientId = "", -- Your Discord application client ID
        ClientSecret = "", -- Your Discord application client secret
        RedirectUri = "http://localhost:30120/snowy_warden/auth", -- Your redirect URI (change localhost to your server's IP/domain)
        WebhookURL = "" -- Only if using Logger = "discord"
    }
} 