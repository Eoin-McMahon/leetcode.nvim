local config = require("leetcode.config")

---The `@leet ... start/end` lines mark which code gets submitted, so they must
---stay in the buffer. They are hidden with `conceal_lines` extmarks instead.
local Tags = {}

local ns = vim.api.nvim_create_namespace("leetcode_tags")
local group = vim.api.nvim_create_augroup("leetcode_tags", { clear = true })

---@param bufnr integer
---@return boolean
function Tags.hidden(bufnr)
    local value = vim.b[bufnr].leetcode_tags_hidden
    if value == nil then
        return config.user.editor.hide_tags
    end
    return value
end

---@param line string
---@return integer? col
local function tag_col(line)
    local col = line:find("@leet", 1, true)
    if not col then
        return
    end
    local rest = line:sub(col)
    if rest:match("^@leet[%w ]-start%s*$") or rest:match("^@leet[%w ]-end%s*$") then
        return col - 1
    end
end

---@param bufnr integer
function Tags.refresh(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    local hide = Tags.hidden(bufnr)

    for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local col = tag_col(line)
        if col then
            vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, col, {
                end_col = #line,
                hl_group = "DiagnosticHint",
                conceal_lines = hide and "" or nil,
            })
        end
    end
end

---Fold text that names a tagged section (`# imports (36 lines)`) instead of
---showing its `@leet` start line.
function Tags.foldtext()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.fn.getline(vim.v.foldstart)
    local col = tag_col(line)
    if not (col and Tags.hidden(bufnr)) then
        return vim.fn.foldtext()
    end

    local name = line:sub(col + 1):match("^@leet (%w+) start") or "code"
    local count = vim.v.foldend - vim.v.foldstart + 1
    return ("%s%s (%d lines)"):format(line:sub(1, col), name, count)
end

---@param winid integer
local function set_win_opts(winid)
    if not vim.api.nvim_win_is_valid(winid) then
        return
    end
    if vim.wo[winid].conceallevel == 0 then
        vim.api.nvim_set_option_value("conceallevel", 2, { scope = "local", win = winid })
    end
    vim.api.nvim_set_option_value(
        "foldtext",
        "v:lua.require'leetcode-ui.tags'.foldtext()",
        { scope = "local", win = winid }
    )
end

---@param bufnr integer
---@param winid integer
function Tags.attach(bufnr, winid)
    set_win_opts(winid)
    Tags.refresh(bufnr)

    if vim.b[bufnr].leetcode_tags_attached then
        return
    end
    vim.b[bufnr].leetcode_tags_attached = true

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = bufnr,
        callback = function()
            Tags.refresh(bufnr)
        end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        buffer = bufnr,
        callback = function()
            set_win_opts(vim.api.nvim_get_current_win())
        end,
    })
end

---@param bufnr integer
function Tags.toggle(bufnr)
    vim.b[bufnr].leetcode_tags_hidden = not Tags.hidden(bufnr)
    Tags.refresh(bufnr)
end

return Tags
