local config = require("leetcode.config")
local log = require("leetcode.logger")

---Editor help in a problem's code buffer. Off by default to match the website:
---no language servers (so no completion, diagnostics, hover or Copilot) and no
---completion menu. Errors appear only after a run, on the line they point at.
local Assist = {}

local JUDGE_NS = vim.api.nvim_create_namespace("leetcode_judge")
local group = vim.api.nvim_create_augroup("leetcode_assist", { clear = true })

---@param bufnr integer
local function detach_all(bufnr)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        pcall(vim.lsp.buf_detach_client, bufnr, client.id)
    end
end

---@param bufnr integer
---@param enabled boolean
local function set_cmp(bufnr, enabled)
    local ok, cmp = pcall(require, "cmp")
    if ok and cmp.setup and cmp.setup.buffer then
        vim.api.nvim_buf_call(bufnr, function()
            pcall(cmp.setup.buffer, { enabled = enabled })
        end)
    end
end

---@param q lc.ui.Question
---@return boolean
function Assist.enabled(q)
    if q.assist == nil then
        return config.user.editor.assist
    end
    return q.assist
end

---Apply the current setting to the question's code buffer.
---@param q lc.ui.Question
function Assist.apply(q)
    local bufnr = q.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })

    if Assist.enabled(q) then
        set_cmp(bufnr, true)
        -- vim.lsp.enable() attaches on FileType; replay it to reattach.
        vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
        pcall(function()
            require("copilot.client").buf_attach(true, bufnr)
        end)
        return
    end

    detach_all(bufnr)
    set_cmp(bufnr, false)
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        buffer = bufnr,
        callback = function(args)
            vim.schedule(function()
                pcall(vim.lsp.buf_detach_client, bufnr, args.data.client_id)
            end)
        end,
    })
end

---@param q lc.ui.Question
function Assist.toggle(q)
    q.assist = not Assist.enabled(q)
    Assist.apply(q)
    log.info(q.assist and "Editor help on: language servers and completion" or "Editor help off, like the website")
end

---Underline the line a compile or runtime error points at, as the website does
---after a run. Only the underline: the message stays in the result panel.
---Cleared on the next edit or run.
---@param q lc.ui.Question
---@param item table run or submit response
function Assist.mark_error(q, item)
    local bufnr = q.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    vim.api.nvim_buf_clear_namespace(bufnr, JUDGE_NS, 0, -1)

    local err = item.status_code == 20 and (item.full_compile_error or item.compile_error)
        or (item.full_runtime_error or item.runtime_error)
    if type(err) ~= "string" or err == "" then
        return
    end
    local line = tonumber(err:match("Line (%d+)"))
    if not line then
        return
    end

    -- Runs send the file's leading lines as blank lines, so line numbers match
    -- the buffer. Submissions send only the code section.
    local submitted = item._ and item._.submission or item.past
    if submitted then
        local range = q:editor_section_range("code")
        line = (range.start_i or 1) - 1 + line
    end

    local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    if not text then
        return
    end
    local first = #(text:match("^%s*"))
    vim.api.nvim_buf_set_extmark(bufnr, JUDGE_NS, line - 1, first, {
        end_col = #text,
        hl_group = "DiagnosticUnderlineError",
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = bufnr,
        once = true,
        callback = function()
            vim.api.nvim_buf_clear_namespace(bufnr, JUDGE_NS, 0, -1)
        end,
    })
end

return Assist
