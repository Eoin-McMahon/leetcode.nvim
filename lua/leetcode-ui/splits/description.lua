local config = require("leetcode.config")

---Render a question's HTML description as plain, website-style text: a bold
---title, a row of pills, plain body text with only code and headings styled,
---examples in shaded blocks, images as openable links.
local Render = {}

local MAX_WIDTH = 88
local PAD = "  "

local ENTITIES = {
    nbsp = " ",
    lt = "<",
    gt = ">",
    amp = "&",
    quot = '"',
    apos = "'",
    ["#39"] = "'",
}

---@param s string
local function decode(s)
    return (
        s:gsub("&(#?%w+);", function(name)
            if ENTITIES[name] then
                return ENTITIES[name]
            end
            local num = name:match("^#(%d+)$")
            if num then
                return vim.fn.nr2char(tonumber(num))
            end
            local hex = name:match("^#x(%x+)$")
            if hex then
                return vim.fn.nr2char(tonumber(hex, 16))
            end
        end)
    )
end

---@class lc.desc.Seg
---@field text string
---@field hl? string

---@class lc.desc.Block
---@field kind "para"|"pre"|"li"|"img"|"heading"
---@field segs lc.desc.Seg[]
---@field shaded? boolean
---@field bullet? string
---@field depth? integer
---@field url? string

---@param html string
---@return lc.desc.Block[]
function Render.parse(html)
    local blocks = {}
    local cur
    local styles = {}
    local in_pre = false
    local lists = {}
    local divs = {}

    local function shaded()
        for _, d in ipairs(divs) do
            if d then
                return true
            end
        end
        return false
    end

    local function current_hl()
        local hl
        for _, s in ipairs(styles) do
            if s == "code" then
                hl = "leetcode_desc_code"
            elseif (s == "strong" or s == "example") and hl ~= "leetcode_desc_code" then
                hl = "leetcode_desc_bold"
            elseif s == "em" and not hl then
                hl = "leetcode_desc_italic"
            elseif s == "a" then
                hl = "leetcode_desc_link"
            end
        end
        return hl
    end

    local function flush()
        if cur then
            local text = table.concat(vim.tbl_map(function(s)
                return s.text
            end, cur.segs))
            if vim.trim(text) ~= "" or cur.kind == "img" then
                table.insert(blocks, cur)
            end
        end
        cur = nil
    end

    local function ensure()
        if not cur then
            cur = { kind = "para", segs = {}, shaded = shaded() }
        end
    end

    local function append(text, hl)
        ensure()
        table.insert(cur.segs, { text = text, hl = hl or current_hl() })
    end

    local pos = 1
    while pos <= #html do
        local s, e, closing, name, attrs = html:find("<(/?)([%w]+)([^>]*)>", pos)
        local text = html:sub(pos, (s or #html + 1) - 1)
        if text ~= "" then
            text = decode(text)
            if in_pre then
                append(text)
            else
                text = text:gsub("%s+", " ")
                if not (text == " " and not cur) then
                    append(text)
                end
            end
        end
        if not s then
            break
        end
        pos = e + 1
        name = name:lower()
        local open = closing == ""

        if name == "p" then
            flush()
        elseif name == "div" then
            flush()
            if open then
                table.insert(divs, attrs:find("example%-block") ~= nil)
            else
                table.remove(divs)
            end
        elseif name == "pre" then
            flush()
            in_pre = open
            if open then
                cur = { kind = "pre", segs = {}, shaded = true }
            end
        elseif name == "ul" or name == "ol" then
            flush()
            if open then
                table.insert(lists, { ordered = name == "ol", n = 0 })
            else
                table.remove(lists)
            end
        elseif name == "li" then
            flush()
            if open then
                local list = lists[#lists] or { ordered = false, n = 0 }
                list.n = list.n + 1
                cur = {
                    kind = "li",
                    segs = {},
                    bullet = list.ordered and (list.n .. ".") or "•",
                    depth = math.max(#lists, 1),
                    shaded = shaded(),
                }
            end
        elseif name == "br" then
            append("\n")
        elseif name == "img" then
            flush()
            table.insert(blocks, { kind = "img", segs = {}, url = attrs:match('src="([^"]+)"') })
        elseif name == "sup" or name == "sub" then
            if open then
                append(name == "sup" and "^" or "_")
            end
        elseif name == "strong" or name == "b" or name == "em" or name == "i" or name == "code" or name == "a" then
            local style = (name == "b" and "strong") or (name == "i" and "em") or name
            if style == "strong" and attrs:find('class="example"') then
                style = "example"
            end
            if open then
                table.insert(styles, style)
            else
                for i = #styles, 1, -1 do
                    if styles[i] == style or (style == "strong" and styles[i] == "example") then
                        table.remove(styles, i)
                        break
                    end
                end
            end
        end
    end
    flush()

    -- Example labels get their own colours.
    local LABEL_HL = {
        input = "leetcode_desc_input",
        output = "leetcode_desc_output",
        explanation = "leetcode_desc_explain",
    }
    for _, b in ipairs(blocks) do
        for _, seg in ipairs(b.segs) do
            local name = seg.hl == "leetcode_desc_bold" and vim.trim(seg.text):lower():match("^(%a+):?$")
            if name and LABEL_HL[name] then
                seg.hl = LABEL_HL[name]
            end
        end
    end

    -- "Example 1:", "Constraints:", "Follow-up:" paragraphs become headings.
    for _, b in ipairs(blocks) do
        if b.kind == "para" and #b.segs > 0 then
            local text = vim.trim(table.concat(vim.tbl_map(function(s)
                return s.text
            end, b.segs)))
            local all_bold = vim.iter(b.segs):all(function(seg)
                return seg.hl == "leetcode_desc_bold" or vim.trim(seg.text) == ""
            end)
            if all_bold and text:match(":$") then
                b.kind = "heading"
                b.segs = { { text = text:gsub(":$", ""), hl = "leetcode_desc_heading" } }
            end
        end
    end

    -- Some problems write examples as plain paragraphs after "Example N"
    -- instead of a <pre> or example block: shade those too.
    local in_example = false
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            in_example = (b.segs[1].text or ""):match("^Example") ~= nil
        elseif in_example and (b.kind == "para" or b.kind == "li") then
            b.shaded = true
        elseif b.kind == "pre" then
            in_example = false
        end
    end

    return blocks
end

---Greedy word wrap that keeps per-segment highlights.
---@param segs lc.desc.Seg[]
---@param width integer
---@param first string prefix of the first line
---@param rest string prefix of continuation lines
---@return { text: string, marks: { col: integer, end_col: integer, hl: string }[] }[]
local function wrap(segs, width, first, rest)
    local words = {}
    for _, seg in ipairs(segs) do
        -- A segment that starts with a space ends the previous word.
        if seg.text:match("^%s") and #words > 0 and not words[#words].text:match("%s$") then
            words[#words].text = words[#words].text .. " "
        end
        for piece in seg.text:gmatch("%S+%s*") do
            table.insert(words, { text = piece, hl = seg.hl, seg = seg })
        end
    end

    local lines = {}
    local line = { text = first, marks = {} }
    local used = vim.api.nvim_strwidth(first)
    local prefix_width = vim.api.nvim_strwidth(rest)
    for _, w in ipairs(words) do
        local word = w.text
        local ww = vim.api.nvim_strwidth(vim.trim(word))
        if used + ww > width and used > prefix_width then
            line.text = line.text:gsub("%s+$", "")
            table.insert(lines, line)
            line = { text = rest, marks = {} }
            used = prefix_width
        end
        local col = #line.text
        line.text = line.text .. word
        used = used + vim.api.nvim_strwidth(word)
        if w.hl then
            -- Words of one segment on one line share a mark, so a code span
            -- like `get(int key)` is shaded as one piece, spaces included.
            local last = line.marks[#line.marks]
            if last and last.seg == w.seg then
                last.end_col = col + #vim.trim(word)
            else
                table.insert(line.marks, { col = col, end_col = col + #vim.trim(word), hl = w.hl, seg = w.seg })
            end
        end
    end
    line.text = line.text:gsub("%s+$", "")
    table.insert(lines, line)
    return lines
end

---Language-neutral highlighting for example values and explanations:
---numbers, strings, literals and line comments.
---@param text string
---@param from integer byte column to start at
---@return { col: integer, end_col: integer, hl: string }[]
local function code_marks(text, from)
    local marks = {}
    local comment = text:find("//", from + 1, true) or text:find("%s#%s", from + 1)
    local limit = comment and comment - 1 or #text
    local function scan(pattern, hl)
        local init = from + 1
        while true do
            local s, e = text:find(pattern, init)
            if not s or s > limit then
                break
            end
            table.insert(marks, { col = s - 1, end_col = e, hl = hl })
            init = e + 1
        end
    end
    scan('"[^"]*"', "@string")
    scan("%f[%w%-]%-?%d+%.?%d*%f[^%w%.]", "@number")
    scan("%f[%w]true%f[^%w]", "@boolean")
    scan("%f[%w]false%f[^%w]", "@boolean")
    scan("%f[%w]null%f[^%w]", "@constant.builtin")
    if comment then
        table.insert(marks, { col = comment - 1, end_col = #text, hl = "@comment" })
    end
    return marks
end

---Lines of a list item. An item that opens with a code span, like
---`get(int key) Return the value...`, and does not fit on one line puts the
---code on its own line with the explanation under it.
---@param segs lc.desc.Seg[]
---@param width integer
---@param first string
---@param cont string
local function li_lines(segs, width, first, cont)
    local lead, rest = {}, {}
    for _, seg in ipairs(segs) do
        if #rest == 0 and (seg.hl == "leetcode_desc_code" or vim.trim(seg.text) == "") then
            table.insert(lead, seg)
        else
            table.insert(rest, seg)
        end
    end
    local has_code = vim.iter(lead):any(function(seg)
        return seg.hl == "leetcode_desc_code"
    end)
    local all = wrap(segs, width, first, cont)
    if not has_code or #rest == 0 or #all == 1 then
        return all
    end
    rest[1] = { text = (rest[1].text:gsub("^%s+", "")), hl = rest[1].hl }
    if rest[1].text == "" then
        table.remove(rest, 1)
    end
    local lines = wrap(lead, width, first, cont)
    vim.list_extend(lines, wrap(rest, width, cont, cont))
    return lines
end

local LABEL_HLS = {
    leetcode_desc_input = true,
    leetcode_desc_output = true,
    leetcode_desc_explain = true,
}

---Lines of an example part. A label ("Input:") gets its own line and the
---value goes under it, so wrapped values line up with the rest.
---@param segs lc.desc.Seg[]
---@param width integer
---@param inner string indent of the block's text
local function block_lines(segs, width, inner)
    local first = segs[1]
    if not (first and LABEL_HLS[first.hl]) then
        return wrap(segs, width, inner, inner .. "  ")
    end
    local label = vim.trim(first.text):gsub(":$", "")
    local lines = { { text = inner .. label, marks = { { col = #inner, end_col = #inner + #label, hl = first.hl } } } }
    local rest = vim.list_slice(segs, 2)
    while rest[1] and vim.trim(rest[1].text) == "" do
        table.remove(rest, 1)
    end
    if rest[1] then
        rest[1] = { text = (rest[1].text:gsub("^%s+", "")), hl = rest[1].hl }
        vim.list_extend(lines, wrap(rest, width, inner, inner .. "  "))
    end
    return lines
end

---@param n number
local function short(n)
    n = tonumber(n) or 0
    if n >= 1e6 then
        return ("%.1fM"):format(n / 1e6)
    elseif n >= 1e3 then
        return ("%.1fk"):format(n / 1e3)
    end
    return tostring(n)
end

---@class lc.desc.Output
---@field lines string[]
---@field marks { row: integer, col: integer, end_col: integer, hl: string }[]
---@field line_hls { row: integer, hl: string }[]
---@field links table<integer, string> 1-based row to URL

---@param q lc.ui.Question
---@param win_width integer
---@return lc.desc.Output
function Render.render(q, win_width)
    local width = math.min(win_width, MAX_WIDTH) - #PAD
    local out = { lines = {}, marks = {}, line_hls = {}, links = {} }

    local function add(text, marks, line_hl)
        table.insert(out.lines, text)
        local row = #out.lines - 1
        -- Inside example blocks, code highlighting goes under the label colours.
        if line_hl == "leetcode_desc_block" then
            local from = 0
            for _, m in ipairs(marks or {}) do
                if LABEL_HLS[m.hl] or m.hl == "leetcode_desc_example" then
                    from = math.max(from, m.end_col)
                end
            end
            for _, m in ipairs(code_marks(text, from)) do
                table.insert(out.marks, { row = row, col = m.col, end_col = m.end_col, hl = m.hl })
            end
        end
        for _, m in ipairs(marks or {}) do
            table.insert(out.marks, { row = row, col = m.col, end_col = m.end_col, hl = m.hl })
        end
        if line_hl then
            table.insert(out.line_hls, { row = row, hl = line_hl })
        end
    end
    local function blank()
        if out.lines[#out.lines] ~= "" then
            add("")
        end
    end
    local function in_block()
        local last = out.line_hls[#out.line_hls]
        return last ~= nil and last.row == #out.lines - 1
    end
    -- Shaded blocks get a padding row above and below, then a blank line.
    local function open_block()
        if not in_block() then
            add(PAD, nil, "leetcode_desc_block")
        end
    end
    local function close_block()
        if in_block() then
            add(PAD, nil, "leetcode_desc_block")
            add("")
        end
    end

    local data = q.q
    add("")
    local title = ("%s%s. %s"):format(PAD, data.frontend_id, data.title)
    add(title, { { col = #PAD, end_col = #title, hl = "leetcode_desc_title" } })
    add("")

    local pills, marks = PAD, {}
    local function pill(text, hl)
        if #pills > #PAD then
            if vim.api.nvim_strwidth(pills .. "  " .. text) > width + #PAD then
                add(pills, marks)
                pills, marks = PAD, {}
            else
                pills = pills .. "  "
            end
        end
        table.insert(marks, { col = #pills, end_col = #pills + #text, hl = hl })
        pills = pills .. text
    end
    pill(" " .. data.difficulty .. " ", "leetcode_pill_" .. data.difficulty:lower())
    if q.cache.status == "ac" then
        pill(config.icons.status.ac .. " Solved", "leetcode_ok")
    end
    if type(data.stats) == "table" and data.stats.acRate then
        pill(data.stats.acRate .. " accepted", "leetcode_pill")
    end
    pill(short(data.likes) .. " likes", "leetcode_pill")
    if type(data.hints) == "table" and #data.hints > 0 then
        pill(("%d hint%s"):format(#data.hints, #data.hints == 1 and "" or "s"), "leetcode_pill")
    end
    add(pills, marks)
    add("")
    add(PAD .. ("─"):rep(width), { { col = #PAD, end_col = #PAD + width * 3, hl = "leetcode_desc_rule" } })
    add("")

    local prev, prev_li_lines = nil, 0
    -- Set while an example's title opened its shaded block, so the example
    -- body continues that block instead of starting a new one.
    local example_open = false
    local blocks = Render.parse(data.content or "")
    for bi, b in ipairs(blocks) do
        if not b.shaded and b.kind ~= "pre" and not (example_open and b.kind == "img") then
            close_block()
        end
        if prev and prev.kind == "li" and b.kind ~= "li" and not b.shaded then
            blank()
        end
        -- The block an example title introduces, past any images.
        local next_block
        for j = bi + 1, #blocks do
            if blocks[j].kind ~= "img" then
                next_block = blocks[j]
                break
            end
        end
        if b.kind == "heading" and b.segs[1].text:match("^Example") and next_block and (next_block.kind == "pre" or next_block.shaded) then
            -- The example's title is the first row of its shaded block.
            blank()
            open_block()
            local text = PAD .. "  " .. b.segs[1].text
            add(text, { { col = #PAD + 2, end_col = #text, hl = "leetcode_desc_example" } }, "leetcode_desc_block")
            add(PAD, nil, "leetcode_desc_block")
            example_open = true
        elseif b.kind == "heading" then
            blank()
            local text = PAD .. b.segs[1].text
            add(text, { { col = #PAD, end_col = #text, hl = "leetcode_desc_heading" } })
        elseif b.kind == "img" then
            -- Inside an example, the image line is part of its block.
            local inner = PAD .. (example_open and "  " or "")
            local text = ("%s%s image  (gx to open)"):format(inner, config.icons.image)
            add(text, { { col = #inner, end_col = #text, hl = "leetcode_desc_dim" } }, example_open and "leetcode_desc_block" or nil)
            out.links[#out.lines] = b.url
            if example_open then
                add(PAD, nil, "leetcode_desc_block")
            end
        elseif b.kind == "pre" then
            -- Rebuild per line so bold labels ("Input:") keep their style.
            local seg_lines, current = {}, {}
            for _, seg in ipairs(b.segs) do
                local parts = vim.split(seg.text, "\n", { plain = true })
                for i, part in ipairs(parts) do
                    if i > 1 then
                        table.insert(seg_lines, current)
                        current = {}
                    end
                    if part ~= "" then
                        table.insert(current, { text = part, hl = seg.hl })
                    end
                end
            end
            table.insert(seg_lines, current)
            while #seg_lines > 0 and #seg_lines[1] == 0 do
                table.remove(seg_lines, 1)
            end
            while #seg_lines > 0 and #seg_lines[#seg_lines] == 0 do
                table.remove(seg_lines)
            end
            if not example_open then
                close_block()
                open_block()
            end
            example_open = false
            for n, segs in ipairs(seg_lines) do
                -- A blank shaded row before each label after the first, so
                -- Input, Output and Explanation read as separate parts.
                local first = segs[1]
                local prev_blank = vim.trim(out.lines[#out.lines] or "") == ""
                if n > 1 and not prev_blank and first and LABEL_HLS[first.hl] then
                    add(PAD, nil, "leetcode_desc_block")
                end
                for _, l in ipairs(block_lines(segs, width - 2, PAD .. "  ")) do
                    add(l.text, l.marks, "leetcode_desc_block")
                end
            end
            close_block()
        elseif b.kind == "li" then
            -- Inside a shaded block, items start at the block's text margin.
            local indent = PAD .. (b.shaded and "  " or "") .. ("  "):rep((b.depth or 1) - 1)
            local first = indent .. b.bullet .. " "
            local cont = indent .. (" "):rep(vim.api.nvim_strwidth(b.bullet) + 1)
            if b.shaded then
                open_block()
                example_open = false
            end
            local lines = li_lines(b.segs, width - (b.shaded and 2 or 0), first, cont)
            -- Items that wrap get a blank line between them.
            if not b.shaded and prev and prev.kind == "li" and (#lines > 1 or prev_li_lines > 1) then
                add("")
            end
            prev_li_lines = #lines
            for i, l in ipairs(lines) do
                if i == 1 then
                    table.insert(l.marks, 1, { col = #indent, end_col = #indent + #b.bullet, hl = "leetcode_desc_dim" })
                end
                add(l.text, l.marks, b.shaded and "leetcode_desc_block" or nil)
            end
        else
            local inner = PAD .. (b.shaded and "  " or "")
            local lines = b.shaded and block_lines(b.segs, width - 2, inner) or wrap(b.segs, width, inner, inner)
            if b.shaded then
                example_open = false
                local first = b.segs[1]
                local labelled = first and LABEL_HLS[first.hl]
                if labelled and in_block() and vim.trim(out.lines[#out.lines]) ~= "" then
                    add(PAD, nil, "leetcode_desc_block")
                end
                open_block()
            end
            for _, l in ipairs(lines) do
                add(l.text, l.marks, b.shaded and "leetcode_desc_block" or nil)
            end
            if not b.shaded then
                add("")
            end
        end
        prev = b
    end

    close_block()

    -- Footer, replacing the old info popup: topics, then similar problems.
    out.problems = {}
    local topics = vim.tbl_map(function(tag)
        return tag.name
    end, type(data.topic_tags) == "table" and data.topic_tags or {})
    if #topics > 0 then
        blank()
        add(PAD .. "Topics", { { col = #PAD, end_col = #PAD + 6, hl = "leetcode_desc_heading" } })
        local line, marks = PAD, {}
        for _, name in ipairs(topics) do
            local pill = " " .. name .. " "
            if vim.api.nvim_strwidth(line .. pill) > width + #PAD then
                add(line, marks)
                line, marks = PAD, {}
            end
            table.insert(marks, { col = #line, end_col = #line + #pill, hl = "leetcode_chip_active" })
            line = line .. pill .. " "
        end
        add(line, marks)
    end
    local similar = type(data.similar) == "table" and data.similar or {}
    if #similar > 0 then
        blank()
        add(PAD .. "Similar problems", { { col = #PAD, end_col = #PAD + 16, hl = "leetcode_desc_heading" } })
        local problemlist = require("leetcode.cache.problemlist")
        for _, s in ipairs(vim.list_slice(similar, 1, 10)) do
            local ok, problem = pcall(problemlist.get_by_title_slug, s.title_slug)
            local id = ok and type(problem) == "table" and problem.frontend_id or nil
            local line = ("%s● %s%s"):format(PAD, id and (id .. ". ") or "", s.title)
            add(line, { { col = #PAD, end_col = #PAD + #"●", hl = "leetcode_" .. (s.difficulty or "easy"):lower() } })
            out.problems[#out.lines] = s.title_slug
        end
    end

    while out.lines[#out.lines] == "" do
        table.remove(out.lines)
    end
    return out
end

return Render
