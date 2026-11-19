local ui_utils = require("leetcode-ui.utils")

---One managed window in the splits layout. The buffer outlives the window, so
---hiding and showing a pane never re-renders it.
---@class lc.splits.Pane
---@field name string
---@field bufnr integer
---@field winid? integer
---@field visible boolean
---@field winbar? string
---@field win_opts table
---@field cursor? integer[]
local Pane = {}
Pane.__index = Pane

---@param name string
---@param opts { buf_opts?: table, win_opts?: table, bufnr?: integer }
---@return lc.splits.Pane
function Pane.new(name, opts)
    local self = setmetatable({
        name = name,
        visible = true,
        win_opts = opts.win_opts or {},
    }, Pane)

    self.bufnr = opts.bufnr or vim.api.nvim_create_buf(false, true)
    ui_utils.buf_set_opts(
        self.bufnr,
        vim.tbl_extend("force", { bufhidden = "hide", swapfile = false, buflisted = false }, opts.buf_opts or {})
    )

    return self
end

---@return boolean
function Pane:is_open()
    return self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid)
end

---@param bufnr integer
function Pane:set_buf(bufnr)
    self.bufnr = bufnr
    if self:is_open() then
        ui_utils.win_set_buf(self.winid, bufnr, true)
    end
end

---@param parent integer window to split
---@param dir "left"|"right"|"above"|"below"
---@param size integer cells: width for left/right, height for above/below
function Pane:open(parent, dir, size)
    local vertical = dir == "left" or dir == "right"
    local config = { split = dir, win = parent }
    if vertical then
        config.width = size
    else
        config.height = size
    end

    self.winid = vim.api.nvim_open_win(self.bufnr, false, config)

    ui_utils.win_set_opts(
        self.winid,
        vim.tbl_extend("force", {
            number = false,
            relativenumber = false,
            signcolumn = "no",
            foldcolumn = "0",
            cursorline = false,
            spell = false,
            list = false,
            winfixwidth = vertical,
            winfixheight = not vertical,
        }, self.win_opts)
    )
    ui_utils.win_set_winfixbuf(self.winid)
    if self.winbar then
        vim.wo[self.winid].winbar = self.winbar
    end
    if self.cursor then
        pcall(vim.api.nvim_win_set_cursor, self.winid, self.cursor)
    end
end

---@param text string
function Pane:set_winbar(text)
    self.winbar = text
    if self:is_open() then
        vim.wo[self.winid].winbar = text
    end
end

---@param vertical boolean
---@return integer?
function Pane:size(vertical)
    if not self:is_open() then
        return
    end
    return vertical and vim.api.nvim_win_get_width(self.winid) or vim.api.nvim_win_get_height(self.winid)
end

function Pane:close()
    if self:is_open() then
        self.cursor = vim.api.nvim_win_get_cursor(self.winid)
        pcall(vim.api.nvim_win_close, self.winid, true)
    end
    self.winid = nil
end

function Pane:focus()
    if self:is_open() then
        vim.api.nvim_set_current_win(self.winid)
    end
end

function Pane:destroy()
    self:close()
    if vim.api.nvim_buf_is_valid(self.bufnr) then
        pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
    end
end

return Pane
