local Names = require("leetcode-ui.stealth.names")
local config = require("leetcode.config")
local utils = require("leetcode.utils")

---Display-only disguise for the code buffer. Nothing here edits the buffer, so
---run, submit, save and the `@leet` tag search all see the real code.
local Overlay = {}

local NS = vim.api.nvim_create_namespace("leetcode_stealth")
local group = vim.api.nvim_create_augroup("leetcode_stealth", { clear = true })

---@type table<string, string[][][]> highlighted decoy chunks per lang and side
local decoy_cache = {}

---@param q lc.ui.Question
---@return string? ts_lang
local function ts_lang(q)
    -- `ft` in the language table is a file extension ("py"), not a filetype.
    local ext = utils.get_lang(q.lang).ft
    local filetype = vim.filetype.match({ filename = "solution." .. ext }) or ext
    return vim.treesitter.language.get_lang(filetype) or filetype
end

---The one name that gives a LeetCode file away: the `Solution` class, or the
---design question's class (`LRUCache`). Method and parameter names read as
---ordinary code and stay.
---@param q lc.ui.Question
---@return { name: string, kind: "type" }[]
function Overlay.symbols(q)
    local md = q.q.meta_data
    local name = type(md) == "table" and md.systemdesign and md.classname or "Solution"
    if not (q:snippet(true) or ""):find(name, 1, true) then
        return {}
    end
    return { { name = name, kind = "type" } }
end

---@param bufnr integer
---@param row integer
---@param col integer
local function hl_at(bufnr, row, col)
    local ok, captures = pcall(vim.treesitter.get_captures_at_pos, bufnr, row, col)
    if ok and captures and #captures > 0 then
        return "@" .. captures[#captures].capture
    end
    return "Normal"
end

---Highlight `text` with treesitter into virt_lines chunks.
---@param text string
---@param lang string
---@return string[][][]
local function highlight(text, lang)
    local lines = vim.split(text, "\n")
    local hls = {}
    for i = 1, #lines do
        hls[i] = {}
    end

    local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
    local query = ok and vim.treesitter.query.get(lang, "highlights")
    if ok and query then
        local tree = parser:parse(true)[1]
        for id, node in query:iter_captures(tree:root(), text) do
            local name = query.captures[id]
            if not name:match("^_") and name ~= "spell" and name ~= "nospell" then
                local sr, sc, er, ec = node:range()
                for r = sr, er do
                    local line = lines[r + 1] or ""
                    local from = r == sr and sc or 0
                    local to = r == er and ec or #line
                    for c = from, to - 1 do
                        hls[r + 1][c] = "@" .. name
                    end
                end
            end
        end
    end

    local out = {}
    for i, line in ipairs(lines) do
        local chunks, start, current = {}, 0, hls[i][0]
        for c = 1, #line do
            local hl = hls[i][c]
            if hl ~= current then
                table.insert(chunks, { line:sub(start + 1, c), current or "Normal" })
                start, current = c, hl
            end
        end
        if #line > start then
            table.insert(chunks, { line:sub(start + 1), current or "Normal" })
        end
        out[i] = #chunks > 0 and chunks or { { "", "Normal" } }
    end
    return out
end

---@param q lc.ui.Question
---@param side "above"|"below"
---@return string[][][]?
local function decoy(q, side)
    if not config.user.stealth.decoy then
        return
    end
    local template = require("leetcode-ui.stealth.decoys")[q.lang]
    if not template then
        return
    end
    local key = q.lang .. ":" .. side
    if not decoy_cache[key] then
        decoy_cache[key] = highlight(template[side], ts_lang(q))
    end
    return decoy_cache[key]
end

---Last blank line before the code section's start tag, if any.
---@param q lc.ui.Question
---@param range lc.Question.Editor.Range
---@return integer? row 0-based
function Overlay.anchor_row(q, range)
    for i = range.start_i - 2, 1, -1 do
        local line = range.lines[i]
        if vim.trim(line) == "" then
            return i - 1
        end
        if not line:find("@leet", 1, true) then
            return
        end
    end
end

---@param q lc.ui.Question
function Overlay.render(q)
    local bufnr = q.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    if not q.stealth then
        return
    end

    q.stealth_names = q.stealth_names or Names.map(q.q.title_slug, Overlay.symbols(q))
    local names = q.stealth_names

    local cursor_row
    if q.winid and vim.api.nvim_win_is_valid(q.winid) and vim.api.nvim_get_current_win() == q.winid then
        cursor_row = vim.api.nvim_win_get_cursor(q.winid)[1] - 1
    end

    local range = q:editor_section_range("code")
    local lines = range.lines
    local snippet_lines = {}
    for _, l in ipairs(vim.split(q:snippet(true) or "", "\n")) do
        snippet_lines[vim.trim(l)] = true
    end
    local comment = vim.trim(utils.get_lang(q.lang).comment)

    for i, line in ipairs(lines) do
        local row = i - 1
        local in_code = range.complete and i >= range.start_i and i <= range.end_i
        local trimmed = vim.trim(line)

        -- Starter comment headers (`# Definition for singly-linked list.`)
        if in_code and trimmed ~= "" and vim.startswith(trimmed, comment) and snippet_lines[trimmed] then
            vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, { conceal_lines = "" })
        elseif row ~= cursor_row then
            for name, fake in pairs(names) do
                local init = 1
                while true do
                    local s, e = line:find("%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]", init)
                    if not s then
                        break
                    end
                    vim.api.nvim_buf_set_extmark(bufnr, NS, row, s - 1, {
                        end_col = e,
                        conceal = "",
                        virt_text = { { fake, hl_at(bufnr, row, s - 1) } },
                        virt_text_pos = "inline",
                    })
                    init = e + 1
                end
            end
        end
    end

    if range.complete then
        -- Neovim skips virtual lines on or right after concealed lines, and the
        -- start tag above the solution is concealed. Hang the decoy below the
        -- last visible line before the tag instead.
        local above = decoy(q, "above")
        local anchor = Overlay.anchor_row(q, range)
        if above and anchor then
            vim.api.nvim_buf_set_extmark(bufnr, NS, anchor, 0, { virt_lines = above })
        elseif above then
            vim.api.nvim_buf_set_extmark(bufnr, NS, range.start_i - 1, 0, {
                virt_lines = above,
                virt_lines_above = true,
            })
        end
        local below = decoy(q, "below")
        if below then
            vim.api.nvim_buf_set_extmark(bufnr, NS, range.end_i - 1, 0, { virt_lines = below })
        end
    end
end

---Compute names and highlighted decoys ahead of time, so turning stealth on is
---only extmark placement.
---@param q lc.ui.Question
function Overlay.prepare(q)
    q.stealth_names = q.stealth_names or Names.map(q.q.title_slug, Overlay.symbols(q))
    decoy(q, "above")
    decoy(q, "below")
end

---@param q lc.ui.Question
function Overlay.attach(q)
    Overlay.render(q)
    if q.stealth_attached then
        return
    end
    q.stealth_attached = true

    local timer = vim.uv.new_timer()
    local last_row
    local function schedule()
        timer:stop()
        timer:start(80, 0, vim.schedule_wrap(function()
            Overlay.render(q)
        end))
    end

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = q.bufnr,
        callback = function()
            if q.stealth then
                schedule()
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinEnter", "WinLeave" }, {
        group = group,
        buffer = q.bufnr,
        callback = function(args)
            if not q.stealth then
                return
            end
            local row = vim.api.nvim_win_get_cursor(0)[1]
            if args.event:match("^Win") or row ~= last_row then
                last_row = row
                Overlay.render(q)
            end
        end,
    })
end

---@param q lc.ui.Question
function Overlay.detach(q)
    if q.bufnr and vim.api.nvim_buf_is_valid(q.bufnr) then
        vim.api.nvim_buf_clear_namespace(q.bufnr, NS, 0, -1)
    end
end

return Overlay
