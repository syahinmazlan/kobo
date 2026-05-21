-- HighContext API Helper for KOReader
local Http = require("socket.http")
local LTN12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")

local AIHelper = {
    api_key = "", -- Paste your fallback sk-proj-... token here or configure via settings
    model = "gpt-5.4-mini", -- Upgraded to the fast, low-cost flagship mini tier
    endpoint = "https://api.openai.com/v1/chat/completions"
}

function AIHelper:init()
    -- Sync existing settings from your primary configurations setup if needed
    -- self.api_key = G_reader_settings:readSetting("chatgpt_key")
end

function AIHelper:analyzeFragment(highlight, context)
    if not self.api_key or self.api_key == "" then
        return nil, "Missing API Key configuration. Configure Key under Settings first."
    end

    local system_prompt = "You are a literary assistant running on an e-reader device. " ..
                          "Your task is to decode and explain complex paragraphs, archaic phrasing, " ..
                          "or long-winded sentences. Break down the core meaning simply and concisely."

    local user_prompt = string.format(
        "--- START PAGE CONTEXT ---\n%s\n--- END PAGE CONTEXT ---\n\n" ..
        "Target selection to evaluate: \"%s\"\n\n" ..
        "Instructions: Using the provided Page Context for perspective and pronouns resolution, " ..
        "explain exactly what the Target Selection means. Do not repeat empty text. Keep it highly legible.",
        context, highlight
    )

    local request_body = JSON.encode({
        model = self.model,
        messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = user_prompt }
        },
        temperature = 0.3
    })

    local response_chunks = {}
    local _, status_code, response_headers = Http.request({
        url = self.endpoint,
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. self.api_key,
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = LTN12.source.string(request_body),
        sink = LTN12.sink.table(response_chunks)
    })

    if status_code ~= 200 then
        logger.error("HighContext API Failure:", status_code)
        return nil, "HTTP Error Status " .. tostring(status_code)
    end

    local response_string = table.concat(response_chunks)
    local decoded_json = JSON.decode(response_string)
    
    if decoded_json and decoded_json.choices and decoded_json.choices[1] then
        return decoded_json.choices[1].message.content
    end

    return nil, "Malformed JSON schema response received from API endpoints."
end

return AIHelper