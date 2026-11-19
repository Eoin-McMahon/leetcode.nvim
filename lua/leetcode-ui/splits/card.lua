---Shaded blocks drawn as cards: the background starts at the text margin and
---stops the same distance from the window edge (or the reading width), so the
---card sits evenly inside the panel. Nothing is added to the buffer text;
---the fill past the end of a line is virtual text.
local Card = {}

local MARGIN = 2
local MAX_WIDTH = 88

---@param bufnr integer
---@param ns integer
---@param line_hls { row: integer, hl: string }[]
---@param width integer window width
function Card.apply(bufnr, ns, line_hls, width)
    local right = math.min(width, MAX_WIDTH) - MARGIN
    for _, l in ipairs(line_hls) do
        local line = vim.api.nvim_buf_get_lines(bufnr, l.row, l.row + 1, false)[1] or ""
        local text_width = math.max(vim.api.nvim_strwidth(line), MARGIN)
        local opts = { priority = 100 }
        if #line > MARGIN then
            opts.end_col = #line
            opts.hl_group = l.hl
        end
        if right > text_width then
            opts.virt_text = { { (" "):rep(right - text_width), l.hl } }
            opts.virt_text_win_col = text_width
        end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, l.row, math.min(MARGIN, #line), opts)
    end
end

return Card
