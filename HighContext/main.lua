-- HighContext Plugin for KOReader v1.0.0
-- Simplifies complex, long-winded, or archaic selected text using ChatGPT API

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")
local logger = require("logger")
local Screen = require("device").screen

local HighContextPlugin = WidgetContainer:new{
    name = "highcontext",
    is_doc_only = true,
}

function HighContextPlugin:init()
    self:onDispatcherRegisterActions()
    logger.info("HighContextPlugin: Initialized successfully.")
end

function HighContextPlugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("analyze_text_context", {
        category = "none",
        event = "AnalyzeSelectedText",
        title = "Explain with AI Context",
        general = true,
    })
end

-- Hook into KOReader's text selection menu
function HighContextPlugin:addToSelectionMenu(menu_items)
    table.insert(menu_items, {
        text = "Explain with AI Context",
        callback = function()
            local selected_text = self.view.highlight:getSelectionText()
            if selected_text and #selected_text > 0 then
                self:processTextAnalysis(selected_text)
            else
                UIManager:show(InfoMessage:new{text = "No text selected!", timeout = 2})
            end
        end
    })
end

-- Extracts all visible text from the current page viewport
function HighContextPlugin:getCurrentPageText()
    if not self.ui or not self.ui.document then return "" end
    
    local page_text = ""
    pcall(function()
        -- Safely extract text from the active visible page layout structure
        local current_page = self.ui:getCurrentPage()
        page_text = self.ui.document:getPageText(current_page)
    end)
    
    return type(page_text) == "string" and page_text or ""
end

function HighContextPlugin:processTextAnalysis(highlighted_text)
    local NetworkMgr = require("ui/network/manager")
    
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = "Network is offline. Please turn on Wi-Fi to use AI translation.",
            timeout = 4,
        })
        return
    end

    local page_context = self.getCurrentPageText()
    
    -- Load helper module or use current existing configurations
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init()
    end
    
    local wait_msg = InfoMessage:new{
        text = "Sending fragment to ChatGPT...\nAnalyzing sentence structures and full-page layout.",
        timeout = 30,
    }
    UIManager:show(wait_msg)
    
    -- Schedule execution safely into the main event loop
    UIManager:scheduleIn(0.1, function()
        local result, err = self.ai_helper:analyzeFragment(highlighted_text, page_context)
        UIManager:close(wait_msg)
        
        if not result then
            UIManager:show(InfoMessage:new{
                text = "AI Query Failed:\n" .. (err or "Unknown API Error"),
                timeout = 5,
            })
            return
        end
        
        -- Display rich explanation inside an overlay scroll panel
        local explanation_viewer = TextViewer:new{
            title = "AI Explains:",
            text = result,
            width = Screen:getWidth() * 0.9,
            height = Screen:getHeight() * 0.85,
            is_borderless = false,
        }
        UIManager:show(explanation_viewer)
    end)
end

function HighContextPlugin:onAnalyzeSelectedText()
    local selected_text = self.view.highlight:getSelectionText()
    if selected_text then self:processTextAnalysis(selected_text) end
    return true
end

return HighContextPlugin
