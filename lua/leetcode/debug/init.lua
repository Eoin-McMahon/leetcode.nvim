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

---A Python that can import debugpy: `debug.python`, then Mason's debugpy, then
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
        config.user.debug.python or "",
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

---Hide the LeetCode panes while dap-ui owns the screen and bring them back
---after.
---@param dap table
---@param q lc.ui.Question
local function manage_panes(dap, q)
    if not q.layout then
        return
    end
    local restore
    dap.listeners.after.event_initialized.leetcode = function()
        restore = {}
        for name, pane in pairs(q.layout.panes) do
            restore[name] = pane.visible
        end
        q.layout:hide({ "side", "console" })
    end
    local function done()
        if not restore then
            return
        end
        local show = {}
        for name, visible in pairs(restore) do
            if visible then
                table.insert(show, name)
            end
        end
        restore = nil
        vim.schedule(function()
            q.layout:show(show)
        end)
    end
    dap.listeners.after.event_terminated.leetcode = done
    dap.listeners.after.event_exited.leetcode = done
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
    vim.fn.writefile({
        vim.json.encode({
            solution = q.file:absolute(),
            meta = q.q.meta_data,
            cases = cases(q),
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
    manage_panes(dap, q)

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
