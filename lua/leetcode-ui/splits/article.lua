local wrap = require("leetcode-ui.splits.description").wrap

---Render LeetCode article markdown (editorials and community solutions) the
---way the description is drawn: padded text wrapped at the reading width,
---accent headings, and code blocks as cards with syntax highlighting.
local Render = {}

local PAD = "  "
local MAX_WIDTH = 88
local BLOCK = "leetcode_desc_block"

---Fence names LeetCode uses, as treesitter languages.
local LANG_ALIASES = {
    py = "python",
    python3 = "python",
    ["c++"] = "cpp",
    js = "javascript",
    ts = "typescript",
    golang = "go",
    rs = "rust",
    cs = "c_sharp",
    csharp = "c_sharp",
    kt = "kotlin",
    rb = "ruby",
    sh = "bash",
}

---Tags dropped from prose. Anything else in angle brackets, like
---`List<Integer>` or a key name, is text.
local HTML_TAGS = {}
for _, name in ipairs({ "a", "b", "br", "center", "code", "div", "em", "font", "i", "p", "small", "span", "strong", "sub", "sup", "u" }) do
    HTML_TAGS[name] = true
end

---@class lc.article.Output
---@field lines string[]
---@field marks { row: integer, col: integer, end_col: integer, hl: string }[]
---@field line_hls { row: integer, hl: string }[]

---Inline markdown to highlighted segments: `code`, **bold**, *italic*,
---[links](url), $math$, and HTML tags dropped.
---@param text string
---@param base? string highlight for plain text
---@return lc.desc.Seg[]
local function inline(text, base)
    local segs, plain = {}, {}
    local function flush()
        if #plain > 0 then
            table.insert(segs, { text = table.concat(plain), hl = base })
            plain = {}
        end
    end
    local function push(t, hl)
        flush()
        if t ~= "" then
            table.insert(segs, { text = t, hl = hl })
        end
    end

    local i = 1
    while i <= #text do
        local rest = text:sub(i)
        local code = rest:match("^`([^`]+)`")
        local bold = rest:match("^%*%*(.-)%*%*")
        local link_text, link_len = rest:match("^%[([^%]]-)%]%b()()")
        local math = rest:match("^%$([^%$]+)%$")
        local tag = rest:match("^<[/%a][^>]*>")
        if tag and not HTML_TAGS[(tag:match("^</?(%a+)") or ""):lower()] then
            tag = nil
        end
        local prev = i > 1 and text:sub(i - 1, i - 1) or " "
        local italic = not prev:match("[%w]") and (rest:match("^%*([^%*%s][^%*]-)%*") or rest:match("^_([^_%s][^_]-)_%f[^%w]"))
        if code then
            push(code, "leetcode_desc_code")
            i = i + #code + 2
        elseif bold and bold ~= "" then
            push(bold, "leetcode_desc_bold")
            i = i + #bold + 4
        elseif link_text then
            push(link_text, "leetcode_desc_link")
            i = i + link_len - 1
        elseif math then
            push((math:gsub("\\text{(.-)}", "%1"):gsub("\\", "")), "leetcode_desc_code")
            i = i + #math + 2
        elseif tag then
            if tag:match("^<br") then
                table.insert(plain, " ")
            end
            i = i + #tag
        elseif italic then
            push(italic, "leetcode_desc_italic")
            i = i + #italic + 2
        else
            table.insert(plain, text:sub(i, i))
            i = i + 1
        end
    end
    flush()
    return segs
end

---Treesitter language of a fence name or language slug (`py`, `python3`).
---@param name string
---@return string
local function ts_lang(name)
    name = (name or ""):lower()
    name = LANG_ALIASES[name] or name
    return vim.treesitter.language.get_lang(name) or name
end

---Keep only the reader's language where an article shows the same code in
---several languages back to back (fences separated by blank lines).
---@param md string[]
---@param lang? string
---@return string[]
local function pick_language(md, lang)
    if not lang then
        return md
    end
    local out, i = {}, 1
    while i <= #md do
        if md[i]:match("^%s*```") then
            -- Collect the run of fences.
            local blocks, j = {}, i
            while j <= #md and md[j]:match("^%s*```") do
                local fence = md[j]:match("^%s*```%s*([%w%+#_%-]*)")
                local block = { md[j] }
                j = j + 1
                while j <= #md and not md[j]:match("^%s*```") do
                    table.insert(block, md[j])
                    j = j + 1
                end
                table.insert(block, md[j])
                j = j + 1
                table.insert(blocks, { fence = fence, lines = block })
                local k = j
                while md[k] and vim.trim(md[k]) == "" do
                    k = k + 1
                end
                if not (md[k] and md[k]:match("^%s*```")) then
                    break
                end
                j = k
            end
            local mine = vim.tbl_filter(function(b)
                return ts_lang(b.fence) == lang
            end, blocks)
            for _, b in ipairs(#blocks > 1 and #mine > 0 and mine or blocks) do
                vim.list_extend(out, b.lines)
            end
            i = j
        else
            table.insert(out, md[i])
            i = i + 1
        end
    end
    return out
end

---Treesitter highlights for a code block, per line.
---@param code_lines string[]
---@param fence string
---@return table<integer, { col: integer, end_col: integer, hl: string }[]> 0-based row
local function highlight(code_lines, fence)
    local by_row = {}
    local lang = ts_lang(fence)
    local source = table.concat(code_lines, "\n")
    local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
    if not ok or not parser then
        return by_row
    end
    local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not ok_query or not query then
        return by_row
    end
    local tree = parser:parse(true)[1]
    if not tree then
        return by_row
    end
    for id, node in query:iter_captures(tree:root(), source) do
        local capture = query.captures[id]
        if capture ~= "spell" and capture ~= "nospell" and not capture:match("^_") then
            local sr, sc, er, ec = node:range()
            for row = sr, er do
                local line = code_lines[row + 1] or ""
                local from = row == sr and sc or 0
                local to = row == er and ec or #line
                if to > from then
                    by_row[row] = by_row[row] or {}
                    table.insert(by_row[row], { col = from, end_col = to, hl = "@" .. capture .. "." .. lang })
                end
            end
        end
    end
    return by_row
end

---@param md string[] markdown lines
---@param win_width integer
---@param opts? { subtitle?: string, lang?: string } a dim line under the title; the reader's language slug
---@return lc.article.Output
function Render.render(md, win_width, opts)
    opts = opts or {}
    local reader_lang = opts.lang and ts_lang(opts.lang)
    md = pick_language(md, reader_lang)
    local width = math.min(win_width, MAX_WIDTH) - #PAD
    local out = { lines = {}, marks = {}, line_hls = {} }

    local function add(text, marks, line_hl)
        table.insert(out.lines, text)
        local row = #out.lines - 1
        for _, m in ipairs(marks or {}) do
            table.insert(out.marks, { row = row, col = m.col, end_col = m.end_col, hl = m.hl })
        end
        if line_hl then
            -- Shaded blocks in articles are code: their cards span the panel
            -- instead of the reading width.
            table.insert(out.line_hls, { row = row, hl = line_hl, wide = true })
        end
    end
    local function blank()
        if #out.lines > 0 and out.lines[#out.lines] ~= "" then
            add("")
        end
    end
    local function add_wrapped(segs, first, rest, line_hl)
        for _, l in ipairs(wrap(segs, width - (line_hl and 2 or 0), first, rest)) do
            add(l.text, l.marks, line_hl)
        end
    end

    ---A code block card as wide as the panel, so code wraps only when a line
    ---would not fit. The top padding row names the language when it is not
    ---the reader's. Wrapped parts are indented under their line.
    local function code_block(fence, code_lines)
        blank()
        local inner = PAD .. "  "
        -- Card margins on both sides, and the inner gap on both sides.
        local code_width = math.max(win_width - 2 * #PAD - 2 * 2, 10)
        local label = (fence == "" or ts_lang(fence) == reader_lang) and "" or fence
        add(inner .. label, { { col = #inner, end_col = #inner + #label, hl = "leetcode_desc_dim" } }, BLOCK)
        local hls = highlight(code_lines, fence)
        for row, code in ipairs(code_lines) do
            code = code:gsub("\t", "    ")
            local marks = hls[row - 1] or {}
            local indent = #(code:match("^%s*"))
            local start = 0
            local first = true
            while first or start < #code do
                local room = first and code_width or math.max(code_width - indent - 2, 10)
                local remaining = code:sub(start + 1)
                local piece = vim.fn.strcharpart(remaining, 0, room)
                -- Break after a space in the second half when there is one,
                -- so names and operators stay whole.
                if #piece < #remaining then
                    local space = piece:match(".*() ")
                    if space and space > #piece / 2 then
                        piece = piece:sub(1, space)
                    end
                end
                local prefix = first and inner or (inner .. (" "):rep(indent + 2))
                local piece_marks = {}
                for _, m in ipairs(marks) do
                    local from = math.max(m.col, start)
                    local to = math.min(m.end_col, start + #piece)
                    if to > from then
                        table.insert(piece_marks, { col = #prefix + from - start, end_col = #prefix + to - start, hl = m.hl })
                    end
                end
                add(prefix .. piece, piece_marks, BLOCK)
                start = start + #piece
                first = false
                if #piece == 0 then
                    break
                end
            end
        end
        add(PAD, nil, BLOCK)
        add("")
    end

    local i = 1
    while i <= #md do
        local line = md[i]
        local fence = line:match("^%s*```%s*([%w%+#_%-]*)")
        local heading_marks, heading = line:match("^(#+)%s+(.*)")
        local item_indent, bullet, item = line:match("^(%s*)([%-%*%+]) (.*)")
        if not item then
            item_indent, bullet, item = line:match("^(%s*)(%d+[%.%)]) (.*)")
        end

        if fence then
            local code = {}
            i = i + 1
            while i <= #md and not md[i]:match("^%s*```") do
                table.insert(code, md[i])
                i = i + 1
            end
            code_block(fence, code)
        elseif heading then
            heading = vim.trim(heading:gsub("#+%s*$", ""))
            local level = #heading_marks
            blank()
            local hl = level == 1 and "leetcode_desc_title" or level == 2 and "leetcode_desc_example" or "leetcode_desc_heading"
            local segs = vim.tbl_map(function(seg)
                seg.hl = hl
                return seg
            end, inline(heading))
            add_wrapped(segs, PAD, PAD)
            if level == 1 and opts.subtitle then
                local text = PAD .. opts.subtitle
                add(text, { { col = #PAD, end_col = #text, hl = "leetcode_desc_dim" } })
            end
            if level <= 3 then
                add("")
            end
        elseif line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") then
            blank()
            local rule = width - #PAD
            add(PAD .. ("─"):rep(rule), { { col = #PAD, end_col = #PAD + rule * 3, hl = "leetcode_desc_rule" } })
            add("")
        elseif line:match("^%s*!%[.-%]%(.-%)%s*$") or line:match("^%s*<img") then
            local text = PAD .. "image"
            add(text, { { col = #PAD, end_col = #text, hl = "leetcode_desc_dim" } })
        elseif item then
            local depth = math.min(math.floor(#item_indent / 2), 3)
            local text = item
            while md[i + 1] and md[i + 1]:match("^%s+%S") and not md[i + 1]:match("^%s*[%-%*%+] ")
                and not md[i + 1]:match("^%s*%d+[%.%)] ") and not md[i + 1]:match("^%s*```") do
                i = i + 1
                text = text .. " " .. vim.trim(md[i])
            end
            local marker = bullet:match("%d") and bullet or "•"
            local indent = PAD .. ("  "):rep(depth)
            local lines = wrap(inline(text), width, indent .. marker .. " ", indent .. (" "):rep(vim.api.nvim_strwidth(marker) + 1))
            for n, l in ipairs(lines) do
                if n == 1 then
                    table.insert(l.marks, 1, { col = #indent, end_col = #indent + #marker, hl = "leetcode_desc_dim" })
                end
                add(l.text, l.marks)
            end
            if not (md[i + 1] and (md[i + 1]:match("^%s*[%-%*%+] ") or md[i + 1]:match("^%s*%d+[%.%)] "))) then
                add("")
            end
        elseif line:match("^%s*>") then
            local text = {}
            while md[i] and md[i]:match("^%s*>") do
                table.insert(text, (md[i]:gsub("^%s*>%s?", "")))
                i = i + 1
            end
            i = i - 1
            local bar = PAD .. "│ "
            for _, l in ipairs(wrap(inline(table.concat(text, " "), "leetcode_desc_italic"), width, bar, bar)) do
                table.insert(l.marks, 1, { col = #PAD, end_col = #bar, hl = "leetcode_desc_dim" })
                add(l.text, l.marks)
            end
            add("")
        elseif line:match("^%s*|") then
            -- Tables: one row per line, cells separated by a bar.
            while md[i] and md[i]:match("^%s*|") do
                if not md[i]:match("^%s*|[%s%-:|]+|%s*$") then
                    local cells = vim.tbl_map(vim.trim, vim.split(vim.trim(md[i]):gsub("^|", ""):gsub("|$", ""), "|", { plain = true }))
                    add_wrapped(inline(table.concat(cells, "  │  ")), PAD, PAD .. "  ")
                end
                i = i + 1
            end
            i = i - 1
            add("")
        elseif vim.trim(line) ~= "" then
            local text = { vim.trim(line) }
            while md[i + 1] and vim.trim(md[i + 1]) ~= "" and not md[i + 1]:match("^%s*[#>|]")
                and not md[i + 1]:match("^%s*```") and not md[i + 1]:match("^%s*[%-%*%+] ")
                and not md[i + 1]:match("^%s*%d+[%.%)] ") do
                i = i + 1
                table.insert(text, vim.trim(md[i]))
            end
            add_wrapped(inline(table.concat(text, " ")), PAD, PAD)
            add("")
        end
        i = i + 1
    end

    while out.lines[#out.lines] == "" do
        table.remove(out.lines)
    end
    return out
end

---Drop emoji from text such as community solution titles: they render at
---uneven widths and break the column layout.
---@param text string
---@return string
function Render.strip_emoji(text)
    local out = text:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
        local b1, b2, b3, b4 = ch:byte(1, -1)
        local cp
        if #ch == 4 then
            cp = (b1 % 8) * 262144 + (b2 % 64) * 4096 + (b3 % 64) * 64 + (b4 % 64)
        elseif #ch == 3 then
            cp = (b1 % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64)
        end
        if cp and (cp >= 0x1F000 or (cp >= 0x2600 and cp <= 0x27BF) or cp == 0xFE0F or cp == 0x200D or (cp >= 0x2B00 and cp <= 0x2BFF)) then
            return ""
        end
        return ch
    end)
    return vim.trim((out:gsub("%s%s+", " ")))
end

return Render
