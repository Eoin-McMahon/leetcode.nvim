local config = require("leetcode.config")

---Floating window with the sign-in state: who, premium, where the cookie came
---from and how old it is, and the last request that worked and that failed.
local Auth = {}

---@param at? integer
local function ago(at)
    if not at then
        return "never"
    end
    local s = os.time() - at
    if s < 60 then
        return s .. "s ago"
    elseif s < 3600 then
        return math.floor(s / 60) .. "m ago"
    elseif s < 86400 then
        return math.floor(s / 3600) .. "h ago"
    end
    return math.floor(s / 86400) .. "d ago"
end

function Auth.status()
    local auth = config.auth or {}
    local activity = require("leetcode.api.utils").activity or {}
    local cookie_file = config.storage.cache:joinpath("cookie"):absolute()
    local cookie_time = vim.fn.getftime(cookie_file)
    local ok_browser, browser = pcall(require, "leetcode.cache.browser")
    local app = ok_browser and browser.app() or nil
    local mappings = config.user.mappings or {}
    local controls = require("leetcode-ui.controls")

    local rows = {
        { "Signed in", auth.is_signed_in and ("yes, as " .. tostring(auth.name)) or "no" },
        { "Premium", auth.is_premium and "yes" or "no" },
        { "Session", auth.session_id and tostring(auth.session_id) or "-" },
        { "Cookie saved", cookie_time > 0 and (os.date("%Y-%m-%d %H:%M", cookie_time) .. " (" .. ago(cookie_time) .. ")") or "none" },
        { "Browser", app and (app .. " (cookies and User-Agent)") or "none found" },
        { "Last request ok", activity.ok and (ago(activity.ok.at) .. "  " .. activity.ok.endpoint) or "none yet" },
    }
    if activity.err then
        table.insert(rows, {
            "Last failure",
            ("%s  %s %s"):format(ago(activity.err.at), activity.err.status or "", activity.err.endpoint),
        })
        table.insert(rows, { "", tostring(activity.err.msg or "") })
    end

    local lines, marks = { "" }, {}
    for _, r in ipairs(rows) do
        local label = ("  %-16s"):format(r[1])
        table.insert(lines, label .. r[2])
        table.insert(marks, { row = #lines - 1, col = 0, end_col = #label, hl = "leetcode_desc_dim" })
    end
    table.insert(lines, "")
    local hint = {}
    for _, item in ipairs({ { "login_browser", "sign in from browser" }, { "login_cookie", "paste a cookie" }, { "logout", "sign out" } }) do
        local key = controls.display_key(mappings[item[1]])
        if key then
            table.insert(hint, (key:gsub("%%%%", "%%")) .. " " .. item[2])
        end
    end
    if #hint > 0 then
        local line = "  " .. table.concat(hint, "   ")
        table.insert(lines, line)
        table.insert(marks, { row = #lines - 1, col = 0, end_col = #line, hl = "leetcode_desc_dim" })
        table.insert(lines, "")
    end

    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, vim.api.nvim_strwidth(l))
    end
    width = math.min(width + 2, vim.o.columns - 4)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].bufhidden = "wipe"
    local ns = vim.api.nvim_create_namespace("leetcode_auth")
    for _, m in ipairs(marks) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, m.row, m.col, { end_col = m.end_col, hl_group = m.hl })
    end
    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - #lines) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = #lines,
        style = "minimal",
        border = "rounded",
        title = " LeetCode account ",
        title_pos = "center",
        zindex = 60,
    })
    vim.wo[win].wrap = true
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(vim.api.nvim_win_close, win, true)
        end, { buffer = bufnr, nowait = true })
    end
end

return Auth
