--// NOVA HUB 1911 - Universal GitHub Loader
--// Tyy repository
--// Downloads the complete Nova Hub, including Universal Fallback mode.

local BASE = "https://raw.githubusercontent.com/phnj9dgrdc-cell/Tyy/main/"
local PARTS = {
    "NovaHub_1911_part1.lua",
    "NovaHub_1911_part2.lua",
    "NovaHub_1911_part3.lua",
    "NovaHub_1911_part4.lua",
    "NovaHub_1911_part5.lua",
    "NovaHub_1911_part6.lua",
    "NovaHub_1911_part7.lua",
    "NovaHub_1911_part8.lua",
}

local function notify(title, msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = tostring(title),
            Text = tostring(msg),
            Duration = 5
        })
    end)
end

local function fetch(url)
    local req = (syn and syn.request) or (http and http.request) or http_request or request

    if req then
        local ok, response = pcall(function()
            return req({
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "Roblox/Exploit",
                    ["Accept"] = "*/*"
                }
            })
        end)

        if ok and type(response) == "table" then
            local status = tonumber(response.StatusCode or response.Status or 0) or 0
            local body = response.Body or response.body
            if status >= 200 and status < 300 and type(body) == "string" and #body > 0 then
                return true, body
            end
        end
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)

    if ok and type(body) == "string" and #body > 0 then
        return true, body
    end

    return false, tostring(body or "HTTP request failed")
end

notify("Nova Hub", "Loading universal build...")

local source = {}

for i, name in ipairs(PARTS) do
    local ok, body = fetch(BASE .. name)

    if not ok then
        notify("Nova Hub Error", "Failed to download part " .. i)
        error("Nova Hub failed to download: " .. name .. "\n" .. tostring(body))
    end

    if body:find("<!DOCTYPE html", 1, true)
        or body:find("<html", 1, true)
        or body:find("404: Not Found", 1, true) then
        notify("Nova Hub Error", "GitHub returned an error for part " .. i)
        error("Invalid GitHub response for " .. name)
    end

    source[#source + 1] = body
end

notify("Nova Hub", "All parts loaded. Starting...")

local completeSource = table.concat(source, "\n")
local chunk, compileError = loadstring(completeSource)

if type(chunk) ~= "function" then
    notify("Nova Hub Error", "Compilation failed")
    error("Nova Hub compilation failed: " .. tostring(compileError))
end

return chunk()
