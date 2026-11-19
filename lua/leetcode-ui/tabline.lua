---Tabline for LeetCode sessions: question tabs show the problem title instead of
---the window count and file name; other tabs look like Neovim's default. In
---stealth mode question tabs show a neutral file name and the menu tab is
---hidden. Only installed when the user has no tabline of their own.
local Tabline = {}

---@param tabp integer
---@return lc.ui.Question?
local function question_in(tabp)
    for _, q in ipairs(_Lc_state.questions) do
        if q.winid and vim.api.nvim_win_is_valid(q.winid) and vim.api.nvim_win_get_tabpage(q.winid) == tabp then
            return q
        end
    end
end

---@param tabp integer
local function is_menu(tabp)
    local menu = _Lc_state.menu
    return menu and menu.winid and vim.api.nvim_win_is_valid(menu.winid) and vim.api.nvim_win_get_tabpage(menu.winid) == tabp
end

---@param tabp integer
---@return string?
local function label(tabp)
    local q = question_in(tabp)
    if q and q.q then
        if vim.g.leetcode_stealth then
            return require("leetcode-ui.stealth").filename_for(q)
        end
        return ("%s. %s"):format(q.q.frontend_id, q.q.title)
    end
    if is_menu(tabp) then
        return not vim.g.leetcode_stealth and "LeetCode" or nil
    end
    local bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tabp))
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
    local modified = vim.bo[bufnr].modified and " +" or ""
    return (name ~= "" and name or "[No Name]") .. modified
end

function Tabline.render()
    local parts = {}
    local current = vim.api.nvim_get_current_tabpage()
    for i, tabp in ipairs(vim.api.nvim_list_tabpages()) do
        local text = label(tabp)
        if text then
            local hl = tabp == current and "%#TabLineSel#" or "%#TabLine#"
            table.insert(parts, ("%s%%%dT %s "):format(hl, i, (text:gsub("%%", "%%%%"))))
        end
    end
    return table.concat(parts) .. "%#TabLineFill#%T"
end

Tabline.expr = "%!v:lua.require'leetcode-ui.tabline'.render()"

function Tabline.setup()
    if vim.o.tabline == "" then
        vim.o.tabline = Tabline.expr
    end
end

return Tabline
