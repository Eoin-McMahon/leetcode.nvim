local ResultLayout = require("leetcode-ui.renderer.result")
local Runner = require("leetcode.runner")
local problemlist = require("leetcode.cache.problemlist")
local config = require("leetcode.config")
local log = require("leetcode.logger")
local t = require("leetcode.translator")

local EXTMARK_NS = vim.api.nvim_create_namespace("leetcode_extmarks")

---Testcase buffer for the splits layout. Mirrors `popup/console/testcase.lua`
---without the `NuiPopup` dependency, so that file stays as upstream has it.
---@class lc.splits.Testcase
---@field console lc.splits.Console
---@field pane lc.splits.Pane
---@field testcases table<string, string>
---@field testcase_len integer
local Testcase = {}
Testcase.__index = Testcase

function Testcase:bufnr()
    return self.pane.bufnr
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

function Testcase:draw_extmarks()
    if not config.user.console.testcase.virt_text then
        return
    end
    local bufnr = self:bufnr()
    vim.api.nvim_buf_clear_namespace(bufnr, EXTMARK_NS, 0, -1)

    local md = self.console.question.q.meta_data
    if type(md) ~= "table" or not md.params then
        return
    end

    local pad = "  "
    local j, invalid = 1, false
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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
                    { "", "Operator" },
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

function Testcase:reset()
    self:populate()
    log.info("Test cases have been reset")
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
    self.console.layout:show("testcase")
    self.pane:focus()
end

---Result buffer for the splits layout, drawn by the plugin's result renderer.
---@class lc.splits.Result
---@field console lc.splits.Console
---@field pane lc.splits.Pane
---@field renderer lc.ui.Result
---@field last_testcase? string
local Result = {}
Result.__index = Result

function Result:target()
    return { bufnr = self.pane.bufnr, winid = self.pane:is_open() and self.pane.winid or nil }
end

function Result:map(...)
    self.renderer.bufnr = self.pane.bufnr
    self.renderer:map(...)
end

function Result:draw()
    self.renderer:draw(self:target())
end

function Result:clear()
    self.renderer.bufnr = self.pane.bufnr
    self.renderer:clear()
    self.last_testcase = nil
end

---Show a placeholder at once so a click gets feedback before the request leaves.
---@param submit boolean
function Result:pending(submit)
    local bufnr = self.pane.bufnr
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "  " .. (submit and "Submitting…" or "Running…") })
    vim.bo[bufnr].modifiable = false
end

---@param item lc.interpreter_response
function Result:handle(item)
    self.renderer:handle_res(item)
    self.console.layout:set_result_status(item._.hl, item._.title)

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
end

function Result:focus()
    self.console.layout:show("result")
    self.pane:focus()
end

---The `q.console` object for the splits layout. Same interface the runner and
---commands use with the floating console.
---@class lc.splits.Console
---@field question lc.ui.Question
---@field layout lc.splits.Layout
---@field testcase lc.splits.Testcase
---@field result lc.splits.Result
local Console = {}
Console.__index = Console

---@param layout lc.splits.Layout
---@param testcase_pane lc.splits.Pane
---@param result_pane lc.splits.Pane
function Console.new(layout, testcase_pane, result_pane)
    local self = setmetatable({ question = layout.question, layout = layout }, Console)

    self.testcase = setmetatable({
        console = self,
        pane = testcase_pane,
        testcases = {},
        testcase_len = 0,
    }, Testcase)

    self.result = setmetatable({ console = self, pane = result_pane }, Result)
    self.result.renderer = ResultLayout(self)
    self.result.renderer.bufnr = result_pane.bufnr

    self.testcase:populate()
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "InsertLeave" }, {
        buffer = testcase_pane.bufnr,
        callback = function()
            self.testcase:draw_extmarks()
        end,
    })

    return self
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

    if config.user.console.open_on_runcode then
        self.layout:show("result")
    end
    self.layout:set_result_status(nil)
    self.result:pending(submit == true)

    Runner:init(self.question):run(submit)
end

function Console:use_testcase()
    local last = self.result.last_testcase
    if last and last ~= "" then
        self.testcase:append(last)
    else
        log.warn("No testcase to use")
    end
end

function Console:show()
    self.layout:show({ "testcase", "result" })
end

function Console:hide()
    self.layout:hide({ "testcase", "result" })
end

function Console:toggle()
    if self.layout:is_visible("testcase") or self.layout:is_visible("result") then
        self:hide()
    else
        self:show()
    end
end

function Console:unmount() end

return Console
