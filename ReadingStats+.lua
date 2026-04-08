--[[
Reading History Popup Table Plus
Version: 2.11.1 (full title header and cleaner pace view)

Notes:
- Keeps the visual layout of the user's preferred version
- Uses daily view only
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
        ["Days Read"] = "days",
        ["reading in this session"] = "reading in this session",
        ["Book total"] = "Book total",
        ["Actual reading total"] = "Actual reading",
        ["Visible period"] = "Visible period",
        ["Visible sessions"] = "Visible sessions",
        ["Daily avg"] = "Daily avg",
        ["Avg session"] = "Avg session",
        ["Med session"] = "Med session",
        ["Summary"] = "Summary",
        ["pages/h"] = "pg/hr",
        ["pg/session"] = "pg/session",
        ["%/hr"] = "%/hr",
        ["total"] = "total",
        ["gain"] = "gain",
        ["days"] = "days",
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
local ROWS_PER_PAGE = 7
local SPEED_MIN_DURATION_SECONDS = 120
local SPEED_MIN_PAGES = 3
local _current_page = 1

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

local function formatHoursMinutes(seconds)
    if not seconds or seconds <= 0 then
        return "0 hr 0 min"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%d hr %d min", hours, minutes)
end

local function formatMinutesSeconds(seconds)
    if not seconds or seconds <= 0 then
        return "0 min 0 sec"
    end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d min %d sec", minutes, secs)
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

local function getDB()
    return SQ3.open(stats_db_path)
end

local function getDailyStats(book_id, days, effective_total_pages)
    if not book_id or not days or days <= 0 then return {} end
    local conn = getDB()
    if not conn then return {} end
    local divisor = tonumber(effective_total_pages) or 0

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

    if divisor > 0 then
        sql = string.format([[
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
                (SELECT min(1.0, (ps4.page * 1.0 / %d))
                 FROM page_stat_data ps4
                 WHERE ps4.id_book = ps.id_book
                   AND date(ps4.start_time, 'unixepoch', 'localtime') = date(ps.start_time, 'unixepoch', 'localtime')
                   AND ps4.page <= %d
                 ORDER BY ps4.start_time DESC
                 LIMIT 1) AS total_percentage
            FROM page_stat_data ps
            WHERE ps.id_book = %d
              AND date(ps.start_time, 'unixepoch', 'localtime') >= date('now', '-' || %d || ' days')
            GROUP BY date(ps.start_time, 'unixepoch', 'localtime')
            ORDER BY dates DESC;
        ]], divisor, divisor, book_id, days)
    end

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

local function getSessionStats(book_id, days)
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
            if row.date ~= current.date or gap > (30 * 60) then
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

local function getBookAuthor(ui)
    if not ui or not ui.doc_props then return "" end
    local author = ui.doc_props.display_author or ui.doc_props.authors or ui.doc_props.author or ""
    if type(author) == "table" then
        author = table.concat(author, ", ")
    end
    return tostring(author)
end

local function getEffectiveTotalPages(ui)
    if not ui or not ui.document then
        return nil
    end
    local doc = ui.document

    if doc.hasHiddenFlows and doc:hasHiddenFlows()
        and ui.getCurrentPage and doc.getPageFlow and doc.getTotalPagesInFlow then
        local current_page = ui:getCurrentPage()
        if current_page then
            local flow = doc:getPageFlow(current_page)
            local flow_total = flow and doc:getTotalPagesInFlow(flow) or nil
            if flow_total and flow_total > 0 then
                return flow_total
            end
        end
    end

    if doc.getPageCount then
        return doc:getPageCount()
    end
    return nil
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

local function getActualReadingTotal(book_id, max_seconds)
    if not book_id then return 0 end
    max_seconds = tonumber(max_seconds) or 120
    local conn = getDB()
    if not conn then return 0 end
    local sql = string.format([[
        SELECT count(*), COALESCE(sum(durations), 0)
        FROM (
            SELECT min(sum(duration), %d) AS durations
            FROM page_stat
            WHERE id_book = %d
            GROUP BY page
        );
    ]], max_seconds, book_id)
    local _, result = conn:rowexec(sql)
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

local function getDailyAverageSeconds(stats)
    local total_time = sumDuration(stats)
    local total_days = #(stats or {})
    if total_days == 0 then
        return 0
    end
    return total_time / total_days
end

local function getFilteredSessionStatsByDates(session_stats, daily_rows)
    local allowed_dates = {}
    for _, row in ipairs(daily_rows or {}) do
        if row and row.date then
            allowed_dates[row.date] = true
        end
    end

    local filtered = {}
    for _, session in ipairs(session_stats or {}) do
        if session and session.date and allowed_dates[session.date] then
            table.insert(filtered, session)
        end
    end
    return filtered
end

local function formatAvgSessionLength(stats)
    local valid_count = 0
    local total_seconds = 0
    for _, row in ipairs(stats or {}) do
        local pages = tonumber(row.pages) or 0
        local duration = tonumber(row.duration) or 0
        if pages > 1 and duration >= 60 then
            valid_count = valid_count + 1
            total_seconds = total_seconds + duration
        end
    end
    if valid_count == 0 then
        return "-"
    end

    local avg_seconds = total_seconds / valid_count
    return formatMinutesSeconds(avg_seconds)
end

local function getMedianSessionLength(stats)
    local durations = {}
    for _, row in ipairs(stats or {}) do
        local pages = tonumber(row.pages) or 0
        local duration = tonumber(row.duration) or 0
        if pages > 1 and duration >= 60 then
            table.insert(durations, duration)
        end
    end
    if #durations == 0 then
        return "-"
    end
    table.sort(durations)
    local n = #durations
    local median
    if n % 2 == 1 then
        median = durations[(n + 1) / 2]
    else
        median = (durations[n / 2] + durations[n / 2 + 1]) / 2
    end
    return formatMinutesSeconds(median)
end

local function getPagesPerSession(stats)
    local valid_count = 0
    local total_pages = 0
    for _, row in ipairs(stats or {}) do
        local pages = tonumber(row.pages) or 0
        local duration = tonumber(row.duration) or 0
        if pages > 1 and duration >= 60 then
            valid_count = valid_count + 1
            total_pages = total_pages + pages
        end
    end
    if valid_count == 0 then
        return "-"
    end
    local avg_pages = total_pages / valid_count
    return string.format("%.1f", avg_pages)
end

local function getProgressEfficiency(stats)
    local total_delta = sumDelta(stats)
    local total_seconds = sumDuration(stats)
    if total_seconds <= 0 then
        return "-"
    end
    local per_hour = (total_delta * 100) / (total_seconds / 3600)
    return string.format("%.2f", per_hour)
end

local function getValidSessionTotals(stats)
    local total_pages = 0
    local total_duration = 0
    local valid_count = 0
    for _, row in ipairs(stats or {}) do
        local pages = tonumber(row.pages) or 0
        local duration = tonumber(row.duration) or 0
        if pages > 1 and duration >= 60 then
            valid_count = valid_count + 1
            total_pages = total_pages + pages
            total_duration = total_duration + duration
        end
    end
    return total_pages, total_duration, valid_count
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
    title = "ReadingStats+",
    reader = true,
})

local ReadingStatsTable = InputContainer:extend{
    modal = true,
    ui = nil,
}

function ReadingStatsTable:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.screen_w = screen_w
    self.screen_h = screen_h

    self.fonts = {
        header  = Font:getFace("NotoSans-Regular.ttf", 14),
        cell    = Font:getFace("NotoSans-Regular.ttf", 15),
        title   = Font:getFace("NotoSans-Regular.ttf", 18),
        title_main = Font:getFace("NotoSans-Bold.ttf", 20),
        title_meta = Font:getFace("NotoSans-Regular.ttf", 13),
        title_author = Font:getFace("NotoSans-Regular.ttf", 13),
        title_meta = Font:getFace("NotoSans-Regular.ttf", 14),
        meta    = Font:getFace("NotoSans-Regular.ttf", 15),
        session = Font:getFace("NotoSans-Regular.ttf", 16),
        session_bold = Font:getFace("NotoSans-Bold.ttf", 16),
        summary = Font:getFace("NotoSans-Regular.ttf", 15),
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
    local effective_total_pages = getEffectiveTotalPages(self.ui)
    local daily_stats = getDailyStats(book_id, 365, effective_total_pages)
    local session_stats = getSessionStats(book_id, 365)
    local all_stats = daily_stats

    local book_title = getBookTitle(self.ui)
    local book_author = getBookAuthor(self.ui)
    local days_read = getTotalDaysRead(book_id)

    local display_stats = all_stats

    local total_rows = #display_stats
    local total_pages = math.max(1, math.ceil(total_rows / ROWS_PER_PAGE))
    local has_pagination = total_rows > ROWS_PER_PAGE

    if _current_page > total_pages then _current_page = total_pages end
    if _current_page < 1 then _current_page = 1 end

    local page_start = (_current_page - 1) * ROWS_PER_PAGE + 1
    local page_end   = math.min(page_start + ROWS_PER_PAGE - 1, total_rows)
    local stats_data = {}
    for i = page_start, page_end do
        table.insert(stats_data, display_stats[i])
    end

    local title_main = TextWidget:new{
        text = wrapTitle(book_title, 28, 2),
        face = self.fonts.title_main or self.fonts.title or self.fonts.cell,
    }

    local title_author = TextWidget:new{
        text = book_author or "",
        face = self.fonts.title_author or self.fonts.title_meta or self.fonts.meta or self.fonts.cell,
    }

    local total_book_time = sumDuration(daily_stats)
    local actual_book_time = getActualReadingTotal(book_id, 120)

    local title_meta = TextWidget:new{
        text = string.format("%d %s   ·   %s: %s   ·   %s: %s",
            days_read, _("Days Read"),
            _("Book total"), formatDurationCompact(total_book_time),
            _("Actual reading total"), formatDurationCompact(actual_book_time)),
        face = self.fonts.title_meta or self.fonts.meta or self.fonts.cell,
    }

    local title = VerticalGroup:new{
        align = "left",
        title_main,
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        title_author,
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        title_meta,
    }

    local title_row = title

    local all_time = sumDuration(all_stats)
    local valid_pages_total, valid_duration_total, valid_sessions_total = getValidSessionTotals(all_stats)
    local visible_speed = "-"
    if valid_sessions_total > 0 and valid_duration_total > 0 then
        local pph = (valid_pages_total * 3600) / valid_duration_total
        visible_speed = string.format("%.0f %s", pph, _("pages/h"))
    end
    local daily_avg_seconds = getDailyAverageSeconds(all_stats)
    local visible_sessions = getFilteredSessionStatsByDates(session_stats, all_stats)
    local avg_session_minutes = formatAvgSessionLength(visible_sessions)
    local med_session_minutes = getMedianSessionLength(visible_sessions)
    local pages_per_session = getPagesPerSession(visible_sessions)
    local progress_efficiency = getProgressEfficiency(all_stats)

    local left_stats = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = string.format("%s: %s", _("Daily avg"), formatHoursMinutes(daily_avg_seconds)),
            face = self.fonts.meta,
        },
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        TextWidget:new{
            text = string.format("%s: %s", _("Avg session"), avg_session_minutes),
            face = self.fonts.meta,
        },
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        TextWidget:new{
            text = string.format("%s: %s", _("Med session"), med_session_minutes),
            face = self.fonts.meta,
        },
    }

    local right_stats = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = visible_speed,
            face = self.fonts.meta,
        },
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        TextWidget:new{
            text = string.format("%s %s", pages_per_session, _("pg/session")),
            face = self.fonts.meta,
        },
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        TextWidget:new{
            text = string.format("%s %s", progress_efficiency, _("%/hr")),
            face = self.fonts.meta,
        },
    }

    local stats_height = math.max(left_stats:getSize().h, right_stats:getSize().h)
    local partition_height = math.max(1, stats_height - (Size.padding.small or 4))
    local stats_partition = LineWidget:new{
        dimen = Geom:new{ w = Size.line.medium, h = partition_height },
        background = Blitbuffer.COLOR_BLACK,
    }

    local stats_widget = HorizontalGroup:new{
        left_stats,
        HorizontalSpan:new{ width = self.layout.column_gap },
        stats_partition,
        HorizontalSpan:new{ width = self.layout.column_gap },
        right_stats,
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

    local session_widget = HorizontalGroup:new{
        TextWidget:new{
            text = "This session: ",
            face = self.fonts.session or self.fonts.cell,
        },
        TextWidget:new{
            text = formatSeconds(session_duration),
            face = self.fonts.session_bold or self.fonts.session or self.fonts.cell,
        },
    }

    local summary_widget = TextWidget:new{
        text = string.format("%s: %s · %s %s · %s %s",
            _("Summary"),
            formatDurationCompact(all_time),
            formatProgressTotal((all_stats[1] and all_stats[1].progress) or 0), _("total"),
            formatProgressDelta((all_stats[1] and all_stats[1].delta_progress) or 0), _("gain")),
        face = self.fonts.summary,
    }

    local summary_meta_widget = TextWidget:new{
        text = string.format("%s: %s · %s · %s %s",
            _("Daily avg"), formatHoursMinutes(daily_avg_seconds),
            visible_speed,
            progress_efficiency, _("%/hr")),
        face = self.fonts.meta,
    }

    local summary_block = VerticalGroup:new{
        align = "left",
        summary_widget,
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        summary_meta_widget,
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
    local stats_frame = makeFrame(stats_widget, 0, Size.padding.tiny or 2)
    local session_frame = makeFrame(session_widget, 0, Size.padding.small)
    local rows_frame = makeFrame(rows, Size.padding.small, Size.padding.small)
    local summary_frame = makeFrame(summary_block, Size.padding.small, Size.padding.small)

    table.insert(table_content, title_frame)
    table.insert(table_content, stats_frame)
    table.insert(table_content, session_frame)
    table.insert(table_content, header)
    table.insert(table_content, rows_frame)
    table.insert(table_content, summary_frame)

    local current_y = title_frame:getSize().h + stats_frame:getSize().h
        + session_frame:getSize().h + header:getSize().h + rows_frame:getSize().h + summary_frame:getSize().h

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
