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
    if self:is_fullscreen() then
        ui_utils.win_set_buf(self.float, bufnr, true)
    end
end

---@return boolean
function Pane:is_fullscreen()
    return self.float ~= nil and vim.api.nvim_win_is_valid(self.float)
end

---Show the pane in a float over the whole editor. The split layout underneath
---is left as it is, so leaving fullscreen restores it exactly.
---@param on_exit fun()
function Pane:enter_fullscreen(on_exit)
    if self:is_fullscreen() then
        return
    end
    local height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
    if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
        height = height - 1
    end
    self.return_win = vim.api.nvim_get_current_win()
    self.float = vim.api.nvim_open_win(self.bufnr, true, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.o.columns,
        height = math.max(height - 1, 1),
        style = "minimal",
        zindex = 45,
    })
    ui_utils.win_set_opts(self.float, vim.tbl_extend("force", { wrap = true, linebreak = true }, self.win_opts))
    if self.winbar then
        vim.wo[self.float].winbar = self.winbar
    end
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(self.float),
        once = true,
        callback = vim.schedule_wrap(function()
            self.float = nil
            on_exit()
        end),
    })
end

function Pane:exit_fullscreen()
    if self:is_fullscreen() then
        pcall(vim.api.nvim_win_close, self.float, true)
    end
    self.float = nil
    local target = self:is_open() and self.winid or self.return_win
    if target and vim.api.nvim_win_is_valid(target) then
        vim.api.nvim_set_current_win(target)
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
    if self:is_fullscreen() then
        vim.wo[self.float].winbar = text
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
