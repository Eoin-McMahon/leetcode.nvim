local config = require("leetcode.config")
local log = require("leetcode.logger")

---Local debugging with nvim-dap. Runs the solution on this machine with the
---testcase pane's inputs, so it needs no Premium and no LeetCode request. The
---plugin registers its own debugpy adapter; the user's dap config is not used
---or changed.
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
---@return integer?
local function entry_line(q)
    local meta = q.q.meta_data
    local name = meta.systemdesign and "__init__" or meta.name
    local lines = vim.api.nvim_buf_get_lines(q.bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        if line:match("def%s+" .. vim.pesc(name) .. "%s*%(") then
            for j = i + 1, #lines do
                if vim.trim(lines[j]) ~= "" and not vim.trim(lines[j]):match("^#") then
                    return j
                end
            end
        end
    end
end

---@param q lc.ui.Question
---@return boolean
local function has_breakpoints(q)
    local ok, breakpoints = pcall(require, "dap.breakpoints")
    if not ok then
        return false
    end
    local by_buf = breakpoints.get(q.bufnr)
    return by_buf[q.bufnr] ~= nil and #by_buf[q.bufnr] > 0
end

local NS = vim.api.nvim_create_namespace("leetcode_debug")

---@param q lc.ui.Question
local function clear_line(q)
    if vim.api.nvim_buf_is_valid(q.bufnr) then
        vim.api.nvim_buf_clear_namespace(q.bufnr, NS, 0, -1)
    end
end

---@param q lc.ui.Question
---@param line integer
local function mark_line(q, line)
    clear_line(q)
    local d = q.debugging
    local label = d and d.case and ("%s Case %d/%d"):format(config.icons.debug_here, d.case, d.total) or nil
    pcall(vim.api.nvim_buf_set_extmark, q.bufnr, NS, line - 1, 0, {
        line_hl_group = "leetcode_debug_line",
        virt_text = label and { { "  " .. label, "leetcode_debug_label" } } or nil,
        virt_text_pos = "eol",
    })
    if q.winid and vim.api.nvim_win_is_valid(q.winid) and vim.api.nvim_win_get_buf(q.winid) == q.bufnr then
        pcall(vim.api.nvim_win_set_cursor, q.winid, { line, 0 })
    end
end

---Make the session visible in the question tab: panes out of the way, a sign
---column for breakpoints, the stopped line highlighted with the case number,
---and the winbar switched to the debug bar.
---@param dap table
---@param q lc.ui.Question
---@param total integer
local function session_ui(dap, q, total)
    local controls = require("leetcode-ui.controls")
    local restore_panes
    local restore_signcolumn

    local function finish()
        if not q.debugging then
            return
        end
        q.debugging = nil
        vim.schedule(function()
            clear_line(q)
            if restore_signcolumn and q.winid and vim.api.nvim_win_is_valid(q.winid) then
                vim.wo[q.winid].signcolumn = restore_signcolumn
            end
            if q.layout and restore_panes then
                q.layout:show(restore_panes)
            end
            controls.render(q)
        end)
    end

    dap.listeners.after.event_initialized.leetcode = function()
        q.debugging = { total = total }
        if q.layout then
            restore_panes = {}
            for name, pane in pairs(q.layout.panes) do
                if pane.visible then
                    table.insert(restore_panes, name)
                end
            end
            q.layout:hide({ "side", "console" })
        end
        if q.winid and vim.api.nvim_win_is_valid(q.winid) then
            restore_signcolumn = vim.wo[q.winid].signcolumn
            vim.wo[q.winid].signcolumn = "yes"
        end
        controls.render(q)
    end
    dap.listeners.after.event_output.leetcode = function(_, body)
        local case = body.category == "stdout" and body.output:match("^Case (%d+)")
        if case and q.debugging then
            q.debugging.case = tonumber(case)
            vim.schedule(function()
                controls.render(q)
            end)
        end
    end
    dap.listeners.after.event_stopped.leetcode = function(session)
        vim.defer_fn(function()
            local frame = session.current_frame
            if not (q.debugging and frame and frame.source and frame.source.path) then
                return
            end
            if vim.fs.normalize(frame.source.path) == vim.fs.normalize(q.file:absolute()) then
                mark_line(q, frame.line)
            end
            controls.render(q)
        end, 50)
    end
    dap.listeners.after.event_continued.leetcode = function()
        vim.schedule(function()
            clear_line(q)
        end)
    end
    dap.listeners.after.event_terminated.leetcode = finish
    dap.listeners.after.event_exited.leetcode = finish
    dap.listeners.after.disconnect.leetcode = finish
end

---The code winbar while debugging: case and step controls.
---@param q lc.ui.Question
---@return string?
function Debug.winbar(q)
    local d = q.debugging
    if not d then
        return
    end
    local controls = require("leetcode-ui.controls")
    local case = d.case and ("Case %d/%d"):format(d.case, d.total) or "starting"
    local parts = {
        ("%%#leetcode_debug_label# %s DEBUG  %s %%*"):format(config.icons.debug, case),
        controls.button("debug_continue", config.icons.debug_continue, "leetcode_ctl_run", "debug_continue"),
        controls.button("debug_over", config.icons.debug_over, "leetcode_ctl_action", "debug_over"),
        controls.button("debug_into", config.icons.debug_into, "leetcode_ctl_action", "debug_into"),
        controls.button("debug_out", config.icons.debug_out, "leetcode_ctl_action", "debug_out"),
        "%=",
        controls.button("debug", config.icons.debug_stop, "leetcode_ctl_debug", "debug"),
    }
    return table.concat(parts, " ")
end

---Step actions for keymaps and winbar clicks.
---@param action "continue"|"over"|"into"|"out"|"breakpoint"
function Debug.step(action)
    local ok, dap = pcall(require, "dap")
    if not ok then
        return log.error("Debugging needs nvim-dap (mfussenegger/nvim-dap)")
    end
    if action == "breakpoint" then
        return dap.toggle_breakpoint()
    end
    if not dap.session() then
        return log.warn("Not debugging. Start with the debug key")
    end
    ({ continue = dap.continue, over = dap.step_over, into = dap.step_into, out = dap.step_out })[action]()
end

---Start debugging, or stop the running session.
---@param q lc.ui.Question
function Debug.toggle(q)
    if q.debugging then
        local ok, dap = pcall(require, "dap")
        if ok and dap.session() then
            dap.terminate()
        end
        local ui_ok, dapui = pcall(require, "dapui")
        if ui_ok then
            pcall(dapui.close)
        end
        return
    end
    Debug.start(q)
end

---@param q lc.ui.Question
function Debug.start(q)
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
    if vim.bo[q.bufnr].modified then
        vim.api.nvim_buf_call(q.bufnr, function()
            vim.cmd("silent write")
        end)
    end

    local spec = vim.fn.tempname() .. ".json"
    local all_cases = cases(q)
    vim.fn.writefile({
        vim.json.encode({
            solution = q.file:absolute(),
            meta = q.q.meta_data,
            cases = all_cases,
        }),
    }, spec)

    if not has_breakpoints(q) then
        local line = entry_line(q)
        if line then
            require("dap.breakpoints").set({}, q.bufnr, line)
            log.info(("No breakpoints set, stopping at line %d"):format(line))
        end
    end

    dap.adapters[ADAPTER] = {
        type = "executable",
        command = python,
        args = { "-m", "debugpy.adapter" },
    }
    session_ui(dap, q, #all_cases)

    dap.run({
        type = ADAPTER,
        request = "launch",
        name = "LeetCode: " .. q.q.title,
        program = harness,
        args = { spec },
        console = "internalConsole",
        justMyCode = true,
        cwd = vim.fs.dirname(q.file:absolute()),
        pythonPath = python,
    })
end

return Debug
