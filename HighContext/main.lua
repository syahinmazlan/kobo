local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AIHelper = require("HighContext.aihelper")

local HighContext = WidgetContainer:extend{
    name = "highcontext",
}

function HighContext:onDispatcherRegisterActions()
    Dispatcher:registerAction("highcontext_summarize_page", {
        category = "none",
        event = "HighContextSummarizePage",
        title = _("HighContext: summarize page"),
        general = true,
    })
    Dispatcher:registerAction("highcontext_settings", {
        category = "none",
        event = "HighContextSettings",
        title = _("HighContext: settings"),
        general = true,
    })
end

function HighContext:init()
    self:onDispatcherRegisterActions()
    self.settings = G_reader_settings:readSetting("highcontext_settings", {
        api_key = "",
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
                text = _("Set API key"),
                callback = function() self:openApiKeyDialog() end,
            },
        },
    }
end

function HighContext:getCurrentPageText()
    if not self.ui or not self.ui.document then
        return nil
    end
    local ok_page, page = pcall(function() return self.ui:getCurrentPage() end)
    if not ok_page or type(page) ~= "number" then
        return nil
    end
    local ok_text, text = pcall(function() return self.ui.document:getPageText(page) end)
    if ok_text and type(text) == "string" and text ~= "" then
        return text
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

    local progress = InfoMessage:new{ text = _("HighContext: generating summary...") }
    UIManager:show(progress)
    local ok, result = AIHelper.generate_summary(self.settings, page_text)
    UIManager:close(progress)

    UIManager:show(InfoMessage:new{
        text = ok and result or (_("HighContext failed: ") .. result),
        timeout = 8,
    })
end

function HighContext:openApiKeyDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Enter API key"),
        input = self.settings.api_key or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        self.settings.api_key = dialog:getInputText()
                        G_reader_settings:saveSetting("highcontext_settings", self.settings)
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return HighContext
