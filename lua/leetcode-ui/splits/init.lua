local Pane = require("leetcode-ui.splits.pane")
local Console = require("leetcode-ui.splits.console")
local Controls = require("leetcode-ui.controls")
local config = require("leetcode.config")
local timings = require("leetcode.timings")

---@alias lc.splits.PaneName "side"|"console"

---@class lc.splits.Entry
---@field pane lc.splits.PaneName
---@field dir "left"|"right"|"above"|"below"
---@field parent "code"|lc.splits.PaneName
---@field size fun(): number fraction of the tab, or of the parent for nested panes
---@field nested? boolean

local function side_width()
    return config.user.splits.side.width
end
local function console_size()
    return config.user.splits.console.size
end

---Panes open in order, each relative to its parent window, so the website
---console sits under the code window only, not across the whole tab.
---@type table<string, lc.splits.Entry[]>
local PRESETS = {
    website = {
        { pane = "side", dir = "left", parent = "code", size = side_width },
        { pane = "console", dir = "below", parent = "code", size = console_size },
    },
    wide = {
        { pane = "side", dir = "left", parent = "code", size = side_width },
        { pane = "console", dir = "right", parent = "code", size = console_size },
    },
}

local PRESET_ORDER = { "website", "wide" }

local HINT_LABELS = { side = "side panel", console = "console" }

---Owns the windows of one question tab in the splits layout.
---@class lc.splits.Layout
---@field question lc.ui.Question
---@field preset string
---@field panes table<lc.splits.PaneName, lc.splits.Pane>
---@field sizes table<string, table<lc.splits.PaneName, integer>> live sizes per preset
---@field console lc.splits.Console
---@field side lc.splits.Side
---@field applying boolean
local Layout = {}
Layout.__index = Layout

local group = vim.api.nvim_create_augroup("leetcode_splits", { clear = true })

---@param question lc.ui.Question
---@return lc.splits.Layout
function Layout.new(question)
    local self = setmetatable({
        question = question,
        preset = PRESETS[config.user.splits.preset] and config.user.splits.preset or "website",
        sizes = {},
        applying = false,
    }, Layout)

    self.panes = {
        side = Pane.new("side", {
            bufnr = question.description.bufnr,
            buf_opts = {
                modifiable = false,
                buftype = "nofile",
                filetype = config.name,
                matchpairs = "",
                synmaxcol = 0,
            },
            win_opts = {
                wrap = true,
                linebreak = true,
                colorcolumn = "",
                foldlevel = 999,
                conceallevel = 2,
            },
        }),
        console = Pane.new("console", {
            buf_opts = { modifiable = true, buftype = "nofile", filetype = config.name .. "-testcase" },
            win_opts = { wrap = true, linebreak = true },
        }),
    }

    local result_buf = vim.api.nvim_create_buf(false, true)
    for opt, value in pairs({
        modifiable = false,
        buftype = "nofile",
        bufhidden = "hide",
        swapfile = false,
        filetype = config.name,
    }) do
        vim.bo[result_buf][opt] = value
    end

    self.console = Console.new(self, self.panes.console, result_buf)
    self.side = require("leetcode-ui.splits.side").new(self)
    self:set_keymaps()

    return self
end

---@param name lc.splits.PaneName
---@return boolean
function Layout:is_visible(name)
    return self.panes[name].visible
end

---@param names lc.splits.PaneName|lc.splits.PaneName[]
---@param visible boolean
function Layout:set_visible(names, visible)
    names = type(names) == "table" and names or { names }
    local changed = false
    for _, name in ipairs(names) do
        if self.panes[name].visible ~= visible then
            self.panes[name].visible = visible
            changed = true
        end
    end
    if changed then
        self:apply()
    end
end

---@param names lc.splits.PaneName|lc.splits.PaneName[]
function Layout:show(names)
    self:set_visible(names, true)
end

---@param names lc.splits.PaneName|lc.splits.PaneName[]
function Layout:hide(names)
    self:set_visible(names, false)
end

---@param name lc.splits.PaneName
function Layout:toggle(name)
    self:set_visible(name, not self.panes[name].visible)
end

---@param name? string preset name, or nil to cycle
function Layout:set_preset(name)
    if not name then
        local idx = 1
        for i, n in ipairs(PRESET_ORDER) do
            if n == self.preset then
                idx = i
            end
        end
        name = PRESET_ORDER[idx % #PRESET_ORDER + 1]
    end
    if not PRESETS[name] or name == self.preset then
        return
    end

    self:remember_sizes()
    self:close_panes()
    self.preset = name
    self:apply()
end

---@private
function Layout:remember_sizes()
    local sizes = self.sizes[self.preset] or {}
    for _, entry in ipairs(PRESETS[self.preset]) do
        local size = self.panes[entry.pane]:size(entry.dir == "left" or entry.dir == "right")
        if size then
            sizes[entry.pane] = size
        end
    end
    self.sizes[self.preset] = sizes
end

---@private
function Layout:close_panes()
    self.applying = true
    for _, pane in pairs(self.panes) do
        pane:close()
    end
    self.applying = false
end

---@param entry lc.splits.Entry
---@param parent_win integer
---@return integer
function Layout:size_for(entry, parent_win)
    local remembered = (self.sizes[self.preset] or {})[entry.pane]
    if remembered then
        return remembered
    end

    local vertical = entry.dir == "left" or entry.dir == "right"
    local total
    if entry.nested then
        total = vertical and vim.api.nvim_win_get_width(parent_win) or vim.api.nvim_win_get_height(parent_win)
    else
        total = vertical and vim.o.columns or (vim.o.lines - vim.o.cmdheight - 2)
    end
    return math.max(1, math.floor(total * entry.size()))
end

---Close every pane and reopen the visible ones in preset order. Rebuilding is
---the only way to keep a full-height side pane after the console changes, and
---it all runs in one call, so Neovim redraws once.
function Layout:apply()
    local code_win = self.question.winid
    if not (code_win and vim.api.nvim_win_is_valid(code_win)) then
        return
    end

    local stop_timing = timings.start("layout apply " .. self.preset)
    local current = vim.api.nvim_get_current_win()
    local focused_pane
    for name, pane in pairs(self.panes) do
        if pane.winid == current then
            focused_pane = name
        end
    end

    self:remember_sizes()
    self:close_panes()

    self.applying = true
    for _, entry in ipairs(PRESETS[self.preset]) do
        local pane = self.panes[entry.pane]
        if pane.visible then
            local parent = entry.parent == "code" and code_win or self.panes[entry.parent].winid
            if not (parent and vim.api.nvim_win_is_valid(parent)) then
                parent = code_win
            end
            pane:open(parent, entry.dir, self:size_for(entry, parent))
            self:watch(pane)
        end
    end
    self.applying = false

    if focused_pane and self.panes[focused_pane]:is_open() then
        self.panes[focused_pane]:focus()
    elseif vim.api.nvim_win_is_valid(current) then
        vim.api.nvim_set_current_win(current)
    else
        vim.api.nvim_set_current_win(code_win)
    end

    Controls.render(self.question)
    stop_timing()
end

---Closing a pane window by hand (`<C-w>c`, `:q`, `<C-w>o`) counts as hiding it.
---@private
---@param pane lc.splits.Pane
function Layout:watch(pane)
    local winid = pane.winid
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(winid),
        once = true,
        callback = function()
            if self.applying or pane.winid ~= winid then
                return
            end
            pane.cursor = nil
            pane.winid = nil
            pane.visible = false
            vim.schedule(function()
                Controls.render(self.question)
            end)
        end,
    })
end

---@private
function Layout:set_keymaps()
    local keys = config.user.keys
    local console = self.console
    local function map(bufnr, key, fn)
        for _, k in ipairs(type(key) == "table" and key or { key }) do
            vim.keymap.set("n", k, fn, { buffer = bufnr, nowait = true })
        end
    end

    -- The testcase buffer is edited like any file, so it only gets keys that do
    -- not shadow common motions. The result buffer is read-only.
    for _, bufnr in ipairs({ console.testcase_buf, console.result_buf }) do
        map(bufnr, keys.tab_next, function()
            console:cycle()
        end)
        map(bufnr, keys.tab_prev, function()
            console:cycle()
        end)
    end
    map(console.result_buf, keys.toggle, function()
        self:hide("console")
    end)
    map(console.result_buf, keys.use_testcase, function()
        console:use_testcase()
    end)
end

---Restore hints for hidden panes, shown in the code window's winbar.
---@param q lc.ui.Question
---@return string?
function Layout.hints(q)
    local self = q.layout
    if not self then
        return
    end

    local parts = {}
    for _, name in ipairs({ "side", "console" }) do
        if not self.panes[name].visible then
            local key = Controls.display_key(config.user.hint_keys[name])
            local text = HINT_LABELS[name] .. " hidden"
            if key then
                text = ("%s: %%#leetcode_ctl_key#%s%%*"):format(text, key)
            end
            table.insert(parts, "%#Comment#" .. text .. "%*")
        end
    end
    return table.concat(parts, "  ")
end

---Reset and add-failed-case buttons, right-aligned in the code winbar.
---@param q lc.ui.Question
---@return string?
function Layout.actions(q)
    if not q.layout then
        return
    end
    local function button(fn, icon, label, key_name)
        local key = Controls.display_key(config.user.hint_keys[key_name])
        return ("%%@v:lua._leetcode_ctl.%s@%%#leetcode_ctl_action# %s %s%s %%X%%*"):format(
            fn,
            icon,
            label,
            key and (" %#leetcode_ctl_key#" .. key) or ""
        )
    end
        return button("reset", config.icons.reset, "Reset cases", "reset")
        .. button("add_case", config.icons.add, "Add failed case", "add_case")
end

table.insert(Controls.segments, Layout.actions)
table.insert(Controls.segments, Layout.hints)

function Layout:unmount()
    self.applying = true
    for name, pane in pairs(self.panes) do
        -- The side buffer belongs to the description and is wiped with it.
        if name == "side" then
            pane:close()
        else
            pane:destroy()
        end
    end
    self.console:destroy()
end

Layout.PRESETS = PRESETS

return Layout
