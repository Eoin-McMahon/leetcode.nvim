local M = {}

---Get highlight group value by name.
---
---@param name string String for looking up highlight group.
---@return table
local function hl(name)
    local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
    setmetatable(highlight, {
        __index = function(self, key)
            if key == "bg" then
                return self.background
            end
            if key == "fg" then
                return self.foreground
            end

            return nil
        end,
    })

    return highlight
end

---Mix `fg` into `bg`. `ratio` 1 is all `fg`.
---@param fg? integer
---@param bg? integer
---@param ratio number
---@return integer?
local function blend(fg, bg, ratio)
    if not fg then
        return nil
    end
    bg = bg or (vim.o.background == "dark" and 0x000000 or 0xffffff)

    local function channel(shift)
        local a = bit.band(bit.rshift(fg, shift), 0xff)
        local b = bit.band(bit.rshift(bg, shift), 0xff)
        return bit.lshift(math.floor(a * ratio + b * (1 - ratio) + 0.5), shift)
    end
    return channel(16) + channel(8) + channel(0)
end

---Colors taken from the user's colorscheme in place of LeetCode's own.
---@return lc.highlights
local function from_colorscheme()
    local bg = hl("Normal").bg
    local ok, warn, err = hl("DiagnosticOk").fg, hl("DiagnosticWarn").fg, hl("DiagnosticError").fg

    local tbl = {
        easy = { fg = ok },
        medium = { fg = warn },
        hard = { fg = err },

        easy_alt = { fg = blend(ok, bg, 0.3) },
        medium_alt = { fg = blend(warn, bg, 0.3) },
        hard_alt = { fg = blend(err, bg, 0.3) },

        all_alt = { fg = blend(hl("Normal").fg, bg, 0.25) },
        calendar_0 = { fg = blend(hl("Normal").fg, bg, 0.2) },
    }
    for level = 10, 100, 10 do
        tbl["calendar_" .. level] = { fg = blend(ok, bg, 0.2 + 0.8 * level / 100) }
    end

    return tbl
end

---@alias lc.highlights table<string, vim.api.keyset.highlight>

---@return lc.highlights
M.get = function()
    local config = require("leetcode.config")
    local tbl = config.user.leetcode_colors and M.leetcode() or vim.tbl_extend("force", M.leetcode(), from_colorscheme())
    return vim.tbl_extend("force", tbl, M.description(tbl))
end

---Groups for the splits description: plain text, with only the title,
---headings, code and pills styled.
---@param tbl lc.highlights
---@return lc.highlights
M.description = function(tbl)
    local normal = hl("Normal")
    local bg = normal.bg
    local code_fg = hl("@markup.raw").fg or hl("String").fg
    local out = {
        desc_title = { fg = normal.fg, bold = true },
        desc_heading = { fg = normal.fg, bold = true },
        desc_bold = { fg = normal.fg, bold = true },
        desc_italic = { italic = true },
        desc_code = { fg = code_fg, bg = blend(normal.fg, bg, 0.1) },
        desc_link = { fg = hl("Function").fg, underline = true },
        desc_dim = { fg = hl("Comment").fg },
        desc_rule = { fg = hl("WinSeparator").fg or hl("Comment").fg },
        desc_block = { bg = blend(normal.fg, bg, 0.07) },
        pill = { fg = hl("Comment").fg },
        desc_input = { fg = hl("DiagnosticInfo").fg, bold = true },
        desc_output = { fg = hl("DiagnosticOk").fg, bold = true },
        desc_explain = { fg = hl("DiagnosticHint").fg, bold = true },
        chart_bar = { fg = blend(normal.fg, bg, 0.35) },
        chart_mine = { fg = hl("Function").fg or hl("DiagnosticInfo").fg },
        chip_active = { fg = normal.fg, bg = blend(normal.fg, bg, 0.16), bold = true },
        result_ok = { fg = hl("DiagnosticOk").fg, bold = true },
        result_err = { fg = hl("DiagnosticError").fg, bold = true },
        block_ok = { bg = blend(hl("DiagnosticOk").fg, bg, 0.12) },
        block_err = { bg = blend(hl("DiagnosticError").fg, bg, 0.12) },
    }
    for _, level in ipairs({ "easy", "medium", "hard" }) do
        local fg = tbl[level] and tbl[level].fg
        out["pill_" .. level] = { fg = fg, bg = blend(fg, bg, 0.2), bold = true }
    end
    return out
end

---@return lc.highlights
M.leetcode = function()
    return {
        [""] = { fg = hl("Normal").fg },

        easy = { fg = "#46c6c2" },
        medium = { fg = "#fac31d" },
        hard = { fg = "#f8615c" },

        easy_alt = { fg = "#294d35" },
        medium_alt = { fg = "#5e4e25" },
        hard_alt = { fg = "#5a302f" },

        ok = { fg = hl("DiagnosticOk").fg },
        info = { fg = hl("DiagnosticInfo").fg },
        hint = { fg = hl("DiagnosticHint").fg },
        error = { fg = hl("DiagnosticError").fg },

        case_ok = { fg = hl("DiagnosticOk").fg, bg = hl("Normal").bg, bold = true },
        case_err = { fg = hl("DiagnosticError").fg, bg = hl("Normal").bg, bold = true },

        case_focus_ok = { bg = hl("DiagnosticOk").fg, fg = hl("NormalSB").bg, bold = true },
        case_focus_err = { bg = hl("DiagnosticError").fg, fg = hl("NormalSB").bg, bold = true },

        normal = { fg = hl("Conceal").fg },
        alt = { fg = hl("Comment").fg },

        italic = { italic = true },
        bold = { bold = true },
        underline = { underline = true },

        code = { fg = hl("Type").fg, bg = hl("Normal").bg },
        example = { fg = hl("DiagnosticHint").fg },
        constraints = { fg = hl("DiagnosticInfo").fg },
        header = { fg = hl("SpecialChar").fg, bold = true },
        followup = { fg = hl("Number").fg, bold = true },

        indent = { fg = hl("Comment").fg },
        link = { fg = hl("Function").fg, underline = true },
        list = { fg = hl("SpecialChar").fg },
        ref = { fg = hl("Tag").fg },
        su = { fg = hl("Number").fg },

        -- calendar
        calendar_0 = { fg = "#45475b" },
        calendar_10 = { fg = "#004d1b" },
        calendar_20 = { fg = "#016620" },
        calendar_30 = { fg = "#078029" },
        calendar_40 = { fg = "#109932" },
        calendar_50 = { fg = "#1cb33d" },
        calendar_60 = { fg = "#28c244" },
        calendar_70 = { fg = "#51d164" },
        calendar_80 = { fg = "#7fe18b" },
        calendar_90 = { fg = "#b3f0b8" },
        calendar_100 = { fg = "#d8ffda" },

        all = { fg = hl("Normal").fg },
        all_alt = { fg = "#45475b" },
    }
end

return M
