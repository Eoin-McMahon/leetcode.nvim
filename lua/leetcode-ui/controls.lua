local config = require("leetcode.config")

---Clickable Run and Submit in the code window's winbar. The winbar is a plain
---string rebuilt only when state changes, not a `%!` expression, so it costs
---nothing per redraw.
local Controls = {}

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_MS = 100

---@type table<lc.ui.Question, { action?: "run"|"submit", frame: integer, timer?: uv.uv_timer_t }>
local state = setmetatable({}, { __mode = "k" })

---Extra winbar segments, for example restore hints for hidden panes.
---@type (fun(q: lc.ui.Question): string?)[]
Controls.segments = {}

local function question_at_mouse()
    local winid = vim.fn.getmousepos().winid
    if winid == 0 then
        return
    end
    local tabp = vim.api.nvim_win_get_tabpage(winid)
    for _, q in ipairs(_Lc_state.questions) do
        if q.winid and vim.api.nvim_win_is_valid(q.winid) and vim.api.nvim_win_get_tabpage(q.winid) == tabp then
            return q
        end
    end
end

---@param submit boolean
local function click(submit)
    return function()
        local q = question_at_mouse()
        if not q or (state[q] and state[q].action) then
            return
        end
        require("leetcode.utils").auth_guard()
        q.console:run(submit)
    end
end

_G._leetcode_ctl = {
    run = click(false),
    submit = click(true),
    reset = function()
        local q = question_at_mouse()
        if q then
            q.console.testcase:reset()
        end
    end,
    debug = function()
        local q = question_at_mouse()
        if q then
            require("leetcode.debug").toggle(q)
        end
    end,

    add_case = function()
        local q = question_at_mouse()
        if q then
            q.console:use_testcase()
        end
    end,
}

---Render a mapping for display. A space leader becomes `leader_label` (the
---Nerd space icon by default) followed by a space, since wide glyphs overlap
---the next cell in many fonts: `<leader>lh` reads `󱁐 lh`. The result is
---escaped for use in a winbar.
---@param key? string|false
---@return string?
function Controls.display_key(key)
    if not key or key == "" then
        return
    end
    local function lead(value)
        value = value or "\\"
        if value ~= " " then
            return value
        end
        local label = config.user.leader_label or (config.user.nerd_font and "\u{f1050}" or "SPC")
        return label .. " "
    end

    local out = key:gsub("<[Ll]ocal[Ll]eader>", function()
        return lead(vim.g.maplocalleader)
    end):gsub("<[Ll]eader>", function()
        return lead(vim.g.mapleader)
    end)
    return (out:gsub("%%", "%%%%"))
end

---@param key? string
local function key_label(key)
    local shown = Controls.display_key(key)
    if not shown then
        return ""
    end
    return (" %%#leetcode_ctl_key#(%s)"):format(shown)
end

---A clickable `icon (key)` winbar button.
---@param fn string `_G._leetcode_ctl` handler name
---@param icon string
---@param hl string
---@param key_name string `mappings` entry
function Controls.button(fn, icon, hl, key_name)
    return ("%%@v:lua._leetcode_ctl.%s@%%#%s# %s%s %%X%%*"):format(fn, hl, icon, key_label(config.user.mappings[key_name]))
end

---@param q lc.ui.Question
---@param name "run"|"submit"|"debug"
---@param icon string
local function button(q, name, icon)
    local s = state[q]
    local busy = s and s.action == name
    local hl = ({ run = "leetcode_ctl_run", submit = "leetcode_ctl_submit" })[name] or "leetcode_ctl_debug"
    return Controls.button(name, busy and SPINNER[s.frame] or icon, hl, name)
end

---@param q lc.ui.Question
function Controls.build(q)
    local parts = {
        button(q, "run", config.icons.run),
        " ",
        button(q, "submit", config.icons.submit),
        " ",
        button(q, "debug", config.icons.debug),
    }

    local extra = {}
    for _, segment in ipairs(Controls.segments) do
        local text = segment(q)
        if text and text ~= "" then
            table.insert(extra, text)
        end
    end
    if #extra > 0 then
        table.insert(parts, "%=")
        table.insert(parts, table.concat(extra, "  "))
        table.insert(parts, " ")
    end

    return table.concat(parts)
end

---@param q lc.ui.Question
function Controls.render(q)
    if not config.user.editor.controls then
        return
    end
    if not (q.winid and vim.api.nvim_win_is_valid(q.winid)) then
        return
    end
    if q.stealth then
        vim.wo[q.winid].winbar = ""
        return
    end
    vim.wo[q.winid].winbar = Controls.build(q)
end

---@param q lc.ui.Question
---@param action? "run"|"submit"
function Controls.set_running(q, action)
    local s = state[q] or { frame = 1 }
    state[q] = s

    if s.timer then
        s.timer:stop()
        s.timer:close()
        s.timer = nil
    end
    s.action = action
    s.frame = 1

    if action then
        s.timer = vim.uv.new_timer()
        s.timer:start(
            SPINNER_MS,
            SPINNER_MS,
            vim.schedule_wrap(function()
                if not s.action then
                    return
                end
                s.frame = s.frame % #SPINNER + 1
                Controls.render(q)
            end)
        )
    end

    Controls.render(q)
end

function Controls.highlights()
    vim.api.nvim_set_hl(0, "leetcode_ctl_run", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_submit", { link = "DiagnosticInfo", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_key", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_tab_active", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_tab", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_action", { link = "Special", default = true })
    vim.api.nvim_set_hl(0, "leetcode_ctl_debug", { link = "DiagnosticWarn", default = true })

end

return Controls
