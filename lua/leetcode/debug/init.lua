local config = require("leetcode.config")
local log = require("leetcode.logger")

---Hand a question over to nvim-dap. The code is copied to a debug file in its
---own tab and run locally on the testcase pane's inputs, so it needs no Premium
---and sends nothing to LeetCode. From then on nvim-dap and dap-ui own the keys,
---signs and UI; when the session ends the tab closes and the question tab is
---back. The plugin registers its own debugpy adapter and leaves the user's dap
---config alone.
local Debug = {}

local ADAPTER = "leetcode_python"
local SUPPORTED = { python3 = true, python = true }

---@return string?
local function harness_path()
    local file = debug.getinfo(1, "S").source:sub(2)
    local path = vim.fs.joinpath(vim.fs.dirname(file), "harness.py")
    return vim.uv.fs_stat(path) and path or nil
end

---A Python that can import debugpy: `debugger.python`, then Mason's debugpy, then
---`python3` on PATH.
---@return string?
local found_python

local function debugpy_python()
    if found_python then
        return found_python
    end
    local candidates = vim.tbl_filter(function(python)
        return python ~= nil and python ~= ""
    end, {
        config.user.debugger.python or "",
        vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python",
        vim.fn.exepath("python3"),
    })
    for _, python in ipairs(candidates) do
        if vim.fn.executable(python) == 1 then
            vim.fn.system({ python, "-c", "import debugpy" })
            if vim.v.shell_error == 0 then
                found_python = python
                return python
            end
        end
    end
end

---Report everything missing at once, so one install round fixes it.
---@return table? dap, table? dapui, string? python
local function dependencies()
    local missing = {}
    local ok_dap, dap = pcall(require, "dap")
    if not ok_dap then
        table.insert(missing, "nvim-dap (mfussenegger/nvim-dap)")
    end
    local ok_ui, dapui = pcall(require, "dapui")
    if not ok_ui then
        table.insert(missing, "nvim-dap-ui (rcarriga/nvim-dap-ui)")
    end
    local python = debugpy_python()
    if not python then
        table.insert(missing, "debugpy (`:MasonInstall debugpy` or `pip install debugpy`)")
    end

    if #missing > 0 then
        log.error("Debugging needs:\n- " .. table.concat(missing, "\n- "))
        return
    end
    return dap, dapui, python
end

---Cases from the testcase pane: blank-line separated groups of input lines.
---@param q lc.ui.Question
---@return string[][]
local function cases(q)
    local groups, current = {}, {}
    for line in (q.console.testcase:content() .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            table.insert(current, line)
        end
    end
    local meta = q.q.meta_data
    local per_case = meta.systemdesign and 2 or #(meta.params or {})
    per_case = math.max(per_case, 1)
    for i = 1, #current, per_case do
        table.insert(groups, vim.list_slice(current, i, i + per_case - 1))
    end
    return groups
end

---Line of the solution method's first statement, for a default breakpoint.
---@param q lc.ui.Question
---@param bufnr integer
---@return integer?
local function entry_line(q, bufnr)
    local meta = q.q.meta_data
    local name = meta.systemdesign and "__init__" or meta.name
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        if line:match("def%s+" .. vim.pesc(name) .. "%s*%(") then
            for j = i + 1, #lines do
                local text = vim.trim(lines[j])
                if text ~= "" and not text:match("^#") then
                    return j
                end
            end
        end
    end
end

---@param bufnr integer
---@return boolean
local function has_breakpoints(bufnr)
    local by_buf = require("dap.breakpoints").get(bufnr)
    return by_buf[bufnr] ~= nil and #by_buf[bufnr] > 0
end

---Write the question's current code (saved or not) to a debug-only file.
---@param q lc.ui.Question
---@return string
local function debug_copy(q)
    local dir = vim.fn.stdpath("cache") .. "/leetcode/debug"
    vim.fn.mkdir(dir, "p")
    local path = ("%s/%s_%s.py"):format(dir, q.q.frontend_id, q.q.title_slug:gsub("-", "_"))
    vim.fn.writefile(vim.api.nvim_buf_get_lines(q.bufnr, 0, -1, false), path)
    return path
end

---@param q lc.ui.Question
local function back_to_question(q)
    local d = q.debug_session
    q.debug_session = nil
    if not d then
        return
    end
    vim.schedule(function()
        if d.tab and vim.api.nvim_tabpage_is_valid(d.tab) and #vim.api.nvim_list_tabpages() > 1 then
            pcall(vim.cmd.tabclose, vim.api.nvim_tabpage_get_number(d.tab))
        end
        -- Deleting the buffer clears its breakpoints, which nvim-dap sends to the
        -- adapter. Wait until the session is fully gone so nothing is sent to a
        -- dead adapter.
        local function wipe(tries)
            local ok, dap = pcall(require, "dap")
            if ok and dap.session() and tries > 0 then
                return vim.defer_fn(function()
                    wipe(tries - 1)
                end, 200)
            end
            if d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) then
                pcall(vim.api.nvim_buf_delete, d.bufnr, { force = true })
            end
        end
        vim.defer_fn(function()
            wipe(10)
        end, 200)
        if q.winid and vim.api.nvim_win_is_valid(q.winid) then
            vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(q.winid))
            vim.api.nvim_set_current_win(q.winid)
        end
    end)
end

---Open the question in the debugger, or stop the session if one is running.
---@param q lc.ui.Question
function Debug.toggle(q)
    if q.debug_session then
        local ok, dap = pcall(require, "dap")
        if ok and dap.session() then
            dap.terminate()
        end
        return back_to_question(q)
    end
    Debug.start(q)
end

---@param q lc.ui.Question
---@param only_cases? string[][] debug these cases instead of the test panel's
function Debug.start(q, only_cases)
    if not SUPPORTED[q.lang] then
        return log.error(("Local debugging supports Python for now, not %s"):format(q.lang))
    end
    local dap, _, python = dependencies()
    if not dap then
        return
    end
    local harness = harness_path()
    if not harness then
        return log.error("Debug harness missing from the plugin install")
    end

    local file = debug_copy(q)
    local spec = vim.fn.tempname() .. ".json"
    vim.fn.writefile({ vim.json.encode({ solution = file, meta = q.q.meta_data, cases = only_cases or cases(q) }) }, spec)

    vim.cmd("tabnew " .. vim.fn.fnameescape(file))
    local d = { tab = vim.api.nvim_get_current_tabpage(), bufnr = vim.api.nvim_get_current_buf() }
    q.debug_session = d

    if not has_breakpoints(d.bufnr) then
        local line = entry_line(q, d.bufnr)
        if line then
            require("dap.breakpoints").set({}, d.bufnr, line)
            pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
        end
    end

    -- Closing the debug tab ends the session; the session ending closes the tab.
    vim.api.nvim_create_autocmd("BufWinLeave", {
        buffer = d.bufnr,
        once = true,
        callback = function()
            if q.debug_session == d and dap.session() then
                dap.terminate()
            end
        end,
    })
    local function done()
        if q.debug_session == d then
            back_to_question(q)
        end
    end
    dap.listeners.after.event_terminated.leetcode = done
    dap.listeners.after.event_exited.leetcode = done
    dap.listeners.after.disconnect.leetcode = done

    dap.adapters[ADAPTER] = {
        type = "executable",
        command = python,
        args = { "-m", "debugpy.adapter" },
    }
    dap.run({
        type = ADAPTER,
        request = "launch",
        name = "LeetCode: " .. q.q.title,
        program = harness,
        args = { spec },
        console = "internalConsole",
        justMyCode = true,
        cwd = vim.fs.dirname(file),
        pythonPath = python,
    })
end

return Debug
