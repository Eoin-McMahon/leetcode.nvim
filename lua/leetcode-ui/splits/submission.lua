local config = require("leetcode.config")

---Render a submission result for the side panel's Submissions tab, like the
---website's: a verdict header with the pass count, then either the failing
---case (with buttons) or the runtime and memory stats with a distribution
---chart, then similar problems.
local Render = {}

local PAD = "  "
local BARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local CHART_HEIGHT = 6
local CHART_BUCKETS = 12
local MAX_SIMILAR = 5

---@param v any
local function present(v)
    return v ~= nil and v ~= vim.NIL and v ~= ""
end

---@class lc.sub.Button
---@field row integer 1-based
---@field col integer 0-based start
---@field end_col integer
---@field action string

---@class lc.sub.Output : lc.desc.Output
---@field buttons lc.sub.Button[]
---@field links table<integer, string> row to similar question slug

---@param item table submit response
---@param q lc.ui.Question
---@param width integer
---@param details? table submissionDetails, for the distribution chart
---@return lc.sub.Output
function Render.render(item, q, width, details)
    local out = { lines = {}, marks = {}, line_hls = {}, links = {}, buttons = {} }
    local inner = math.max(math.min(width, 88) - #PAD - 4, 20)

    local function add(text, marks, line_hl)
        table.insert(out.lines, text)
        local row = #out.lines - 1
        for _, m in ipairs(marks or {}) do
            table.insert(out.marks, { row = row, col = m.col, end_col = m.end_col, hl = m.hl })
        end
        if line_hl then
            table.insert(out.line_hls, { row = row, hl = line_hl })
        end
    end
    local function dim(text)
        local line = PAD .. text
        add(line, { { col = #PAD, end_col = #line, hl = "leetcode_desc_dim" } })
    end
    local function heading(text)
        add("")
        local line = PAD .. text
        add(line, { { col = #PAD, end_col = #line, hl = "leetcode_desc_heading" } })
    end
    local function block(text, hl)
        hl = hl or "leetcode_desc_block"
        add(PAD, nil, hl)
        for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
            while #line > inner do
                add(PAD .. "  " .. line:sub(1, inner), nil, hl)
                line = line:sub(inner + 1)
            end
            add(PAD .. "  " .. line, nil, hl)
        end
        add(PAD, nil, hl)
    end
    local function buttons(list)
        local line, marks = PAD, {}
        for _, b in ipairs(list) do
            if #line > #PAD then
                line = line .. "   "
            end
            local text = (" %s %s "):format(b.icon, b.label)
            table.insert(marks, { col = #line, end_col = #line + #text, hl = "leetcode_chip_active" })
            table.insert(out.buttons, { row = #out.lines + 1, col = #line, end_col = #line + #text, action = b.action })
            line = line .. text
        end
        add(line, marks)
    end

    local ok = item.status_code == 10
    local title = vim.trim(item.status_msg or (ok and "Accepted" or "Failed"))
    add("")
    local header = PAD .. title
    local marks = { { col = #PAD, end_col = #header, hl = ok and "leetcode_result_ok" or "leetcode_result_err" } }
    if present(item.total_correct) and present(item.total_testcases) then
        local passed = ("   %d / %d testcases passed"):format(item.total_correct, item.total_testcases)
        table.insert(marks, { col = #header, end_col = #header + #passed, hl = "leetcode_desc_dim" })
        header = header .. passed
    end
    add(header, marks)
    dim(("submitted at %s"):format(os.date("%b %d, %Y %H:%M", item.timestamp or os.time())))

    if ok then
        add("")
        local function card(label, value, beats)
            local line = ("%s%s  %s"):format(PAD, label, value)
            local m = {
                { col = #PAD, end_col = #PAD + #label, hl = "leetcode_desc_dim" },
                { col = #PAD + #label + 2, end_col = #line, hl = "leetcode_desc_title" },
            }
            if present(beats) then
                local text = ("   Beats %.2f%%"):format(tonumber(beats) or 0)
                table.insert(m, { col = #line, end_col = #line + #text, hl = "leetcode_result_ok" })
                line = line .. text
            end
            add(line, m, "leetcode_desc_block")
        end
        add(PAD, nil, "leetcode_desc_block")
        card(config.icons.runtime .. " Runtime", item.status_runtime or "", item.runtime_percentile)
        add(PAD, nil, "leetcode_desc_block")
        card(config.icons.memory .. " Memory ", item.status_memory or "", item.memory_percentile)
        add(PAD, nil, "leetcode_desc_block")

        local dist = details and details.runtimeDistribution
        local ok_json, parsed = pcall(vim.json.decode, type(dist) == "string" and dist or "")
        local buckets = ok_json and type(parsed) == "table" and parsed.distribution
        if type(buckets) == "table" and #buckets > 0 then
            heading("Runtime distribution")
            add("")
            local mine = tonumber((item.status_runtime or ""):match("%d+")) or -1
            -- Fill the width: as many buckets as fit with readable labels,
            -- then widen the bars to use all the space.
            local label_w = 0
            for _, b in ipairs(vim.list_slice(buckets, 1, CHART_BUCKETS)) do
                label_w = math.max(label_w, #(tostring(b[1]) .. "ms"))
            end
            local count = math.max(math.min(CHART_BUCKETS, #buckets, math.floor(inner / (label_w + 1))), 1)
            local shown = vim.list_slice(buckets, 1, count)
            local col_w = math.floor(inner / #shown)
            local bar_w = math.max(col_w - 1, 1)
            local max = 0
            for _, b in ipairs(shown) do
                max = math.max(max, tonumber(b[2]) or 0)
            end
            local mine_idx = 1
            for i, b in ipairs(shown) do
                if mine >= (tonumber(b[1]) or 0) then
                    mine_idx = i
                end
            end
            for level = CHART_HEIGHT, 1, -1 do
                local line, m = PAD .. "  ", {}
                for i, b in ipairs(shown) do
                    local units = max > 0 and (tonumber(b[2]) or 0) / max * CHART_HEIGHT * 8 or 0
                    local fill = units - (level - 1) * 8
                    local glyph = fill >= 8 and BARS[8] or (fill > 0 and BARS[math.max(math.floor(fill), 1)] or " ")
                    local bar = glyph:rep(bar_w)
                    if glyph ~= " " then
                        table.insert(m, {
                            col = #line,
                            end_col = #line + #bar,
                            hl = i == mine_idx and "leetcode_chart_mine" or "leetcode_chart_bar",
                        })
                    end
                    line = line .. bar .. " "
                end
                add(line, m)
            end
            local labels = PAD .. "  "
            for _, b in ipairs(shown) do
                local text = tostring(b[1]) .. "ms"
                labels = labels .. text .. (" "):rep(math.max(col_w - #text, 1))
            end
            add(labels, { { col = #PAD, end_col = #labels, hl = "leetcode_desc_dim" } })
        end
    else
        local md = type(q.q.meta_data) == "table" and q.q.meta_data or {}
        -- Design problems take a list of calls and a list of their arguments.
        local params = md.systemdesign and { { name = "calls" }, { name = "arguments" } } or md.params or {}
        local err = item.status_code == 20 and item.full_compile_error or item.full_runtime_error
        if present(err) then
            heading(item.status_code == 20 and "Compile error" or "Error")
            block(err, "leetcode_block_err")
        end
        if present(item.last_testcase) then
            heading("Input")
            add("")
            buttons({
                { icon = config.icons.add, label = "Use testcase", action = "use" },
                { icon = config.icons.debug, label = "Debug this case", action = "debug" },
            })
            add("")
            for i, value in ipairs(vim.split(item.last_testcase, "\n")) do
                if params[i] then
                    dim(params[i].name .. " =")
                end
                block(value)
            end
        end
        if present(item.code_output) then
            heading("Output")
            block(type(item.code_output) == "table" and table.concat(item.code_output, "\n") or item.code_output, "leetcode_block_err")
        end
        if present(item.expected_output) then
            heading("Expected")
            block(item.expected_output, "leetcode_block_ok")
        end
        if present(item.std_output) then
            heading("Stdout")
            block(item.std_output)
        end
    end

    if item.past then
        add("")
        buttons({ { icon = config.icons.tabs.submissions, label = "Load this code", action = "load" } })
    end

    local similar = not item.past and q.q.similar
    if type(similar) == "table" and #similar > 0 then
        heading("More challenges")
        for _, s in ipairs(vim.list_slice(similar, 1, MAX_SIMILAR)) do
            local slug = s.title_slug
            local problem = slug and select(2, pcall(require("leetcode.cache.problemlist").get_by_title_slug, slug))
            local id = type(problem) == "table" and problem.frontend_id or ""
            local line = ("%s%s %s%s"):format(PAD, "●", id ~= "" and (id .. ". ") or "", s.title)
            add(line, {
                { col = #PAD, end_col = #PAD + #"●", hl = "leetcode_" .. (s.difficulty or "easy"):lower() },
            })
            out.links[#out.lines] = slug
        end
    end

    return out
end

return Render
