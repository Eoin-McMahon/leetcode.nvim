local Controls = require("leetcode-ui.controls")
local ResultLayout = require("leetcode-ui.renderer.result")
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

function Testcase:draw_extmarks()
    local bufnr = self:bufnr()
    vim.api.nvim_buf_clear_namespace(bufnr, EXTMARK_NS, 0, -1)

    local md = self.console.question.q.meta_data
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    if config.user.console.testcase.virt_text and type(md) == "table" and md.params then
        local pad = "  "
        local j, invalid = 1, false
        for i, line in ipairs(lines) do
            if lines[i - 1] == "" and line == "" then
                invalid = true
            end

            if line ~= "" then
                local param = md.params[j]
                local text
                if param and not invalid then
                    text = {
                        { pad },
                        { config.icons.param, "Operator" },
                        { " " },
                        { param.name, "Comment" },
                        { " " },
                        { param.type, "Type" },
                    }
                else
                    text = { { pad }, { (" %s"):format(t("invalid")), "leetcode_error" } }
                end
                vim.api.nvim_buf_set_extmark(bufnr, EXTMARK_NS, i - 1, 0, { virt_text = text })
                j = j + 1
            else
                j = 1
            end
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
                    "Comment",
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

---Result buffer for the splits layout, drawn by the plugin's result renderer.
---@class lc.splits.Result
---@field console lc.splits.Console
---@field renderer lc.ui.Result
---@field last_testcase? string
local Result = {}
Result.__index = Result

function Result:target()
    local console = self.console
    local pane = console.pane
    local shown = pane:is_open() and vim.api.nvim_win_get_buf(pane.winid) == console.result_buf
    return { bufnr = console.result_buf, winid = shown and pane.winid or nil }
end

function Result:map(...)
    self.renderer.bufnr = self.console.result_buf
    self.renderer:map(...)
end

function Result:draw()
    self.renderer:draw(self:target())
end

function Result:clear()
    self.renderer.bufnr = self.console.result_buf
    self.renderer:clear()
    self.last_testcase = nil
end

---Show a placeholder at once so a click gets feedback before the request leaves.
---@param submit boolean
function Result:pending(submit)
    local bufnr = self.console.result_buf
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "  " .. (submit and "Submitting…" or "Running…") })
    vim.bo[bufnr].modifiable = false
end

---@param item lc.interpreter_response
function Result:handle(item)
    self.renderer:handle_res(item)
    self.console:set_status(item._.hl, item._.title)

    if item.last_testcase then
        self.last_testcase = item.last_testcase
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
local LABELS = { testcase = "Testcase", result = "Test Result" }

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
    self.result = setmetatable({ console = self }, Result)
    self.result.renderer = ResultLayout(self)
    self.result.renderer.bufnr = result_buf

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

function Console:render_winbar()
    local parts = { " " }
    for i, tab in ipairs(TABS) do
        local hl = tab == self.active and "leetcode_ctl_tab_active" or "leetcode_ctl_tab"
        local key = Controls.display_key(config.user.hint_keys[tab])
        local label = LABELS[tab] .. (key and (" (%s)"):format(key) or "")
        if tab == "result" and self.status_title then
            label = ("%s %%#%s#%s"):format(label, self.status_hl or hl, (self.status_title:gsub("%%", "%%%%")))
        end
        table.insert(parts, ("%%%d@v:lua._leetcode_ctl.console_tab@%%#%s# %s %%X%%*"):format(i, hl, label))
    end

    local hide = Controls.display_key(config.user.hint_keys.console)
    if hide then
        table.insert(parts, ("%%=%%#leetcode_ctl_key#hide %s %%*"):format(hide))
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
