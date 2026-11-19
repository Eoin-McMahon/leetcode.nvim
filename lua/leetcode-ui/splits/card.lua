---Shaded blocks drawn as cards: the background starts at the text margin and
---stops the same distance from the window edge (or the reading width), so the
---card sits evenly inside the panel. Nothing is added to the buffer text;
---the fill past the end of a line is virtual text.
local Card = {}

Card.MARGIN = 2
Card.MAX_WIDTH = 88

---@class lc.card.Geometry
---@field offset integer columns before the content (centering)
---@field width integer content width, at most `MAX_WIDTH`
---@field left integer first column of the card background
---@field right integer column after the card background

---@param win_width integer
---@param center? boolean centre the content when the window is wider than it
---@return lc.card.Geometry
function Card.geometry(win_width, center)
    local width = math.min(win_width, Card.MAX_WIDTH)
    local offset = center and math.floor((win_width - width) / 2) or 0
    return {
        offset = offset,
        width = width,
        left = offset + Card.MARGIN,
        right = offset + width - Card.MARGIN,
    }
end

---@param bufnr integer
---@param ns integer
---@param line_hls { row: integer, hl: string, wide?: boolean }[] `wide` cards span the window, not the reading width
---@param win_width integer
---@param center? boolean the lines are shifted by the geometry's offset
function Card.apply(bufnr, ns, line_hls, win_width, center)
    local g = Card.geometry(win_width, center)
    for _, l in ipairs(line_hls) do
        local right = l.wide and (win_width - Card.MARGIN) or g.right
        local line = vim.api.nvim_buf_get_lines(bufnr, l.row, l.row + 1, false)[1] or ""
        local text_width = math.max(vim.api.nvim_strwidth(line), g.left)
        local opts = { priority = 100 }
        if #line > g.left then
            opts.end_col = #line
            opts.hl_group = l.hl
        end
        if right > text_width then
            opts.virt_text = { { (" "):rep(right - text_width), l.hl } }
            opts.virt_text_win_col = text_width
        end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, l.row, math.min(g.left, #line), opts)
    end
end

return Card
