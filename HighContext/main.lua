local _plugin_dir = (debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or ".") .. "/"

if not package.path:find(_plugin_dir, 1, true) then
    package.path = _plugin_dir .. "?.lua;" .. package.path
end

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AIHelper = require("aihelper")

local HighContext = WidgetContainer:extend{
    name = "highcontext",
}

local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function read_api_key_from_file(path)
    if not path or path == "" then
        return nil
    end
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return trim(content) ~= "" and trim(content) or nil
end

function HighContext:onDispatcherRegisterActions()
    Dispatcher:registerAction("highcontext_summarize_page", {
        category = "none",
        event = "HighContextSummarizePage",
        title = _("HighContext: summarize page"),
        general = true,
    })
end

function HighContext:init()
    self:onDispatcherRegisterActions()
    self.settings = G_reader_settings:readSetting("highcontext_settings", {
        api_key = "",
        api_key_file = _plugin_dir .. "api_key.txt",
        endpoint = "https://api.openai.com/v1/chat/completions",
        model = "gpt-4o-mini",
        system_prompt = "Summarize the text with concise bullet points and key context.",
    })
    self.ui.menu:registerToMainMenu(self)
end

function HighContext:addToMainMenu(menu_items)
    menu_items.highcontext = {
        text = _("HighContext"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Summarize current page"),
                callback = function() self:onHighContextSummarizePage() end,
            },
            {
                text = _("API key file info"),
                callback = function() self:showApiKeyFileInfo() end,
            },
        },
    }
end

function HighContext:showApiKeyFileInfo()
    local path = self.settings.api_key_file or (_plugin_dir .. "api_key.txt")
    UIManager:show(InfoMessage:new{
        text = _("Place your API key in: ") .. path,
        timeout = 6,
    })
end

function HighContext:getCurrentPageText()
    if not self.ui or not self.ui.document then
        return nil
    end
    local ok_page, page = pcall(function() return self.ui:getCurrentPage() end)
    if not ok_page or type(page) ~= "number" then
        return nil
    end

    if self.ui.document.getPageText then
        local ok_text, text = pcall(function() return self.ui.document:getPageText(page) end)
        if ok_text and type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

function HighContext:onHighContextSummarizePage()
    local page_text = self:getCurrentPageText()
    if not page_text then
        UIManager:show(InfoMessage:new{
            text = _("Could not read page text for this document/backend."),
            timeout = 3,
        })
        return
    end

    local runtime_settings = {}
    for k, v in pairs(self.settings) do
        runtime_settings[k] = v
    end

    local key_from_file = read_api_key_from_file(self.settings.api_key_file)
    runtime_settings.api_key = key_from_file or self.settings.api_key

    local progress = InfoMessage:new{ text = _("HighContext: generating summary...") }
    UIManager:show(progress)
    local ok, result = AIHelper.generate_summary(runtime_settings, page_text)
    UIManager:close(progress)

    UIManager:show(InfoMessage:new{
        text = ok and result or (_("HighContext failed: ") .. result),
        timeout = 8,
    })
end

function HighContext:onHighContextSummarizePageAction()
    self:onHighContextSummarizePage()
end

return HighContext
