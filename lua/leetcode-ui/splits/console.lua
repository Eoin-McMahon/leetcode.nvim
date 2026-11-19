local Controls = require("leetcode-ui.controls")
local Runner = require("leetcode.runner")
local problemlist = require("leetcode.cache.problemlist")
local config = require("leetcode.config")
local log = require("leetcode.logger")
local t = require("leetcode.translator")

local EXTMARK_NS = vim.api.nvim_create_namespace("leetcode_extmarks")

---@alias lc.splits.ConsoleTab "testcase"|"result"

---Testcase buffer for the splits layout. Mirrors `popup/console/testcase.lua`
---without the `NuiPopup` dependency, so that file stays as upstream has it.
---@class lc.splits.Testcase
---@field console lc.splits.Console
---@field testcases table<string, string>
---@field testcase_len integer
local Testcase = {}
Testcase.__index = Testcase

function Testcase:bufnr()
    return self.console.testcase_buf
end

function Testcase:content()
    local lines = vim.api.nvim_buf_get_lines(self:bufnr(), 0, -1, false)
    lines = vim.tbl_filter(function(line)
        return line ~= ""
    end, lines)
    return table.concat(lines, "\n")
end

function Testcase:snapshot(id, data)
    if data.test_case then
        self.testcases[id] = data.test_case
    end
end

---@return string[][]
function Testcase:by_id(id)
    local testcases = {} ---@type string[][]
    local i, n = 0, self.testcase_len
    for case in vim.gsplit(self.testcases[id] or "", "\n") do
        local j = math.floor(i / n) + 1
        testcases[j] = testcases[j] or {}
        table.insert(testcases[j], case)
        i = i + 1
    end
    return testcases
end

function Testcase:populate()
    local lines = {}
    local t_list = self.console.question.q.testcase_list
    self.testcase_len = #vim.split(t_list[1] or "", "\n")

    for i, case in ipairs(t_list) do
        if i ~= 1 then
            table.insert(lines, "")
        end
        for s in vim.gsplit(case, "\n", { trimempty = true }) do
            table.insert(lines, s)
        end
    end

    vim.api.nvim_buf_set_lines(self:bufnr(), 0, -1, false, lines)
    self:draw_extmarks()
end

---@return string[]
function Testcase:param_names()
    local md = self.console.question.q.meta_data
    if type(md) ~= "table" or type(md.params) ~= "table" then
        return {}
    end
    return vim.tbl_map(function(p)
        return p.name
    end, md.params)
end

---Label each value with its parameter (`list1 = `) inline, mark where each case
---starts, and shade the values, like the website's test case editor. The
---buffer text stays the raw input, so editing it works as before.
function Testcase:draw_extmarks()
    local bufnr = self:bufnr()
    vim.api.nvim_buf_clear_namespace(bufnr, EXTMARK_NS, 0, -1)

    local md = self.console.question.q.meta_data
    local params = type(md) == "table" and md.params or {}
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local width = 0
    for _, p in ipairs(params) do
        width = math.max(width, #p.name)
    end

    local j, case, invalid = 1, 0, false
    for i, line in ipairs(lines) do
        if lines[i - 1] == "" and line == "" then
            invalid = true
        end
        if line ~= "" then
            if j == 1 then
                case = case + 1
                vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, i - 1, 0, {
                    virt_text = { { ("Case %d"):format(case), "leetcode_desc_dim" } },
                    virt_text_pos = "right_align",
                })
            end
            local param = params[j]
            local text
            if param and not invalid then
                text = { { ("  %s = "):format(param.name .. (" "):rep(width - #param.name)), "leetcode_desc_dim" } }
            else
                text = { { ("  %s "):format(t("invalid")), "leetcode_error" } }
            end
            vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, i - 1, 0, {
                virt_text = text,
                virt_text_pos = "inline",
                line_hl_group = "leetcode_desc_block",
            })
            j = j + 1
        else
            j = 1
        end
    end

    -- Make it obvious the buffer is editable and how a case is laid out.
    local names = table.concat(self:param_names(), ", ")
    vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, math.max(#lines - 1, 0), 0, {
        virt_lines = {
            { { "" } },
            {
                {
                    ("  Add your own case: a blank line, then one line each for %s"):format(
                        names ~= "" and names or "the inputs"
                    ),
                    "leetcode_desc_dim",
                },
            },
        },
    })
end

function Testcase:reset()
    self:populate()
    log.info("Test cases reset to the examples")
end

---@param input string
function Testcase:append(input)
    local s = vim.split(input, "\n", { trimempty = true })
    local bufnr = self:bufnr()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    if #lines > 1 or (#lines == 1 and lines[1] ~= "") then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", unpack(s) })
    else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, s)
    end
    self:draw_extmarks()
end

function Testcase:focus()
    self.console:select("testcase", true)
end

---Result buffer for the splits layout, drawn like the description panel.
---@class lc.splits.Result
---@field console lc.splits.Console
---@field item? table last run or submit response
---@field case_idx integer
---@field last_testcase? string
local Result = {}
Result.__index = Result

local RESULT_NS = vim.api.nvim_create_namespace("leetcode_result")

function Result:width()
    local pane = self.console.pane
    if pane:is_open() then
        return vim.api.nvim_win_get_width(pane.winid)
    end
    return 80
end

---@param lines string[]
---@param out? lc.desc.Output
function Result:write(lines, out)
    local bufnr = self.console.result_buf
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_buf_clear_namespace(bufnr, RESULT_NS, 0, -1)
    for _, m in ipairs(out and out.marks or {}) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, RESULT_NS, m.row, m.col, {
            end_col = math.min(m.end_col, #lines[m.row + 1]),
            hl_group = m.hl,
        })
    end
    for _, l in ipairs(out and out.line_hls or {}) do
        vim.api.nvim_buf_set_extmark(bufnr, RESULT_NS, l.row, 0, { line_hl_group = l.hl })
    end
end

function Result:draw()
    if not self.item then
        return
    end
    local item = self.item
    local testcases = self.console.testcase:by_id(item.submission_id)
    local md = self.console.question.q.meta_data
    local params = type(md) == "table" and md.params or {}
    local out, count = require("leetcode-ui.splits.result").render(item, testcases, params, self.case_idx, self:width())
    self:write(out.lines, out)

    local bufnr = self.console.result_buf
    for i = 1, math.min(count, 9) do
        vim.keymap.set("n", tostring(i), function()
            self.case_idx = i
            self:draw()
        end, { buffer = bufnr, nowait = true })
    end
end

-- Kept for callers of the upstream console interface.
function Result:map(mode, key, fn)
    vim.keymap.set(mode, key, fn, { buffer = self.console.result_buf })
end

function Result:clear()
    self.item = nil
    self.last_testcase = nil
    self:write({})
end

---Show a placeholder at once so a click gets feedback before the request leaves.
---@param submit boolean
function Result:pending(submit)
    self.item = nil
    local text = "  " .. (submit and "Submitting…" or "Running…")
    self:write({ "", text }, { marks = { { row = 1, col = 2, end_col = #text, hl = "leetcode_desc_dim" } }, line_hls = {} })
end

---A failed request (network, auth, rate limit) replaces the "Running…"
---placeholder instead of leaving it on screen.
---@param err lc.err
function Result:show_error(err)
    self.item = nil
    self.console:set_status("leetcode_error", "Request failed")
    local lines = { "", "  Request failed", "" }
    local marks = { { row = 1, col = 2, end_col = 16, hl = "leetcode_result_err" } }
    local line_hls = {}
    local msg = tostring(err.msg or "Something went wrong")
    table.insert(lines, "  ")
    table.insert(line_hls, { row = #lines - 1, hl = "leetcode_block_err" })
    for _, l in ipairs(vim.split(msg, "\n")) do
        table.insert(lines, "    " .. l)
        table.insert(line_hls, { row = #lines - 1, hl = "leetcode_block_err" })
    end
    table.insert(lines, "  ")
    table.insert(line_hls, { row = #lines - 1, hl = "leetcode_block_err" })
    self:write(lines, { marks = marks, line_hls = line_hls })
    self.console:select("result")
end

---@param item lc.interpreter_response
function Result:handle(item)
    self.item = item
    self.case_idx = 1
    -- Open on the first failing case, like the website.
    local compare = item.compare_result
    if type(compare) == "string" then
        local first_fail = compare:find("0", 1, true)
        if first_fail then
            self.case_idx = first_fail
        end
    end
    self.console:set_status(item._.hl, item._.title)

    if item.last_testcase and item.last_testcase ~= vim.NIL then
        self.last_testcase = item.last_testcase
    elseif type(compare) == "string" and compare:find("0", 1, true) then
        -- A failed run case can be added as a test too.
        local cases = self.console.testcase:by_id(item.submission_id)
        local failed = cases[self.case_idx]
        self.last_testcase = failed and table.concat(failed, "\n") or nil
    end

    if item._.submission then
        local status = item.status_code == 10 and "ac" or "notac"
        problemlist.change_status(self.console.question.q.title_slug, status)
        if status == "ac" then
            config.stats.update_streak()
        end
        self.console.layout.side:load("submissions", true)
    end

    self:draw()
    Controls.render(self.console.question)
end

function Result:focus()
    self.console:select("result", true)
end

---The `q.console` object for the splits layout: one bottom pane with Testcase
---and Test Result tabs, like the website. Same interface the runner and
---commands use with the floating console.
---@class lc.splits.Console
---@field question lc.ui.Question
---@field layout lc.splits.Layout
---@field pane lc.splits.Pane
---@field testcase_buf integer
---@field result_buf integer
---@field active lc.splits.ConsoleTab
---@field status_hl? string
---@field status_title? string
---@field testcase lc.splits.Testcase
---@field result lc.splits.Result
local Console = {}
Console.__index = Console

local TABS = { "testcase", "result" }
local LABELS = { testcase = "Tests", result = "Results" }

---@param layout lc.splits.Layout
---@param pane lc.splits.Pane shows the testcase buffer when created
---@param result_buf integer
function Console.new(layout, pane, result_buf)
    local self = setmetatable({
        question = layout.question,
        layout = layout,
        pane = pane,
        testcase_buf = pane.bufnr,
        result_buf = result_buf,
        active = "testcase",
    }, Console)

    self.testcase = setmetatable({ console = self, testcases = {}, testcase_len = 0 }, Testcase)
    self.result = setmetatable({ console = self, case_idx = 1 }, Result)

    local id = self.question.q.frontend_id
    pcall(vim.api.nvim_buf_set_name, self.testcase_buf, id .. "/Tests")
    pcall(vim.api.nvim_buf_set_name, result_buf, id .. "/Results")

    self.testcase:populate()
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "InsertLeave" }, {
        buffer = self.testcase_buf,
        callback = function()
            self.testcase:draw_extmarks()
        end,
    })

    self:render_winbar()
    return self
end

---@param tab lc.splits.ConsoleTab
---@param focus? boolean
function Console:select(tab, focus)
    self.active = tab
    self.layout:show("console")
    self.pane:set_buf(tab == "result" and self.result_buf or self.testcase_buf)
    self:render_winbar()
    if tab == "result" then
        self.result:draw()
    end
    if focus then
        self.pane:focus()
    end
end

function Console:cycle()
    self:select(self.active == "testcase" and "result" or "testcase")
end

---@param hl? string
---@param title? string
function Console:set_status(hl, title)
    self.status_hl = hl
    self.status_title = title
    self:render_winbar()
end

---Tabs like the side pane (`icon (key)`, active one named), then the test
---case actions and the hide key on the right.
function Console:render_winbar()
    local parts = { " " }
    for i, tab in ipairs(TABS) do
        local active = tab == self.active
        local hl = active and "leetcode_ctl_tab_active" or "leetcode_ctl_tab"
        local label = config.icons.console_tabs[tab]
        if active then
            label = label .. " " .. LABELS[tab]
        end
        local key = Controls.display_key(config.user.mappings[tab])
        if key then
            label = ("%s (%s)"):format(label, key)
        end
        if tab == "result" and self.status_title then
            label = ("%s %%#%s#%s"):format(label, self.status_hl or hl, (vim.trim(self.status_title):gsub("%%", "%%%%")))
        end
        table.insert(parts, ("%%%d@v:lua._leetcode_ctl.console_tab@%%#%s# %s %%X%%*"):format(i, hl, label))
    end

    table.insert(parts, "%=")
    table.insert(parts, Controls.button("reset", config.icons.reset, "leetcode_ctl_action", "reset"))
    table.insert(parts, Controls.button("add_case", config.icons.add, "leetcode_ctl_action", "add_case"))
    local hide = Controls.display_key(config.user.mappings.console)
    if hide then
        table.insert(parts, ("%%#leetcode_ctl_key# %s %s %%*"):format(config.icons.hide, hide))
    end
    self.pane:set_winbar(table.concat(parts, ""))
end

---@param submit? boolean
function Console:run(submit)
    local range = self.question:editor_section_range("code")
    if not range:is_valid_or_log() then
        return
    end
    if Runner.running then
        return log.warn("Runner is busy")
    end

    self:set_status(nil)
    self.result:pending(submit == true)
    if config.user.console.open_on_runcode or self.layout:is_visible("console") then
        self:select("result")
    end

    Runner:init(self.question):run(submit)
end

function Console:use_testcase()
    local last = self.result.last_testcase
    if last and last ~= "" then
        self.testcase:append(last)
        self:select("testcase")
        log.info("Added the failed case to your test cases")
    else
        log.warn("No failed case to add. Run or submit first")
    end
end

function Console:show()
    self.layout:show("console")
end

function Console:hide()
    self.layout:hide("console")
end

function Console:toggle()
    self.layout:toggle("console")
end

function Console:unmount() end

function Console:destroy()
    if vim.api.nvim_buf_is_valid(self.result_buf) then
        pcall(vim.api.nvim_buf_delete, self.result_buf, { force = true })
    end
end

_G._leetcode_ctl.console_tab = function(minwid)
    local winid = vim.fn.getmousepos().winid
    for _, q in ipairs(_Lc_state.questions) do
        if q.layout and q.layout.panes.console.winid == winid then
            q.console:select(TABS[minwid])
        end
    end
end

Console.TABS = TABS

return Console
