---Render a run or submit response in the same style as the description:
---a coloured verdict header, case chips, and labelled shaded blocks.
local Render = {}

local PAD = "  "

---@param v any
local function present(v)
    return v ~= nil and v ~= vim.NIL and v ~= ""
end

---@param text string
---@param width integer
---@return string[]
local function hard_wrap(text, width)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line == "" then
            table.insert(out, "")
        end
        while #line > 0 do
            table.insert(out, line:sub(1, width))
            line = line:sub(width + 1)
        end
    end
    while #out > 1 and out[#out] == "" do
        table.remove(out)
    end
    return out
end

---@param item table interpreter response
---@param testcases string[][] inputs per case, from the testcase snapshot
---@param params { name: string }[]
---@param case_idx integer selected case
---@param width integer window width
---@return lc.desc.Output, integer case_count
function Render.render(item, testcases, params, case_idx, width)
    local out = { lines = {}, marks = {}, line_hls = {}, links = {} }
    local inner = math.max(width - #PAD - 4, 20)

    local function add(text, marks, line_hl)
        table.insert(out.lines, text)
        local row = #out.lines - 1
        for _, m in ipairs(marks or {}) do
            table.insert(out.marks, { row = row, col = m.col, end_col = m.end_col, hl = m.hl })
        end
        if line_hl then
            table.insert(out.line_hls, { row = row, hl = line_hl })
        end
    end
    local function label(text)
        local line = PAD .. text
        add(line, { { col = #PAD, end_col = #line, hl = "leetcode_desc_dim" } })
    end
    local function heading(text)
        add("")
        local line = PAD .. text
        add(line, { { col = #PAD, end_col = #line, hl = "leetcode_desc_heading" } })
    end
    ---A shaded block with a padding row above and below, so it reads as one
    ---solid box.
    local function block(text, hl)
        hl = hl or "leetcode_desc_block"
        add(PAD, nil, hl)
        for _, l in ipairs(hard_wrap(text, inner)) do
            add(PAD .. "  " .. l, nil, hl)
        end
        add(PAD, nil, hl)
    end
    local function inputs(values)
        for i, value in ipairs(values or {}) do
            local name = params[i] and params[i].name
            if name then
                label(name .. " =")
            end
            block(value)
        end
    end

    local ok = item._ and item._.success
    local title = vim.trim(item.status_msg or "")
    add("")
    local header = PAD .. title
    add(header, { { col = #PAD, end_col = #header, hl = ok and "leetcode_result_ok" or "leetcode_result_err" } })

    local stats = {}
    if present(item.status_runtime) or present(item.display_runtime) then
        local runtime = present(item.display_runtime) and (item.display_runtime .. " ms") or item.status_runtime
        local text = "Runtime " .. runtime
        if present(item.runtime_percentile) then
            text = text .. (" · beats %.1f%%"):format(item.runtime_percentile)
        end
        table.insert(stats, text)
    end
    if item._ and item._.submission and present(item.status_memory) then
        local text = "Memory " .. item.status_memory
        if present(item.memory_percentile) then
            text = text .. (" · beats %.1f%%"):format(item.memory_percentile)
        end
        table.insert(stats, text)
    end
    if item._ and item._.submission and present(item.total_testcases) and present(item.total_correct) then
        table.insert(stats, ("%d / %d cases passed"):format(item.total_correct, item.total_testcases))
    end
    if #stats > 0 then
        label(table.concat(stats, "   "))
    end

    local code = item.status_code
    local case_count = 0

    if code == 15 or code == 20 then
        local err = code == 20 and item.full_compile_error or item.full_runtime_error
        heading(code == 20 and "Compile error" or "Error")
        block(present(err) and err or (item.runtime_error or item.compile_error or ""), "leetcode_block_err")
        if present(item.last_testcase) then
            heading("Last executed input")
            inputs(vim.split(item.last_testcase, "\n"))
        end
    elseif code == 10 and not (item._ and item._.submission) then
        case_count = present(item.total_testcases) and item.total_testcases or 0
        case_idx = math.min(math.max(case_idx, 1), math.max(case_count, 1))

        add("")
        local chips, marks = PAD, {}
        for i = 1, case_count do
            local passed = (item.compare_result or ""):sub(i, i) == "1"
            local dot = "●"
            if #chips > #PAD then
                chips = chips .. "  "
            end
            table.insert(marks, { col = #chips, end_col = #chips + #dot, hl = passed and "leetcode_ok" or "leetcode_error" })
            local chip = (" %s Case %d "):format(dot, i)
            local start = #chips
            chips = chips .. chip
            if i == case_idx then
                table.insert(marks, { col = start, end_col = #chips, hl = "leetcode_chip_active" })
            end
        end
        add(chips, marks)

        local i = case_idx
        local passed = (item.compare_result or ""):sub(i, i) == "1"
        heading("Input")
        inputs(testcases[i])
        heading("Output")
        block(tostring((item.code_answer or {})[i] or ""), passed and nil or "leetcode_block_err")
        heading("Expected")
        block(tostring((item.expected_code_answer or {})[i] or ""), passed and nil or "leetcode_block_ok")
        local stdout = (item.std_output_list or {})[i]
        if present(stdout) then
            heading("Stdout")
            block(stdout)
        end
    elseif code == 10 then
        add("")
        label("All test cases passed.")
    else
        if present(item.last_testcase) then
            heading("Last executed input")
            inputs(vim.split(item.last_testcase, "\n"))
        end
        if present(item.code_output) then
            heading("Output")
            block(type(item.code_output) == "table" and table.concat(item.code_output, "\n") or item.code_output, "leetcode_block_err")
        end
        if present(item.expected_output) then
            heading("Expected")
            block(item.expected_output, "leetcode_block_ok")
        end
        if present(item.std_output) then
            heading("Stdout")
            block(item.std_output)
        end
    end

    return out, case_count
end

return Render
