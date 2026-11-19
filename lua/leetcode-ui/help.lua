local config = require("leetcode.config")

---Floating list of every LeetCode key, grouped by what it acts on. Opened
---with g? in the menu and in a problem's buffers.
local Help = {}

local GROUPS = {
    { "Code", { "run", "submit", "debug", "last_submit", "reset_code", "lang", "fullscreen" } },
    { "Tests", { "console", "new_case", "testcase", "reset", "result", "add_case" } },
    {
        "Left panel",
        { "tab_description", "tab_editorial", "tab_solutions", "tab_submissions", "side", "side_fullscreen" },
    },
    { "Problems", { "list", "recent", "random", "daily" } },
    { "General", { "menu", "layout", "stealth", "key_hints", "signin", "exit" } },
}

---@return { [1]: string, [2]: string }[] key and description, for keys inside the panels
local function panel_keys()
    local keys = config.user.keys
    local function first(k)
        return type(k) == "table" and k[1] or k
    end
    return {
        { first(keys.tab_next) .. " / " .. first(keys.tab_prev), "Next / previous tab" },
        { first(keys.confirm), "Open the item or press the button under the cursor" },
        { first(keys.back), "Back from an opened solution or submission" },
        { "<Esc>", "Leave fullscreen" },
        { first(keys.toggle), "Collapse the panel" },
        { "g?", "This help" },
    }
end

function Help.open()
    local controls = require("leetcode-ui.controls")
    local actions = require("leetcode.command").mapping_actions
    local mappings = config.user.mappings or {}

    local lines, marks = { "" }, {}
    local function heading(text)
        table.insert(lines, "  " .. text)
        table.insert(marks, { row = #lines - 1, col = 2, end_col = 2 + #text, hl = "leetcode_desc_heading" })
    end
    local function entry(key, desc)
        local shown = (key:gsub("%%%%", "%%"))
        local pad = (" "):rep(math.max(18 - vim.api.nvim_strwidth(shown), 1))
        local line = "    " .. shown .. pad .. desc
        table.insert(lines, line)
        table.insert(marks, { row = #lines - 1, col = 4, end_col = 4 + #shown, hl = "leetcode_menu_key" })
    end

    for _, group in ipairs(GROUPS) do
        local rows = {}
        for _, name in ipairs(group[2]) do
            local key = controls.display_key(mappings[name])
            if key and actions[name] then
                table.insert(rows, { key, actions[name][2] })
            end
        end
        if #rows > 0 then
            heading(group[1])
            for _, r in ipairs(rows) do
                entry(r[1], r[2])
            end
            table.insert(lines, "")
        end
    end
    heading("Inside a panel")
    for _, r in ipairs(panel_keys()) do
        entry(r[1], r[2])
    end
    table.insert(lines, "")

    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, vim.api.nvim_strwidth(l))
    end
    width = math.min(width + 2, vim.o.columns - 4)
    local height = math.min(#lines, vim.o.lines - 6)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].bufhidden = "wipe"
    local ns = vim.api.nvim_create_namespace("leetcode_help")
    for _, m in ipairs(marks) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, m.row, m.col, { end_col = m.end_col, hl_group = m.hl })
    end

    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " LeetCode keys ",
        title_pos = "center",
        zindex = 60,
    })
    for _, key in ipairs({ "q", "<Esc>", "g?" }) do
        vim.keymap.set("n", key, function()
            pcall(vim.api.nvim_win_close, win, true)
        end, { buffer = bufnr, nowait = true })
    end
end

return Help
