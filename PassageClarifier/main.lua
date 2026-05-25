local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local Event = require("ui/event")
local util = require("util")
local _ = require("gettext")

local ok_json, json = pcall(require, "json")
local ok_https, https = pcall(require, "ssl.https")
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
    self:registerDictButton()
end

function PassageClarifier:onReaderReady()
    self:registerHighlightButton()
    self:registerDictButton()
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

local function get_dict_lookup_text(dict_widget)
    if dict_widget.highlight and dict_widget.highlight.selected_text and dict_widget.highlight.selected_text.text then
        return clean_text(dict_widget.highlight.selected_text.text)
    end
    if dict_widget.word then return clean_text(dict_widget.word) end
    if dict_widget.lookupword then return clean_text(dict_widget.lookupword) end
    if dict_widget.displayword then return clean_text(dict_widget.displayword) end
    return ""
end

local function layout_contains_button(layout, button_id)
    if not layout then return false end
    for _, row in ipairs(layout) do
        for _, id in ipairs(row) do
            if id == button_id then return true end
        end
    end
    return false
end

local function insert_dict_button(layout, button_id)
    if not layout or layout_contains_button(layout, button_id) then return false end
    for _, row in ipairs(layout) do
        if layout_contains_button({ row }, "wikipedia") or layout_contains_button({ row }, "search") then
            table.insert(row, #row, button_id)
            return true
        end
    end
    table.insert(layout, { button_id })
    return true
end

function PassageClarifier:registerDictButton()
    if self._dict_button_registered then return end
    if not self.ui or not self.ui.dictionary or not self.ui.dictionary.addToDictButtons then return end

    self.ui.dictionary:addToDictButtons({
        id = "clarify",
        menu_text = _("Clarify"),
        text = _("Clarify"),
        callback = function(dict_widget)
            local selected = get_dict_lookup_text(dict_widget)
            dict_widget:onClose(true)
            self:clarify(selected)
        end,
    })

    -- Put Clarify beside the built-in dictionary actions on default layouts.
    insert_dict_button(self.ui.dictionary.default_layout, "clarify")

    -- If the user has customized dictionary buttons, update that saved layout too.
    if G_reader_settings then
        local config = G_reader_settings:readSetting("dict_button_config")
        if config and insert_dict_button(config.layout, "clarify") then
            config.order = config.order or {}
            local in_order = false
            for _, id in ipairs(config.order) do
                if id == "clarify" then
                    in_order = true
                    break
                end
            end
            if not in_order then
                table.insert(config.order, "clarify")
            end
            config.row_count = config.row_count or {}
            for i, row in ipairs(config.layout) do
                config.row_count[i] = config.row_count[i] or #row
            end
            G_reader_settings:saveSetting("dict_button_config", config)
        end
    end

    self._dict_button_registered = true
end

-- DictQuickLookup emits DictButtonsReady before drawing the dictionary popup.
-- This adds Clarify to the dictionary popup shown after a word lookup.
function PassageClarifier:onDictButtonsReady(dict_widget, buttons)
    if not dict_widget or not buttons then return end

    table.insert(buttons, 2, {
        {
            id = "clarify",
            text = _("Clarify"),
            callback = function()
                local selected = get_dict_lookup_text(dict_widget)
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

    if not ok_json or not ok_ltn12 then
        UIManager:show(InfoMessage:new{ text = _("Missing JSON or LTN12 library in this KOReader build.") })
        return
    end

    if not ok_https then
        UIManager:show(InfoMessage:new{ text = _("Missing HTTPS library in this KOReader build.") })
        return
    end

    local settings = read_settings()
    local api_key = settings.api_key
    if not api_key or api_key == "" or api_key == "PASTE_OPENAI_API_KEY_HERE" then
        UIManager:show(InfoMessage:new{ text = _("Add your OpenAI API key in passageclarifier.koplugin/settings.lua") })
        return
    end

    local loading_message = InfoMessage:new{ text = _("Clarifying selected passage...") }
    UIManager:show(loading_message)

    UIManager:scheduleIn(0.1, function()
        local function close_loading_message()
            if loading_message then
                UIManager:close(loading_message)
                loading_message = nil
            end
        end

        local prompt = table.concat({
            "Clarify this selected passage for a modern reader.",
            "",
            "Your goal is to make the text fully understandable without oversimplifying the meaning or tone.",
            "",
            "Rules:",
            "- Explain the passage in plain modern English.",
            "- Be explicit about what the passage literally means.",
            "- Explain what is implied, emotionally suggested, or indirectly communicated.",
            "- Identify archaic wording, uncommon vocabulary, idioms, sayings, symbolism, euphemism, irony, or figurative language.",
            "- Define unusual terms directly in context.",
            "- Preserve nuance and ambiguity when intentional.",
            "- Do not analyze grammar or sentence structure.",
            "- Do not discuss writing quality unless necessary for understanding.",
            "- Do not spoil beyond the selected passage.",
            "- Keep the total response under 500 tokens.",
            "- Prioritize the most important clarifications if space is limited.",
            "- Be concise when the meaning is straightforward.",
            "- Be more expressive only when the passage is emotionally dense or abstract.",
            "",
            "Use only relevant sections from:",
            "1. Literal meaning",
            "2. Implied meaning",
            "3. Archaic or unusual wording",
            "",
            "Selected passage:",
            selected_text,
        }, "\n")

        local payload = json.encode({
            model = settings.model or "gpt-4.1-mini",
            max_output_tokens = settings.max_output_tokens or 500,
            input = prompt,
        })

        local chunks = {}
        local ok_req, code, headers, status = https.request{
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
            close_loading_message()
            UIManager:show(TextViewer:new{
                title = _("Clarify error"),
                text = "Request failed.\n\nStatus: " .. tostring(status or code) .. "\n\n" .. body,
            })
            return
        end

        local ok_decode, decoded = pcall(json.decode, body)
        if not ok_decode then
            close_loading_message()
            UIManager:show(TextViewer:new{ title = _("Clarify error"), text = "Could not decode API response.\n\n" .. body })
            return
        end

        close_loading_message()
        UIManager:show(TextViewer:new{
            title = _("Clarification"),
            text = extract_output_text(decoded) or "No explanation returned.",
        })
    end)
end

return PassageClarifier
