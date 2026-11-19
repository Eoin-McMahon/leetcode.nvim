local Controls = require("leetcode-ui.controls")
local Runner = require("leetcode.runner")
local problemlist = require("leetcode.cache.problemlist")
local config = require("leetcode.config")
local log = require("leetcode.logger")
local t = require("leetcode.translator")

local EXTMARK_NS = vim.api.nvim_create_namespace("leetcode_extmarks")

---How values of structured types are written, shown on custom cases.
local TYPE_HINTS = {
    ListNode = "linked list: values in order",
    ["ListNode[]"] = "lists: each one's values in order",
    TreeNode = "tree: level order, null for gaps",
}

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
    -- A blank first row, so the cursor starts on empty space instead of
    -- covering the first value. Blank rows are ignored when running.
    local lines = { "" }
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

    local examples = #(self.console.question.q.testcase_list or {})
    local j, case, invalid = 1, 0, false
    for i, line in ipairs(lines) do
        if lines[i - 1] == "" and line == "" then
            invalid = true
        end
        if line ~= "" then
            local custom = case + (j == 1 and 1 or 0) > examples
            if j == 1 then
                case = case + 1
                local label = { { ("Case %d"):format(case), "leetcode_desc_dim" } }
                if custom then
                    table.insert(label, { "  " .. config.icons.hide, "leetcode_error" })
                end
                vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, i - 1, 0, {
                    virt_text = label,
                    virt_text_pos = "right_align",
                })
            end
            local hint = custom and params[j] and TYPE_HINTS[params[j].type]
            if hint then
                vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, i - 1, 0, {
                    virt_text = { { "  " .. hint, "leetcode_desc_dim" } },
                    virt_text_pos = "eol",
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

    -- Make it obvious the buffer is editable and how to add a case.
    vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, math.max(#lines - 1, 0), 0, {
        virt_lines = {
            { { "" } },
            {
                {
                    ("  %s writes a new case from Case 1. Edit any value in place; %s on a case of yours deletes it"):format(
                        config.icons.write,
                        config.icons.hide
                    ),
                    "leetcode_desc_dim",
                },
            },
        },
    })
end

---Rows of each case in the buffer, in order.
---@return { first: integer, last: integer }[] 1-based rows
function Testcase:case_rows()
    local rows, current = {}, nil
    for i, line in ipairs(vim.api.nvim_buf_get_lines(self:bufnr(), 0, -1, false)) do
        if line ~= "" then
            if not current then
                current = { first = i, last = i }
                table.insert(rows, current)
            else
                current.last = i
            end
        else
            current = nil
        end
    end
    return rows
end

---Append a new case pre-filled with the first example, so its format is
---valid from the start (linked lists and trees as value lists), and put the
---cursor on its first value.
function Testcase:add_custom()
    local first = (self.console.question.q.testcase_list or {})[1] or ""
    self.console:select("testcase", true)
    self:append(first)
    local rows = self:case_rows()
    local last = rows[#rows]
    if last and self.console.pane:is_open() then
        pcall(vim.api.nvim_win_set_cursor, self.console.pane.winid, { last.first, 0 })
    end
end

---Delete the custom case that contains a row. Example cases stay.
---@param row integer 1-based
function Testcase:delete_case(row)
    local examples = #(self.console.question.q.testcase_list or {})
    for idx, r in ipairs(self:case_rows()) do
        if row >= r.first and row <= r.last then
            if idx <= examples then
                return log.warn("Example cases cannot be deleted. Reset restores them")
            end
            if vim.fn.confirm(("Delete Case %d?"):format(idx), "&Delete\n&Cancel", 2) ~= 1 then
                return
            end
            local bufnr = self:bufnr()
            vim.api.nvim_buf_set_lines(bufnr, r.first - 2, r.last, false, {})
            self:draw_extmarks()
            return
        end
    end
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
    if vim.trim(table.concat(lines)) ~= "" then
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
    if self.console.submitting then
        self.console.submitting = false
        return self.console.layout.side:show_submission({
            status_code = -1,
            status_msg = "Submission failed",
            full_runtime_error = tostring(err.msg or "Something went wrong"),
        })
    end
    self.item = nil
    local title = err.title or "Request failed"
    self.console:set_status("leetcode_error", title)
    local lines = { "", "  " .. title, "" }
    local marks = { { row = 1, col = 2, end_col = 2 + #title, hl = "leetcode_result_err" } }
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
    require("leetcode.assist").mark_error(self.console.question, item)
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
        local side = self.console.layout.side
        side:load("submissions", true)
        self.console.submitting = false
        side:show_submission(item)
        Controls.render(self.console.question)
        return
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
        collapsed = config.user.splits.collapsed,
    }, Console)

    self.testcase = setmetatable({ console = self, testcases = {}, testcase_len = 0 }, Testcase)
    self.result = setmetatable({ console = self, case_idx = 1 }, Result)

    local id = self.question.q.frontend_id
    pcall(vim.api.nvim_buf_set_name, self.testcase_buf, id .. "/Tests")
    pcall(vim.api.nvim_buf_set_name, result_buf, id .. "/Results")

    -- The one-row view shown while collapsed. Entering it expands the panel,
    -- so a click or <C-w>j opens the tests.
    self.collapsed_buf = vim.api.nvim_create_buf(false, true)
    for opt, value in pairs({ buftype = "nofile", bufhidden = "hide", swapfile = false, modifiable = false }) do
        vim.bo[self.collapsed_buf][opt] = value
    end
    for _, bufnr in ipairs({ self.testcase_buf, self.result_buf, self.collapsed_buf }) do
        require("leetcode.command").problem_mappings(bufnr)
    end
    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = self.collapsed_buf,
        callback = vim.schedule_wrap(function()
            self:set_collapsed(false)
            self.pane:focus()
        end),
    })

    self.testcase:populate()

    -- Enter on the first row of one of your cases deletes it (after asking);
    -- elsewhere Enter behaves as usual.
    vim.keymap.set("n", "<CR>", function()
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local examples = #(self.question.q.testcase_list or {})
        for idx, r in ipairs(self.testcase:case_rows()) do
            if r.first == row and idx > examples then
                return self.testcase:delete_case(row)
            end
        end
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end, { buffer = self.testcase_buf })

    -- A click on a custom case's X deletes it; other clicks behave as usual.
    vim.keymap.set("n", "<LeftMouse>", function()
        local m = vim.fn.getmousepos()
        local pane = self.pane
        if pane:is_open() and m.winid == pane.winid and m.line > 0 then
            if m.wincol >= vim.api.nvim_win_get_width(pane.winid) - 2 then
                return self.testcase:delete_case(m.line)
            end
        end
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "n", false)
    end, { buffer = self.testcase_buf })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "InsertLeave" }, {
        buffer = self.testcase_buf,
        callback = function()
            self.testcase:draw_extmarks()
        end,
    })

    self:render_winbar()
    return self
end

---@return integer
function Console:active_buf()
    return self.active == "result" and self.result_buf or self.testcase_buf
end

---@param collapsed boolean
function Console:set_collapsed(collapsed)
    if self.collapsed == collapsed then
        return
    end
    self.collapsed = collapsed
    self.layout:show("console")
    self.layout:apply()
    if collapsed then
        self.layout:focus_code()
    end
end

---Collapse or expand; shows the panel first if it was hidden.
function Console:toggle()
    if not self.layout:is_visible("console") then
        self.collapsed = false
        return self.layout:show("console")
    end
    self:set_collapsed(not self.collapsed)
end

---@param horizontal boolean one row under the code, else a narrow strip
function Console:render_collapsed(horizontal)
    local bufnr = self.collapsed_buf
    local ns = vim.api.nvim_create_namespace("leetcode_collapsed")
    local icons = config.icons
    local lines = horizontal and { "" } or { "", "", "" }
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    if horizontal then
        vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
            virt_text = {
                { " " .. icons.console_tabs.testcase .. " " .. LABELS.testcase .. "  ", "leetcode_ctl_tab" },
                { icons.console_tabs.result .. " " .. LABELS.result, "leetcode_ctl_tab" },
            },
            virt_text_pos = "overlay",
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
            virt_text = { { icons.expand_up .. " ", "leetcode_ctl_key" } },
            virt_text_pos = "right_align",
        })
    else
        for row, icon in ipairs({ icons.expand_left, icons.console_tabs.testcase, icons.console_tabs.result }) do
            vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, 0, {
                virt_text = { { " " .. icon, row == 1 and "leetcode_ctl_key" or "leetcode_ctl_tab" } },
                virt_text_pos = "overlay",
            })
        end
    end
end

---@param tab lc.splits.ConsoleTab
---@param focus? boolean
function Console:select(tab, focus)
    self.active = tab
    if self.collapsed then
        self.collapsed = false
        self.layout:show("console")
        self.layout:apply()
    else
        self.layout:show("console")
        self.pane:set_buf(self:active_buf())
    end
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

---Both tabs named with their icons, then the test case actions, fullscreen
---and collapse on the right. No key hints unless `key_hints` is on.
function Console:render_winbar()
    if self.collapsed then
        return
    end
    local parts = { " " }
    for i, tab in ipairs(TABS) do
        local active = tab == self.active
        local hl = active and "leetcode_ctl_tab_active" or "leetcode_ctl_tab"
        local label = config.icons.console_tabs[tab] .. " " .. LABELS[tab]
        local key = config.user.key_hints and Controls.display_key(config.user.mappings[tab])
        if key then
            label = ("%s (%s)"):format(label, key)
        end
        if tab == "result" and self.status_title then
            label = ("%s %%#%s#%s"):format(label, self.status_hl or hl, (vim.trim(self.status_title):gsub("%%", "%%%%")))
        end
        table.insert(parts, ("%%%d@v:lua._leetcode_ctl.console_tab@%%#%s# %s %%X%%*"):format(i, hl, label))
    end

    local icons = config.icons
    local horizontal = self.layout.preset ~= "wide"
    table.insert(parts, "%=")
    table.insert(parts, Controls.button("reset", icons.reset, "leetcode_ctl_action", "reset"))
    table.insert(parts, Controls.button("new_case", icons.write, "leetcode_ctl_action", "new_case"))
    if self.pane:is_fullscreen() then
        table.insert(parts, Controls.button("fullscreen_console", icons.restore, "leetcode_ctl_key", "fullscreen"))
    else
        table.insert(parts, Controls.button("fullscreen_console", icons.fullscreen, "leetcode_ctl_key", "fullscreen"))
        table.insert(
            parts,
            Controls.button("toggle_console", horizontal and icons.collapse_down or icons.collapse_right, "leetcode_ctl_key", "console")
        )
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

    if submit then
        -- Submissions show in the side panel, like the website.
        self.submitting = true
        self.layout.side:show_submission_pending()
    else
        self.submitting = false
        self:set_status(nil)
        self.result:pending(false)
        -- Running always opens the results, expanding a collapsed panel.
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

function Console:unmount() end

function Console:destroy()
    for _, bufnr in ipairs({ self.result_buf, self.collapsed_buf }) do
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
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
