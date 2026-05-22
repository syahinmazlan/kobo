local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local Event = require("ui/event")
local util = require("util")
local _ = require("gettext")

local ok_json, json = pcall(require, "json")
local ok_http, http = pcall(require, "socket.http")
local ok_ltn12, ltn12 = pcall(require, "ltn12")

local PassageClarifier = WidgetContainer:extend{
    name = "passageclarifier",
    is_doc_only = true,
}

local function plugin_dir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*[/\\])") or "plugins/passageclarifier.koplugin/"
end

local function read_settings()
    local ok, settings = pcall(dofile, plugin_dir() .. "settings.lua")
    if ok and type(settings) == "table" then
        return settings
    end
    return {}
end

local function clean_text(text)
    if not text then return "" end
    local ok, cleaned = pcall(util.cleanupSelectedText, text)
    if ok and cleaned then return cleaned end
    return tostring(text):gsub("%s+", " ")
end

local function extract_output_text(response)
    if type(response) ~= "table" then return nil end
    if response.output_text then return response.output_text end
    if type(response.output) == "table" then
        local parts = {}
        for _, item in ipairs(response.output) do
            if type(item.content) == "table" then
                for _, content in ipairs(item.content) do
                    if content.text then
                        table.insert(parts, content.text)
                    end
                end
            end
        end
        if #parts > 0 then return table.concat(parts, "\n") end
    end
    if response.error and response.error.message then
        return "OpenAI API error: " .. response.error.message
    end
    return nil
end

function PassageClarifier:init()
    self:registerHighlightButton()
end

function PassageClarifier:onReaderReady()
    self:registerHighlightButton()
end

function PassageClarifier:registerHighlightButton()
    if self._highlight_button_registered then return end
    if not self.ui or not self.ui.highlight or not self.ui.highlight.addToHighlightDialog then return end

    self.ui.highlight:addToHighlightDialog("08_clarify", function(highlight)
        return {
            text = _("Clarify"),
            callback = function()
                local selected = ""
                if highlight.selected_text and highlight.selected_text.text then
                    selected = clean_text(highlight.selected_text.text)
                end
                highlight:onClose(true)
                self:clarify(selected)
            end,
        }
    end)
    self._highlight_button_registered = true
end

-- DictQuickLookup emits DictButtonsReady before drawing the dictionary popup.
-- This adds Clarify to the dictionary popup shown after a word lookup.
function PassageClarifier:onDictButtonsReady(dict_widget, buttons)
    if not dict_widget or not buttons then return end

    local function get_selected_text()
        if dict_widget.highlight and dict_widget.highlight.selected_text and dict_widget.highlight.selected_text.text then
            return clean_text(dict_widget.highlight.selected_text.text)
        end
        if dict_widget.word then return clean_text(dict_widget.word) end
        if dict_widget.lookupword then return clean_text(dict_widget.lookupword) end
        if dict_widget.displayword then return clean_text(dict_widget.displayword) end
        return ""
    end

    table.insert(buttons, 2, {
        {
            id = "clarify",
            text = _("Clarify"),
            callback = function()
                local selected = get_selected_text()
                dict_widget:onClose(true)
                self:clarify(selected)
            end,
        },
    })
end

function PassageClarifier:clarify(selected_text)
    selected_text = clean_text(selected_text)
    if selected_text == "" then
        UIManager:show(InfoMessage:new{ text = _("No text selected.") })
        return
    end

    if not ok_json or not ok_http or not ok_ltn12 then
        UIManager:show(InfoMessage:new{ text = _("Missing JSON or HTTP library in this KOReader build.") })
        return
    end

    local settings = read_settings()
    local api_key = settings.api_key
    if not api_key or api_key == "" or api_key == "PASTE_OPENAI_API_KEY_HERE" then
        UIManager:show(InfoMessage:new{ text = _("Add your OpenAI API key in passageclarifier.koplugin/settings.lua") })
        return
    end

    UIManager:show(InfoMessage:new{ text = _("Clarifying selected passage...") })

    UIManager:scheduleIn(0.1, function()
        local prompt = table.concat({
            "Clarify this selected passage for a reader.",
            "Use these sections only:",
            "1. Literal meaning",
            "2. Archaic or unusual wording",
            "3. Implied meaning",
            "4. Non-literal language",
            "Do not include sentence structure analysis or grammar analysis.",
            "Do not spoil beyond the selected text. Use plain English. Be concise.",
            "Selected passage:",
            selected_text,
        }, "\n")

        local payload = json.encode({
            model = settings.model or "gpt-4.1-mini",
            max_output_tokens = settings.max_output_tokens or 500,
            input = prompt,
        })

        local chunks = {}
        local ok_req, code, headers, status = http.request{
            url = "https://api.openai.com/v1/responses",
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. api_key,
                ["Content-Length"] = tostring(#payload),
            },
            source = ltn12.source.string(payload),
            sink = ltn12.sink.table(chunks),
        }

        local body = table.concat(chunks)
        if not ok_req or tonumber(code) ~= 200 then
            UIManager:show(TextViewer:new{
                title = _("Clarify error"),
                text = "Request failed.\n\nStatus: " .. tostring(status or code) .. "\n\n" .. body,
            })
            return
        end

        local ok_decode, decoded = pcall(json.decode, body)
        if not ok_decode then
            UIManager:show(TextViewer:new{ title = _("Clarify error"), text = "Could not decode API response.\n\n" .. body })
            return
        end

        UIManager:show(TextViewer:new{
            title = _("Clarification"),
            text = extract_output_text(decoded) or "No explanation returned.",
        })
    end)
end

return PassageClarifier
