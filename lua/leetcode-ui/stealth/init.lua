local Controls = require("leetcode-ui.controls")
local Names = require("leetcode-ui.stealth.names")
local Overlay = require("leetcode-ui.stealth.overlay")
local Tags = require("leetcode-ui.tags")
local utils = require("leetcode.utils")

---Stealth mode: hide every LeetCode marker in question tabs and disguise the
---code. Global, so a question opened while it is on starts disguised.
local Stealth = {}

Stealth.active = false

---@type { statusline: string, tabline: string, titlestring: string }?
local saved_opts

---@param bufnr integer
---@return lc.ui.Question?
local function question_for(bufnr)
    for _, q in ipairs(_Lc_state.questions) do
        if q.bufnr == bufnr then
            return q
        end
    end
end

---@param q lc.ui.Question
function Stealth.filename_for(q)
    return Names.filename(q.q.title_slug, utils.get_lang(q.lang).ft)
end

---Statusline replacement for `%f`.
function Stealth.filename()
    local winid = vim.g.statusline_winid or vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local q = question_for(bufnr)
    if q then
        return Stealth.filename_for(q)
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    return name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
end

function Stealth.tabline()
    local parts = {}
    local current = vim.api.nvim_get_current_tabpage()
    for i, tabp in ipairs(vim.api.nvim_list_tabpages()) do
        local bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tabp))
        local q = question_for(bufnr)
        local label = q and Stealth.filename_for(q) or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
        local hl = tabp == current and "%#TabLineSel#" or "%#TabLine#"
        table.insert(parts, ("%s%%%dT %s "):format(hl, i, label ~= "" and label or "[No Name]"))
    end
    return table.concat(parts) .. "%#TabLineFill#%T"
end

---@param q lc.ui.Question
function Stealth.apply(q)
    if q.stealth then
        return
    end
    q.stealth = true

    if q.layout then
        q.stealth_panes = {}
        for name, pane in pairs(q.layout.panes) do
            q.stealth_panes[name] = pane.visible
        end
        q.layout:hide({ "side", "console" })
    else
        pcall(function()
            q.description:hide()
            q.console:hide()
        end)
    end

    q.stealth_tags = vim.b[q.bufnr].leetcode_tags_hidden
    vim.b[q.bufnr].leetcode_tags_hidden = true
    Tags.refresh(q.bufnr)
    q.stealth_diagnostics = vim.diagnostic.is_enabled({ bufnr = q.bufnr })
    vim.diagnostic.enable(false, { bufnr = q.bufnr })

    Controls.render(q)
    Overlay.attach(q)
end

---@param q lc.ui.Question
function Stealth.restore(q)
    if not q.stealth then
        return
    end
    q.stealth = false
    Overlay.detach(q)

    if q.layout and q.stealth_panes then
        local show = {}
        for name, visible in pairs(q.stealth_panes) do
            if visible then
                table.insert(show, name)
            end
        end
        q.layout:show(show)
    end

    vim.b[q.bufnr].leetcode_tags_hidden = q.stealth_tags
    Tags.refresh(q.bufnr)
    vim.diagnostic.enable(q.stealth_diagnostics ~= false, { bufnr = q.bufnr })
    Controls.render(q)
end

local function override_ui()
    saved_opts = {
        statusline = vim.o.statusline,
        tabline = vim.o.tabline,
        titlestring = vim.o.titlestring,
    }
    local statusline = vim.o.statusline ~= "" and vim.o.statusline or "%<%f %h%m%r%=%-14.(%l,%c%V%) %P"
    vim.o.statusline = statusline:gsub("%%f", "%%{v:lua.require'leetcode-ui.stealth'.filename()}")
    vim.o.tabline = require("leetcode-ui.tabline").expr
    vim.o.titlestring = "%{v:lua.require'leetcode-ui.stealth'.filename()}"
end

local function restore_ui()
    if saved_opts then
        vim.o.statusline = saved_opts.statusline
        vim.o.tabline = saved_opts.tabline
        vim.o.titlestring = saved_opts.titlestring
        saved_opts = nil
    end
end

function Stealth.enable()
    if Stealth.active then
        return
    end
    Stealth.active = true
    vim.g.leetcode_stealth = true
    override_ui()
    for _, q in ipairs(_Lc_state.questions) do
        Stealth.apply(q)
    end
    vim.cmd("redrawstatus! | redrawtabline")
end

function Stealth.disable()
    if not Stealth.active then
        return
    end
    Stealth.active = false
    vim.g.leetcode_stealth = false
    for _, q in ipairs(_Lc_state.questions) do
        Stealth.restore(q)
    end
    restore_ui()
    vim.cmd("redrawstatus! | redrawtabline")
end

function Stealth.toggle()
    if Stealth.active then
        Stealth.disable()
    else
        Stealth.enable()
    end
end

return Stealth
