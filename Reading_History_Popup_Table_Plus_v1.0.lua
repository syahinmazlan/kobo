--[[
Reading History Popup Table Plus
Version: 2.11.1 (full title header and cleaner pace view)

Notes:
- Keeps the visual layout of the user's preferred version
- Config dialog lets user choose:
  * Daily mode
  * Session mode with 30 / 45 / 60 min cutoff
- Preference is saved in G_reader_settings
]]--

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local LineWidget = require("ui/widget/linewidget")
local SQ3 = require("lua-ljsqlite3/init")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local gettext = require("gettext")
local ReaderUI = require("apps/reader/readerui")

local PATCH_L10N = {
    en = {
        ["DATE"] = "DATE",
        ["TIME"] = "TIME",
        ["PAGES"] = "PAGES",
        ["SPEED"] = "SPEED",
        ["DELTA"] = "ΔPROG",
        ["TOTAL"] = "TOTAL",
        ["RANGE"] = "RANGE",
        ["Days Read"] = "days reading",
        ["reading in this session"] = "reading in this session",
        ["Book total"] = "Book total",
        ["Streak"] = "Streak",
        ["Visible period"] = "Visible period",
        ["Visible sessions"] = "Visible sessions",
        ["Summary"] = "Summary",
        ["pages/h"] = "pages/h",
        ["days"] = "days",
        ["Mode"] = "Mode",
        ["daily"] = "daily",
        ["sessions (30m cutoff)"] = "sessions (30m cutoff)",
        ["sessions (45m cutoff)"] = "sessions (45m cutoff)",
        ["sessions (60m cutoff)"] = "sessions (60m cutoff)",
        ["Config"] = "[Config]",
        ["Select mode"] = "Select mode",
        ["Daily view"] = "Daily view",
        ["Sessions 30m"] = "Sessions 30m",
        ["Sessions 45m"] = "Sessions 45m",
        ["Sessions 60m"] = "Sessions 60m",
        ["No data"] = "No data",
        ["avg"] = "avg",
        ["min"] = "min",
        ["max"] = "max",
        ["early"] = "early",
        ["late"] = "late",
    }
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

local stats_db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local ROWS_PER_PAGE = 6
local SPEED_MIN_DURATION_SECONDS = 120
local SPEED_MIN_PAGES = 3
local _current_page = 1

local function getMode()
    if G_reader_settings and G_reader_settings.readSetting then
        return G_reader_settings:readSetting("reading_stats_mode") or "daily"
    end
    return "daily"
end

local function setMode(mode)
    if G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting("reading_stats_mode", mode)
    end
end

local function getSessionGapSeconds()
    local mode = getMode()
    if mode == "sessions_45" then
        return 45 * 60
    elseif mode == "sessions_60" then
        return 60 * 60
    else
        return 30 * 60
    end
end

local function modeLabel(mode)
    if mode == "sessions_30" then return _("sessions (30m cutoff)") end
    if mode == "sessions_45" then return _("sessions (45m cutoff)") end
    if mode == "sessions_60" then return _("sessions (60m cutoff)") end
    return _("daily")
end

local function truncateTitle(title, max_chars)
    if not title then return "" end
    if #title > max_chars then
        return title:sub(1, max_chars - 3) .. "..."
    end
    return title
end


local function wrapTitle(title, max_chars_per_line, max_lines)
    if not title then return "" end
    max_chars_per_line = max_chars_per_line or 28
    max_lines = max_lines or 2

    local words = {}
    for w in tostring(title):gmatch("%S+") do
        table.insert(words, w)
    end
    if #words == 0 then return "" end

    local lines = {}
    local current = ""
    for _, w in ipairs(words) do
        local candidate = (current == "") and w or (current .. " " .. w)
        if #candidate <= max_chars_per_line then
            current = candidate
        else
            if current ~= "" then
                table.insert(lines, current)
            end
            current = w
            if #lines >= max_lines - 1 then
                break
            end
        end
    end
    if current ~= "" and #lines < max_lines then
        table.insert(lines, current)
    end

    local used_words = 0
    for _, line in ipairs(lines) do
        for _ in line:gmatch("%S+") do
            used_words = used_words + 1
        end
    end
    if used_words < #words and #lines > 0 then
        lines[#lines] = lines[#lines] .. "..."
    end

    return table.concat(lines, "\n")
end

local function formatDate(iso_date)
    local year, month, day = iso_date:match("(%d+)-(%d+)-(%d+)")
    if year then
        local yy = year:sub(-2)
        return string.format("%s/%s/%s", day, month, yy)
    end
    return iso_date
end

local function formatSeconds(seconds)
    if not seconds or seconds <= 0 then
        return "0m 0s"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    else
        return string.format("%dm %ds", minutes, secs)
    end
end

local function formatDurationCompact(seconds)
    if not seconds or seconds <= 0 then
        return "0m"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

local function formatProgressDelta(delta)
    local value = tonumber(delta) or 0
    return string.format("%+.1f%%", value * 100)
end

local function formatProgressTotal(progress)
    local value = tonumber(progress) or 0
    return string.format("%.1f%%", value * 100)
end

local function formatSpeed(pages, duration)
    if not pages or pages < SPEED_MIN_PAGES or not duration or duration < SPEED_MIN_DURATION_SECONDS then
        return "-"
    end
    local pph = (pages * 3600) / duration
    return string.format("%.0f", pph)
end

local function formatRange(first_page, last_page)
    if first_page == nil and last_page == nil then
        return "-"
    end
    first_page = tonumber(first_page)
    last_page = tonumber(last_page)
    if first_page and last_page then
        if first_page == last_page then
            return tostring(first_page)
        end
        return string.format("%d-%d", first_page, last_page)
    elseif first_page then
        return tostring(first_page)
    elseif last_page then
        return tostring(last_page)
    end
    return "-"
end

local function daysBetweenISO(d1, d2)
    local y1, m1, da1 = d1:match("(%d+)-(%d+)-(%d+)")
    local y2, m2, da2 = d2:match("(%d+)-(%d+)-(%d+)")
    if not y1 or not y2 then return nil end
    local t1 = os.time({year=tonumber(y1), month=tonumber(m1), day=tonumber(da1), hour=12})
    local t2 = os.time({year=tonumber(y2), month=tonumber(m2), day=tonumber(da2), hour=12})
    return math.floor((t1 - t2) / 86400)
end

local function getDB()
    return SQ3.open(stats_db_path)
end

local function getDailyStats(book_id, days)
    if not book_id or not days or days <= 0 then return {} end
    local conn = getDB()
    if not conn then return {} end

    local sql = string.format([[
        SELECT
            date(ps.start_time, 'unixepoch', 'localtime') AS dates,
            count(DISTINCT ps.page) AS pages,
            sum(ps.duration) AS durations,
            (SELECT ps2.page
             FROM page_stat_data ps2
             WHERE ps2.id_book = ps.id_book
               AND date(ps2.start_time, 'unixepoch', 'localtime') = date(ps.start_time, 'unixepoch', 'localtime')
             ORDER BY ps2.start_time ASC
             LIMIT 1) AS first_page,
            (SELECT ps3.page
             FROM page_stat_data ps3
             WHERE ps3.id_book = ps.id_book
               AND date(ps3.start_time, 'unixepoch', 'localtime') = date(ps.start_time, 'unixepoch', 'localtime')
             ORDER BY ps3.start_time DESC
             LIMIT 1) AS last_page,
            (SELECT (ps4.page * 1.0 / ps4.total_pages)
             FROM page_stat_data ps4
             WHERE ps4.id_book = ps.id_book
               AND date(ps4.start_time, 'unixepoch', 'localtime') = date(ps.start_time, 'unixepoch', 'localtime')
             ORDER BY ps4.start_time DESC
             LIMIT 1) AS total_percentage
        FROM page_stat_data ps
        WHERE ps.id_book = %d
          AND date(ps.start_time, 'unixepoch', 'localtime') >= date('now', '-' || %d || ' days')
        GROUP BY date(ps.start_time, 'unixepoch', 'localtime')
        ORDER BY dates DESC;
    ]], book_id, days)

    local results = conn:exec(sql)
    conn:close()

    local stats = {}
    if results and results.dates then
        for i = 1, #results.dates do
            table.insert(stats, {
                date = results.dates[i],
                pages = tonumber(results.pages[i]) or 0,
                duration = tonumber(results.durations[i]) or 0,
                first_page = tonumber(results.first_page[i]),
                last_page = tonumber(results.last_page[i]),
                progress = tonumber(results.total_percentage[i]) or 0,
                delta_progress = 0,
            })
        end
    end

    for i = 1, #stats do
        local older = stats[i + 1]
        if older then
            stats[i].delta_progress = (stats[i].progress or 0) - (older.progress or 0)
        else
            stats[i].delta_progress = stats[i].progress or 0
        end
    end

    return stats
end

local function getRawReadingRows(book_id, days)
    if not book_id or not days or days <= 0 then return {} end
    local conn = getDB()
    if not conn then return {} end

    local sql = string.format([[
        SELECT
            ps.start_time AS start_time,
            date(ps.start_time, 'unixepoch', 'localtime') AS dates,
            ps.page AS page,
            ps.duration AS duration,
            ps.total_pages AS total_pages
        FROM page_stat_data ps
        WHERE ps.id_book = %d
          AND date(ps.start_time, 'unixepoch', 'localtime') >= date('now', '-' || %d || ' days')
        ORDER BY ps.start_time ASC;
    ]], book_id, days)

    local results = conn:exec(sql)
    conn:close()

    local rows = {}
    if results and results.start_time then
        for i = 1, #results.start_time do
            table.insert(rows, {
                start_time = tonumber(results.start_time[i]) or 0,
                date = results.dates[i],
                page = tonumber(results.page[i]) or 0,
                duration = tonumber(results.duration[i]) or 0,
                total_pages = tonumber(results.total_pages[i]) or 0,
            })
        end
    end
    return rows
end

local function getSessionStats(book_id, days, gap_seconds)
    local rows = getRawReadingRows(book_id, days)
    if #rows == 0 then return {} end

    local sessions = {}
    local current = nil

    local function finalizeSession(sess)
        if not sess then return end
        local seen = {}
        local page_count = 0
        for _, page in ipairs(sess._pages_seen or {}) do
            if not seen[page] then
                seen[page] = true
                page_count = page_count + 1
            end
        end
        sess.pages = page_count
        sess._pages_seen = nil
        table.insert(sessions, sess)
    end

    for _, row in ipairs(rows) do
        local start_new_session = false
        if not current then
            start_new_session = true
        else
            local gap = row.start_time - (current.last_time or row.start_time)
            if row.date ~= current.date or gap > gap_seconds then
                start_new_session = true
            end
        end

        if start_new_session then
            finalizeSession(current)
            current = {
                date = row.date,
                first_page = row.page,
                last_page = row.page,
                duration = 0,
                progress = 0,
                delta_progress = 0,
                last_time = row.start_time,
                _pages_seen = {},
            }
        end

        current.last_time = row.start_time
        current.last_page = row.page
        current.duration = current.duration + (row.duration or 0)
        table.insert(current._pages_seen, row.page)

        if row.total_pages and row.total_pages > 0 then
            current.progress = row.page / row.total_pages
        end
    end

    finalizeSession(current)

    local out = {}
    for i = #sessions, 1, -1 do
        table.insert(out, sessions[i])
    end

    for i = 1, #out do
        local older = out[i + 1]
        if older then
            out[i].delta_progress = (out[i].progress or 0) - (older.progress or 0)
        else
            out[i].delta_progress = out[i].progress or 0
        end
    end

    return out
end

local function getCurrentSessionDuration(book_id, start_current_period)
    if not book_id or not start_current_period then return 0 end
    local conn = getDB()
    if not conn then return 0 end

    local sql_stmt = [[
        SELECT count(*),
               sum(sum_duration)
        FROM (
            SELECT sum(duration) AS sum_duration
            FROM page_stat
            WHERE start_time >= %d
            GROUP BY id_book, page
        );
    ]]
    local _, current_duration = conn:rowexec(string.format(sql_stmt, start_current_period))
    conn:close()

    if current_duration == nil then
        current_duration = 0
    end
    return tonumber(current_duration) or 0
end

local function getBookTitle(ui)
    if not ui then return "" end
    local book_title = ui.doc_props and ui.doc_props.display_title or ""
    local colon_pos = book_title:find(":")
    if colon_pos then
        book_title = book_title:sub(1, colon_pos - 1)
    end
    return book_title
end

local function getTotalDaysRead(book_id)
    if not book_id then return 0 end
    local conn = getDB()
    if not conn then return 0 end
    local sql = string.format([[
        SELECT count(DISTINCT date(ps.start_time, 'unixepoch', 'localtime'))
        FROM page_stat_data ps
        WHERE ps.id_book = %d;
    ]], book_id)
    local result = conn:rowexec(sql)
    conn:close()
    return tonumber(result) or 0
end

local function sumDuration(stats)
    local total = 0
    for _, row in ipairs(stats or {}) do
        total = total + (tonumber(row.duration) or 0)
    end
    return total
end

local function sumPages(stats)
    local total = 0
    for _, row in ipairs(stats or {}) do
        total = total + (tonumber(row.pages) or 0)
    end
    return total
end

local function sumDelta(stats)
    local total = 0
    for _, row in ipairs(stats or {}) do
        total = total + (tonumber(row.delta_progress) or 0)
    end
    return total
end

local function getStreak(stats)
    if not stats or #stats == 0 then return 0 end
    local streak = 1
    for i = 1, #stats - 1 do
        local diff = daysBetweenISO(stats[i].date, stats[i + 1].date)
        if diff == 1 then
            streak = streak + 1
        else
            break
        end
    end
    return streak
end

local function fixedCol(widget, width)
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = widget:getSize().h },
        widget,
    }
end

local function buildColumnSeparator(column_gap, height)
    local v_padding = Size.padding.small
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = column_gap },
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ height = v_padding },
            LineWidget:new{
                dimen = Geom:new{ w = Size.line.thin, h = height - 2 * v_padding },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
            VerticalSpan:new{ height = v_padding },
        },
        HorizontalSpan:new{ width = column_gap },
    }
end

local function buildRowSeparator(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Size.line.thin },
        background = Blitbuffer.COLOR_LIGHT_GRAY,
    }
end

local function buildLayout(screen_w, padding_h, column_gap)
    local col_count = 7
    local col_width = math.floor((screen_w - 2 * padding_h - (col_count - 1) * 2 * column_gap) / col_count)
    return {
        full_width = screen_w,
        padding_h = padding_h,
        column_gap = column_gap,
        col_width = col_width,
    }
end

local function buildTableHeader(fonts, layout)
    local headers = { _("DATE"), _("TIME"), _("PAGES"), _("SPEED"), _("DELTA"), _("TOTAL"), _("RANGE") }
    local header_row = HorizontalGroup:new{ align = "center" }
    for i, header_text in ipairs(headers) do
        local header_widget = TextWidget:new{ text = header_text, face = fonts.header }
        table.insert(header_row, fixedCol(header_widget, layout.col_width))
        if i < #headers then
            table.insert(header_row, buildColumnSeparator(layout.column_gap, 24))
        end
    end
    return FrameContainer:new{
        background = Blitbuffer.COLOR_GRAY_E,
        bordersize = 0,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left = layout.padding_h,
        padding_right = layout.padding_h,
        header_row,
    }
end

local function buildTableRows(stats_data, fonts, layout)
    local rows = VerticalGroup:new{ align = "left" }
    for idx, item in ipairs(stats_data) do
        local date_widget = TextWidget:new{ text = formatDate(item.date), face = fonts.cell }
        local time_widget = TextWidget:new{ text = formatDurationCompact(item.duration), face = fonts.cell }
        local pages_widget = TextWidget:new{ text = tostring(item.pages), face = fonts.cell }
        local speed_widget = TextWidget:new{ text = formatSpeed(item.pages, item.duration), face = fonts.cell }
        local delta_widget = TextWidget:new{ text = formatProgressDelta(item.delta_progress), face = fonts.cell }
        local total_widget = TextWidget:new{ text = formatProgressTotal(item.progress), face = fonts.cell }
        local range_widget = TextWidget:new{ text = formatRange(item.first_page, item.last_page), face = fonts.cell }

        local row = HorizontalGroup:new{
            align = "center",
            fixedCol(date_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(time_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(pages_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(speed_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(delta_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(total_widget, layout.col_width),
            buildColumnSeparator(layout.column_gap, 22),
            fixedCol(range_widget, layout.col_width),
        }

        table.insert(rows, row)
        if idx < #stats_data then
            table.insert(rows, VerticalSpan:new{ height = Size.padding.tiny or 2 })
            table.insert(rows, buildRowSeparator(layout.full_width - 2 * layout.padding_h))
            table.insert(rows, VerticalSpan:new{ height = Size.padding.tiny or 2 })
        end
    end
    return rows
end

local function buildPaginationBar(fonts, layout, current_page, total_pages)
    local bar_h  = Screen:scaleBySize(44)
    local full_w = layout.full_width
    local can_prev = current_page > 1
    local can_next = current_page < total_pages
    local zone_w = math.floor(full_w / 5)
    local lbl_w  = full_w - zone_w * 4

    local function makeZone(label, enabled, w)
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = bar_h },
            TextWidget:new{
                text = label,
                face = enabled and fonts.cell or fonts.header,
            },
        }
    end

    local function makeSep()
        return LineWidget:new{
            dimen = Geom:new{ w = Size.line.thin, h = Screen:scaleBySize(24) },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
    end

    local page_lbl = TextWidget:new{
        text = string.format("%d / %d", current_page, total_pages),
        face = fonts.cell,
    }
    local lbl_zone = CenterContainer:new{
        dimen = Geom:new{ w = lbl_w, h = bar_h },
        page_lbl,
    }

    local bar = HorizontalGroup:new{ align = "center",
        makeZone("«", can_prev, zone_w), makeSep(),
        makeZone("‹", can_prev, zone_w), makeSep(),
        lbl_zone, makeSep(),
        makeZone("›", can_next, zone_w), makeSep(),
        makeZone("»", can_next, zone_w),
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        bar,
    }

    local x0 = 0
    local x1 = zone_w
    local x2 = zone_w * 2
    local x3 = zone_w * 2 + lbl_w
    local x4 = x3 + zone_w

    local hits = {
        { enabled = can_prev, target = 1,                x_min = x0, x_max = x1 },
        { enabled = can_prev, target = current_page - 1, x_min = x1, x_max = x2 },
        { enabled = can_next, target = current_page + 1, x_min = x3, x_max = x4 },
        { enabled = can_next, target = total_pages,      x_min = x4, x_max = full_w },
    }
    return frame, hits
end


Dispatcher:registerAction("reading_history_popup_table_plus_v1", {
    category = "none",
    event = "ShowReadingHistoryPopupTablePlusV1",
    title = "Reading History Popup Table Plus v1.0",
    reader = true,
})

local ReadingStatsTable = InputContainer:extend{
    modal = true,
    ui = nil,
}

local ConfigPopup = InputContainer:extend{
    modal = true,
    parent_popup = nil,
}

function ConfigPopup:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ w = self.screen_w, h = self.screen_h }

    self.fonts = {
        title = Font:getFace("NotoSerif-Bold.ttf", 18),
        item = Font:getFace("NotoSerif-Bold.ttf", 16),
    }

    local mode = getMode()
    local options = {
        { key = "daily", label = _("Daily view") },
        { key = "sessions_30", label = _("Sessions 30m") },
        { key = "sessions_45", label = _("Sessions 45m") },
        { key = "sessions_60", label = _("Sessions 60m") },
    }

    local content = VerticalGroup:new{ align = "left" }
    local title_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding_top = Size.padding.default,
        padding_bottom = Size.padding.small,
        padding_left = Size.padding.default,
        padding_right = Size.padding.default,
        TextWidget:new{ text = _("Select mode"), face = self.fonts.title },
    }
    table.insert(content, title_frame)

    self._option_hits = {}
    local current_y = title_frame:getSize().h

    for _, opt in ipairs(options) do
        local prefix = (mode == opt.key) and "● " or "○ "
        local option_frame = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding_top = Size.padding.small,
            padding_bottom = Size.padding.small,
            padding_left = Size.padding.default,
            padding_right = Size.padding.default,
            TextWidget:new{ text = prefix .. opt.label, face = self.fonts.item },
        }
        local h = option_frame:getSize().h
        table.insert(self._option_hits, {
            key = opt.key,
            y_min_rel = current_y,
            y_max_rel = current_y + h,
        })
        current_y = current_y + h
        table.insert(content, option_frame)
    end

    self.popup = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = math.max(Size.line.thin, 1),
        padding = 0,
        radius = 0,
        width = math.floor(self.screen_w * 0.46),
        content,
    }

    local pw = self.popup:getSize().w
    local ph = self.popup:getSize().h
    self.popup_x = math.floor((self.screen_w - pw) / 2)
    self.popup_y = math.floor((self.screen_h - ph) / 2)
    self.popup_w = pw
    self.popup_h = ph

    self[1] = CenterContainer:new{
        dimen = self.dimen,
        self.popup,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
end

function ConfigPopup:onTapSelect(arg, ges_ev)
    if ges_ev and ges_ev.pos then
        local x = ges_ev.pos.x
        local y = ges_ev.pos.y
        if x >= self.popup_x and x <= (self.popup_x + self.popup_w) and y >= self.popup_y and y <= (self.popup_y + self.popup_h) then
            local y_rel = y - self.popup_y
            for _, hit in ipairs(self._option_hits) do
                if y_rel >= hit.y_min_rel and y_rel <= hit.y_max_rel then
                    setMode(hit.key)
                    local ui_ref = self.parent_popup and self.parent_popup.ui
                    UIManager:close(self)
                    if self.parent_popup then
                        UIManager:close(self.parent_popup)
                    end
                    UIManager:scheduleIn(0, function()
                        _current_page = 1
                        UIManager:show(ReadingStatsTable:new{ ui = ui_ref })
                    end)
                    return true
                end
            end
            return true
        end
    end
    UIManager:close(self)
    return true
end

function ConfigPopup:onAnyKeyPressed()
    UIManager:close(self)
    return true
end


function ReadingStatsTable:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.screen_w = screen_w
    self.screen_h = screen_h

    self.fonts = {
        header  = Font:getFace("NotoSerif-Bold.ttf", 14),
        cell    = Font:getFace("NotoSerif-Bold.ttf", 15),
        title   = Font:getFace("NotoSerif-Bold.ttf", 18),
        title_main = Font:getFace("NotoSerif-Bold.ttf", 20),
        title_meta = Font:getFace("NotoSans-Regular.ttf", 14),
        meta    = Font:getFace("NotoSerif-Bold.ttf", 15),
        session = Font:getFace("NotoSerif-Bold.ttf", 16),
        summary = Font:getFace("NotoSerif-Bold.ttf", 15),
        config  = Font:getFace("NotoSerif-Bold.ttf", 10),
    }

    self.layout = buildLayout(screen_w, Size.padding.default, Screen:scaleBySize(4))
    self.dimen = Geom:new{ w = screen_w, h = screen_h }
    self.stats_plugin = self.ui and self.ui.statistics
    self:buildContent()

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
end

function ReadingStatsTable:buildContent()
    if self.stats_plugin then
        self.stats_plugin:insertDB()
    end

    local book_id = self.stats_plugin and self.stats_plugin.id_curr_book
    local mode = getMode()

    local all_stats
    local daily_stats = getDailyStats(book_id, 365)
    if mode == "daily" then
        all_stats = daily_stats
    else
        all_stats = getSessionStats(book_id, 365, getSessionGapSeconds())
    end

    local book_title = getBookTitle(self.ui)
    local days_read = getTotalDaysRead(book_id)

    local total_rows = #all_stats
    local total_pages = math.max(1, math.ceil(total_rows / ROWS_PER_PAGE))
    local has_pagination = total_rows > ROWS_PER_PAGE

    if _current_page > total_pages then _current_page = total_pages end
    if _current_page < 1 then _current_page = 1 end

    local page_start = (_current_page - 1) * ROWS_PER_PAGE + 1
    local page_end   = math.min(page_start + ROWS_PER_PAGE - 1, total_rows)
    local stats_data = {}
    for i = page_start, page_end do
        table.insert(stats_data, all_stats[i])
    end

    
local title_main = TextWidget:new{
        text = wrapTitle(book_title, 26, 2),
        face = self.fonts.title_main or self.fonts.title or self.fonts.cell,
    }

    local title_meta = TextWidget:new{
        text = string.format("%d %s", days_read, _("Days Read")),
        face = self.fonts.title_meta or self.fonts.meta or self.fonts.cell,
    }

    local title = VerticalGroup:new{
        align = "left",
        title_main,
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        title_meta,
    }


    local config_text = TextWidget:new{
        text = _("Config"),
        face = self.fonts.config or self.fonts.cell
    }

    local config_gap_w = 12
    local config_w = config_text:getSize().w
    local title_col_w = self.screen_w - 2 * self.layout.padding_h - config_w - config_gap_w
    if title_col_w < math.floor(self.screen_w * 0.34) then
        title_col_w = math.floor(self.screen_w * 0.34)
    end
    local title_row = HorizontalGroup:new{
        align = "center",
        fixedCol(title, title_col_w),
        HorizontalSpan:new{ width = config_gap_w },
        fixedCol(config_text, config_w),
    }

    local total_book_time = sumDuration(daily_stats)
    local streak = getStreak(daily_stats)
    local visible_time = sumDuration(stats_data)
    local visible_pages = sumPages(stats_data)
    local visible_delta = sumDelta(stats_data)
    local visible_speed = "-"
    if visible_pages > 0 and visible_time > 0 then
        local speed = formatSpeed(visible_pages, visible_time)
        if speed ~= "-" then
            visible_speed = string.format("%s %s", speed, _("pages/h"))
        end
    end

    local meta1 = TextWidget:new{
        text = string.format("%s: %s   ·   %s: %d %s",
            _("Book total"), formatDurationCompact(total_book_time),
            _("Streak"), streak, _("days")),
        face = self.fonts.meta,
    }

    local visible_label = (mode == "daily") and _("Visible period") or _("Visible sessions")
    local meta2 = TextWidget:new{
        text = string.format("%s: %s   ·   %d p   ·   %s",
            visible_label, formatDurationCompact(visible_time), visible_pages, visible_speed),
        face = self.fonts.meta,
    }

    local meta3 = TextWidget:new{
        text = string.format("%s: %s", _("Mode"), modeLabel(mode)),
        face = self.fonts.meta,
    }

    local session_duration = getCurrentSessionDuration(
        book_id,
        self.stats_plugin and self.stats_plugin.start_current_period
    )
    if self.stats_plugin and self.stats_plugin.page_start_time then
        local live_seconds = os.time() - self.stats_plugin.page_start_time
        if live_seconds > 0 then
            session_duration = session_duration + live_seconds
        end
    end

    local session_widget = TextWidget:new{
        text = string.format("%s %s", formatSeconds(session_duration), _("reading in this session")),
        face = self.fonts.session or self.fonts.cell,
    }

    local summary_widget = TextWidget:new{
        text = string.format("%s: %s · %d p · %s",
            _("Summary"), formatProgressDelta(visible_delta), visible_pages, formatDurationCompact(visible_time)),
        face = self.fonts.summary,
    }

    local header = buildTableHeader(self.fonts, self.layout)
    local rows = buildTableRows(stats_data, self.fonts, self.layout)

    local table_content = VerticalGroup:new{ align = "left" }

    local function makeFrame(widget, pt, pb)
        return FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding_top = pt,
            padding_bottom = pb,
            padding_left = self.layout.padding_h,
            padding_right = self.layout.padding_h,
            widget,
        }
    end

    local title_frame = makeFrame(title_row, Size.padding.default, Size.padding.tiny or 2)
    local meta1_frame = makeFrame(meta1, 0, Size.padding.tiny or 2)
    local meta2_frame = makeFrame(meta2, 0, Size.padding.tiny or 2)
    local meta3_frame = makeFrame(meta3, 0, Size.padding.small)
    local session_frame = makeFrame(session_widget, 0, Size.padding.small)
    local rows_frame = makeFrame(rows, Size.padding.small, Size.padding.small)
    local summary_frame = makeFrame(summary_widget, Size.padding.small, Size.padding.small)

    table.insert(table_content, title_frame)
    table.insert(table_content, meta1_frame)
    table.insert(table_content, meta2_frame)
    table.insert(table_content, meta3_frame)
    table.insert(table_content, session_frame)
    table.insert(table_content, header)
    table.insert(table_content, rows_frame)
    table.insert(table_content, summary_frame)

    local current_y = title_frame:getSize().h + meta1_frame:getSize().h + meta2_frame:getSize().h
        + meta3_frame:getSize().h + session_frame:getSize().h + header:getSize().h + rows_frame:getSize().h + summary_frame:getSize().h

    local btn_y_min = 0
    local btn_y_max = title_frame:getSize().h
    local row_start_x = self.screen_w - self.layout.padding_h - config_w
    self._config_hit = {
        x_min = row_start_x,
        x_max = row_start_x + config_w,
        y_min = btn_y_min,
        y_max = btn_y_max,
    }

    self._chart_hit = nil

    if has_pagination then
        local sep_line = LineWidget:new{
            dimen = Geom:new{ w = self.layout.full_width, h = Size.line.thin },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
        local pagination_frame, hits = buildPaginationBar(self.fonts, self.layout, _current_page, total_pages)

        self._pagination_hits = hits
        self._pagination_bar_y = current_y + sep_line:getSize().h

        table.insert(table_content, sep_line)
        table.insert(table_content, pagination_frame)

        current_y = self._pagination_bar_y + pagination_frame:getSize().h
    else
        self._pagination_hits = nil
        self._pagination_bar_y = nil
    end

    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.layout.full_width, h = Size.line.medium },
        background = Blitbuffer.COLOR_BLACK,
    }
    table.insert(table_content, bottom_line)

    self._popup_bottom_y = current_y + bottom_line:getSize().h

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius = 0,
        padding = 0,
        width = self.screen_w,
        table_content,
    }

    self[1] = self.popup_frame
end

function ReadingStatsTable:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function ReadingStatsTable:onTapClose(arg, ges_ev)
    if ges_ev and ges_ev.pos then
        local tx = ges_ev.pos.x
        local ty = ges_ev.pos.y

        if self._config_hit and tx >= self._config_hit.x_min and tx <= self._config_hit.x_max and ty >= self._config_hit.y_min and ty <= self._config_hit.y_max then
            UIManager:show(ConfigPopup:new{ parent_popup = self })
            return true
        end

        local bar_y = self._pagination_bar_y or 0
        local popup_bot = self._popup_bottom_y or 0

        if ty <= popup_bot then
            if ty >= bar_y and self._pagination_hits then
                for _, hit in ipairs(self._pagination_hits) do
                    if hit.enabled and tx >= hit.x_min and tx <= hit.x_max then
                        local ui_ref = self.ui
                        local target = hit.target
                        UIManager:close(self)
                        UIManager:scheduleIn(0, function()
                            _current_page = target
                            UIManager:show(ReadingStatsTable:new{ ui = ui_ref })
                        end)
                        return true
                    end
                end
                return true
            end
            return true
        end
    end

    UIManager:close(self)
    return true
end

function ReadingStatsTable:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function ReadingStatsTable:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function ReaderUI.onShowReadingHistoryPopupTablePlusV1(this)
    _current_page = 1
    UIManager:show(ReadingStatsTable:new{ ui = this })
    return true
end

return ReadingStatsTable
