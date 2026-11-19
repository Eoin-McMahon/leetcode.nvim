local config = require("leetcode.config")

---The `@leet ... start/end` lines mark which code gets submitted, so they must
---stay in the buffer. They are hidden with `conceal_lines` extmarks instead.
local Tags = {}

local ns = vim.api.nvim_create_namespace("leetcode_tags")
local group = vim.api.nvim_create_augroup("leetcode_tags", { clear = true })

---Concealed rows (1-based) per buffer. Neovim shows a concealed line while the
---cursor is on it, so the cursor is kept off these.
---@type table<integer, table<integer, boolean>>
local concealed = {}

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
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local rows = {}
    concealed[bufnr] = rows

    -- With tags hidden the editor shows only the solution, like the website:
    -- the imports section and the blank lines up to the code start tag go too.
    -- Stealth keeps one blank line there, since its decoy code hangs below it.
    local hidden_until = 0
    if hide then
        for i, line in ipairs(lines) do
            if line:find("@leet start", 1, true) and line:match("@leet start%s*$") then
                hidden_until = i - 1
                break
            end
        end
        if vim.g.leetcode_stealth and config.user.stealth.decoy and hidden_until > 0 then
            if vim.trim(lines[hidden_until]) == "" then
                hidden_until = hidden_until - 1
            end
        end
    end

    for i, line in ipairs(lines) do
        local col = tag_col(line)
        if col then
            vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, col, {
                end_col = #line,
                hl_group = "DiagnosticHint",
                conceal_lines = hide and "" or nil,
            })
            rows[i] = hide or nil
        elseif i <= hidden_until then
            vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, { conceal_lines = "" })
            rows[i] = true
        end
    end

    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
        Tags.skip_concealed(winid, 1)
    end

    -- A closed fold over concealed lines still draws its fold line.
    if hidden_until > 0 then
        for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
            vim.api.nvim_win_call(winid, function()
                if vim.fn.foldclosed(1) ~= -1 then
                    pcall(vim.cmd, ("silent! 1,%dfoldopen!"):format(hidden_until))
                end
            end)
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

---Move the cursor off a concealed line, in the direction it was moving.
---@param winid integer
---@param dir 1|-1
function Tags.skip_concealed(winid, dir)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local rows = concealed[bufnr]
    if not rows then
        return
    end
    local row = vim.api.nvim_win_get_cursor(winid)[1]
    if not rows[row] then
        return
    end

    local count = vim.api.nvim_buf_line_count(bufnr)
    for _, step in ipairs({ dir, -dir }) do
        local r = row
        while r >= 1 and r <= count do
            if not rows[r] then
                vim.api.nvim_win_set_cursor(winid, { r, 0 })
                return
            end
            r = r + step
        end
    end
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
    local last_row = {}
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        buffer = bufnr,
        callback = function()
            local winid = vim.api.nvim_get_current_win()
            local row = vim.api.nvim_win_get_cursor(winid)[1]
            local dir = (last_row[winid] and row < last_row[winid]) and -1 or 1
            Tags.skip_concealed(winid, dir)
            last_row[winid] = vim.api.nvim_win_get_cursor(winid)[1]
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
