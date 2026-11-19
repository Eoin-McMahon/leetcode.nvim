local Controls = require("leetcode-ui.controls")
local Markdown = require("leetcode-ui.splits.markdown")
local article = require("leetcode.api.article")
local config = require("leetcode.config")
local log = require("leetcode.logger")
local utils = require("leetcode.utils")

---@alias lc.splits.Tab "description"|"editorial"|"solutions"|"submissions"

---@type lc.splits.Tab[]
local TABS = { "description", "editorial", "solutions", "submissions" }
local LABELS = {
    description = "Description",
    editorial = "Editorial",
    solutions = "Solutions",
    submissions = "Submissions",
}

local NS = vim.api.nvim_create_namespace("leetcode_side")

---@param key string|string[]
---@return string[]
local function key_list(key)
    return type(key) == "table" and key or { key }
end

---@param bufnr integer
---@param key string|string[]
---@param fn function
local function map(bufnr, key, fn)
    for _, k in ipairs(key_list(key)) do
        vim.keymap.set("n", k, fn, { buffer = bufnr, nowait = true })
    end
end

---@param key string|string[]
local function key_text(key)
    return key_list(key)[1]
end

---Side pane: one window whose buffer switches per tab. Each tab keeps its own
---buffer, filled once in the background, so switching is a buffer swap.
---@class lc.splits.Side
---@field layout lc.splits.Layout
---@field question lc.ui.Question
---@field active lc.splits.Tab
---@field bufs table<lc.splits.Tab, integer>
---@field loaded table<lc.splits.Tab, boolean>
---@field locked table<lc.splits.Tab, boolean>
---@field solutions? lc.article.Summary[]
---@field submissions? lc.article.Submission[]
---@field description_dirty boolean
local Side = {}
Side.__index = Side

---@param layout lc.splits.Layout
---@return lc.splits.Side
function Side.new(layout)
    local self = setmetatable({
        layout = layout,
        question = layout.question,
        active = "description",
        bufs = { description = layout.panes.side.bufnr },
        loaded = { description = true },
        locked = {},
        description_dirty = false,
    }, Side)

    self:map_tab_keys(layout.panes.side.bufnr)
    self:name_buffer("description", layout.panes.side.bufnr)
    self:render_winbar()
    return self
end

---@param bufnr integer
function Side:map_tab_keys(bufnr)
    local keys = config.user.keys
    map(bufnr, keys.tab_next, function()
        self:cycle(1)
    end)
    map(bufnr, keys.tab_prev, function()
        self:cycle(-1)
    end)
    map(bufnr, keys.toggle, function()
        self.layout:hide("side")
    end)
    for tab, key in pairs(keys.side_tabs or {}) do
        map(bufnr, key, function()
            self:select(tab)
        end)
    end
end

---@param tab lc.splits.Tab
---@return integer
function Side:buffer(tab)
    if self.bufs[tab] and vim.api.nvim_buf_is_valid(self.bufs[tab]) then
        return self.bufs[tab]
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    for opt, value in pairs({
        buftype = "nofile",
        bufhidden = "hide",
        swapfile = false,
        modifiable = false,
        filetype = "markdown",
    }) do
        vim.bo[bufnr][opt] = value
    end
    self:map_tab_keys(bufnr)
    self.bufs[tab] = bufnr
    self:name_buffer(tab, bufnr)
    return bufnr
end

---Readable buffer names (`21/Editorial`) instead of `[Scratch]` in the
---statusline and tabline.
---@param tab string
---@param bufnr integer
function Side:name_buffer(tab, bufnr)
    pcall(vim.api.nvim_buf_set_name, bufnr, ("%s/%s"):format(self.question.q.frontend_id, LABELS[tab] or tab))
end

function Side:destroy()
    for _, bufnr in pairs(self.bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
    end
end

---@param tab lc.splits.Tab
---@param lines string[]
---@param marks? { row: integer, hl: string, col?: integer, end_col?: integer }[]
function Side:set_lines(tab, lines, marks)
    local bufnr = self:buffer(tab)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    for _, m in ipairs(marks or {}) do
        vim.api.nvim_buf_set_extmark(bufnr, NS, m.row, m.col or 0, {
            end_col = m.end_col or #lines[m.row + 1],
            hl_group = m.hl,
        })
    end

    if self.active == tab and self.layout.panes.side:is_open() then
        pcall(vim.api.nvim_win_set_cursor, self.layout.panes.side.winid, { 1, 0 })
    end
end

---@param tab lc.splits.Tab
---@param text string
function Side:message(tab, text)
    self:set_lines(tab, { "", "  " .. text }, { { row = 1, hl = "Comment" } })
end

---@param tab lc.splits.Tab
function Side:premium_message(tab)
    self.locked[tab] = true
    self:set_lines(
        tab,
        { "", ("  %s requires LeetCode Premium"):format(LABELS[tab]) },
        { { row = 1, hl = "leetcode_medium" } }
    )
    self:render_winbar()
end

---Tabs as `icon (key)`, with the active one also named and highlighted:
---`▤ Description (d)  ✎ (e)  ☰ (s)  ✓ (u)`. Fits a narrow panel.
function Side:render_winbar()
    local parts = { " " }
    for i, tab in ipairs(TABS) do
        local active = tab == self.active
        local hl = active and "leetcode_ctl_tab_active" or "leetcode_ctl_tab"
        local label = config.icons.tabs[tab]
        if active then
            label = label .. " " .. LABELS[tab]
        end
        local key = (config.user.keys.side_tabs or {})[tab]
        if key then
            label = ("%s (%s)"):format(label, Controls.display_key(key_text(key)))
        end
        table.insert(parts, ("%%%d@v:lua._leetcode_ctl.tab@%%#%s# %s %%X%%*"):format(i, hl, label))
    end
    table.insert(parts, ("%%=%%@v:lua._leetcode_ctl.hide_side@%%#leetcode_ctl_key# %s %%X%%*"):format(config.icons.hide))
    self.layout.panes.side:set_winbar(table.concat(parts, ""))
end

---Draw the description into its tab buffer at the side pane's width.
function Side:render_description()
    local bufnr = self:buffer("description")
    local pane = self.layout.panes.side
    local width = pane:is_open() and vim.api.nvim_win_get_width(pane.winid) or self.last_width or 60
    self.last_width = width

    local out = require("leetcode-ui.splits.description").render(self.question, width)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, out.lines)
    vim.bo[bufnr].modifiable = false

    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    for _, m in ipairs(out.marks) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, m.row, m.col, {
            end_col = math.min(m.end_col, #out.lines[m.row + 1]),
            hl_group = m.hl,
        })
    end
    for _, l in ipairs(out.line_hls) do
        vim.api.nvim_buf_set_extmark(bufnr, NS, l.row, 0, { line_hl_group = l.hl })
    end
    self.links = out.links

    if not self.links_mapped then
        self.links_mapped = true
        vim.keymap.set("n", "gx", function()
            local url = self.links[vim.api.nvim_win_get_cursor(0)[1]]
            if url then
                vim.ui.open(url)
            else
                vim.cmd("normal! gx")
            end
        end, { buffer = bufnr, nowait = true })
    end
end

---@param tab lc.splits.Tab
function Side:select(tab)
    self.active = tab
    self.layout:show("side")
    self.layout.panes.side:set_buf(self:buffer(tab))
    self:render_winbar()

    if tab == "description" and self.description_dirty then
        self.description_dirty = false
        self:render_description()
    end

    self:load(tab)
end

---@param step integer
function Side:cycle(step)
    local idx = 1
    for i, tab in ipairs(TABS) do
        if tab == self.active then
            idx = i
        end
    end
    self:select(TABS[(idx - 1 + step) % #TABS + 1])
end

function Side:prefetch()
    for _, tab in ipairs({ "editorial", "solutions", "submissions" }) do
        self:load(tab)
    end
end

---@param tab lc.splits.Tab
---@param force? boolean
function Side:load(tab, force)
    if self.loaded[tab] and not force then
        return
    end
    self.loaded[tab] = true

    if tab == "editorial" then
        self:load_editorial()
    elseif tab == "solutions" then
        self:load_solutions()
    elseif tab == "submissions" then
        self:load_submissions()
    end
end

function Side:load_editorial()
    local q = self.question.q
    local solution = q.solution

    if solution == vim.NIL then
        return self:message("editorial", "No editorial for this question")
    end
    -- `solution` is missing from payloads cached before it was queried; fetch
    -- then and let the response decide.
    if type(solution) == "table" and solution.paidOnly and not config.auth.is_premium then
        return self:premium_message("editorial")
    end

    if not self.bufs.editorial then
        self:message("editorial", "Loading editorial…")
    end

    article.editorial(q.title_slug, function(res, err)
        if not res then
            return self:message("editorial", "No editorial for this question")
        end
        if res.content == "" then
            if config.auth.is_premium then
                return self:message("editorial", "No editorial for this question")
            end
            return self:premium_message("editorial")
        end

        local lines, uuids = Markdown.clean(res.content)
        table.insert(lines, 1, "# " .. res.title)
        table.insert(lines, 2, "")

        local lang = self.question.lang
        local ft = utils.get_lang(lang).ft
        local codes = {}
        self:set_lines("editorial", Markdown.fill_playgrounds(lines, codes, lang, ft))

        for _, uuid in ipairs(uuids) do
            article.playground(uuid, function(list)
                codes[uuid] = list or {}
                self:set_lines("editorial", Markdown.fill_playgrounds(lines, codes, lang, ft))
            end)
        end
    end)
end

---@param n integer
local function short_number(n)
    if n >= 1e6 then
        return ("%.1fM"):format(n / 1e6)
    elseif n >= 1e3 then
        return ("%.1fk"):format(n / 1e3)
    end
    return tostring(n)
end

function Side:load_solutions()
    if not self.solutions then
        self:message("solutions", "Loading solutions…")
    end

    article.solutions(self.question.q.title_slug, function(list, err)
        if not list then
            return self:message("solutions", "Could not load solutions")
        end
        self.solutions = list
        self:render_solution_list()

        local bufnr = self:buffer("solutions")
        map(bufnr, config.user.keys.confirm, function()
            self:open_solution()
        end)
        map(bufnr, config.user.keys.back, function()
            self:render_solution_list()
        end)
    end)
end

function Side:render_solution_list()
    local keys = config.user.keys
    local lines = { "", ("  %s open  %s back to list"):format(key_text(keys.confirm), key_text(keys.back)), "" }
    local marks = { { row = 1, hl = "Comment" } }
    self.solution_rows = {}

    for _, s in ipairs(self.solutions or {}) do
        local votes = 0
        for _, r in ipairs(s.reactions or {}) do
            votes = votes + (r.count or 0)
        end
        local stats = ("%6s %s %6s views  "):format(short_number(votes), config.icons.upvote, short_number(s.hitCount or 0))
        local author = type(s.author) == "table" and s.author.userName or "?"
        table.insert(lines, ("%s%s · %s"):format(stats, s.title, author))
        table.insert(marks, { row = #lines - 1, hl = "Comment", end_col = #stats })
        self.solution_rows[#lines] = s
    end

    self:set_lines("solutions", lines, marks)
    vim.bo[self:buffer("solutions")].filetype = config.name
end

function Side:open_solution()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local s = self.solution_rows and self.solution_rows[row]
    if not s then
        return
    end

    self:message("solutions", "Loading " .. s.title .. "…")
    article.solution(s.topicId, function(res)
        if not res then
            return self:message(
                "solutions",
                ("Could not load this solution. %s back to list"):format(key_text(config.user.keys.back))
            )
        end
        local lines = Markdown.clean(res.content)
        local author = type(res.author) == "table" and res.author.userName or "?"
        table.insert(lines, 1, "# " .. res.title)
        table.insert(lines, 2, ("_by %s_  (%s back to list)"):format(author, key_text(config.user.keys.back)))
        table.insert(lines, 3, "")
        self.solution_rows = {}
        self:set_lines("solutions", lines)
        vim.bo[self:buffer("solutions")].filetype = "markdown"
    end)
end

function Side:load_submissions()
    if not self.submissions then
        self:message("submissions", "Loading submissions…")
    end

    article.submissions(self.question.q.title_slug, function(list)
        if not list then
            return self:message("submissions", "Could not load submissions")
        end
        self.submissions = list
        if #list == 0 then
            return self:message("submissions", "No submissions yet")
        end

        local lines = { "", ("  %s load into editor"):format(key_text(config.user.keys.confirm)), "" }
        local marks = { { row = 1, hl = "Comment" } }
        local rows = {}
        for _, s in ipairs(list) do
            local ok = s.statusDisplay == "Accepted"
            local status = ("%-22s"):format(s.statusDisplay)
            local when = os.date("%Y-%m-%d %H:%M", tonumber(s.timestamp) or 0)
            table.insert(lines, ("  %s %-8s %-9s %-10s %s"):format(status, s.runtime, s.memory, s.lang, when))
            table.insert(marks, {
                row = #lines - 1,
                col = 2,
                end_col = 2 + #status,
                hl = ok and "leetcode_ok" or "leetcode_error",
            })
            rows[#lines] = s
        end
        self.submission_rows = rows
        self:set_lines("submissions", lines, marks)
        vim.bo[self:buffer("submissions")].filetype = config.name

        map(self:buffer("submissions"), config.user.keys.confirm, function()
            self:load_submission()
        end)
    end)
end

function Side:load_submission()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local s = self.submission_rows and self.submission_rows[row]
    if not s then
        return
    end
    article.submission_code(s.id, function(res)
        if not res then
            return log.error("Could not load submission " .. s.id)
        end
        self.question:editor_section_replace(res.code, "code")
        log.info("Loaded submission from " .. os.date("%Y-%m-%d %H:%M", tonumber(s.timestamp) or 0))
    end)
end

_G._leetcode_ctl.tab = function(minwid)
    local winid = vim.fn.getmousepos().winid
    for _, q in ipairs(_Lc_state.questions) do
        if q.layout and q.layout.panes.side.winid == winid then
            q.layout.side:select(TABS[minwid])
        end
    end
end

Side.TABS = TABS

return Side
