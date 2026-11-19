local Button = require("leetcode-ui.lines.button")
local t = require("leetcode.translator")

local log = require("leetcode.logger")

---@class lc.ui.Button.Menu : lc.ui.Button
local MenuButton = Button:extend("LeetMenuButton")

---@alias lc.ui.Button.Menu.opts
---| { expandable?: boolean, expand_icon?: string, icon: string, width?: integer }
---| lc.ui.Button.opts

---@param text string
---@param opts lc.ui.Button.Menu.opts
function MenuButton:init(text, opts)
    text = t(text)
    opts = vim.tbl_deep_extend("force", {
        expandable = false,
        expand_icon = "",
        width = 50,
    }, opts or {})
    MenuButton.super.init(self, {}, opts)

    -- Laid out like a dashboard entry: icon, label, key on the right. No
    -- chevron on entries that open a page.
    self:append(opts.icon, "leetcode_menu_icon")
    self:append("  ")
    self:append(text, "leetcode_menu_label")

    local len = vim.api.nvim_strwidth(self:content()) + vim.api.nvim_strwidth(opts.sc or "")
    local padding = (" "):rep(math.max(opts.width - len, 1))

    self:append(padding)
    if opts.sc then
        self:append(opts.sc, "leetcode_menu_key")
    end
end

---@type fun(text: string, opts: lc.ui.Button.Menu.opts): lc.ui.Button
local LeetMenuButton = MenuButton

return LeetMenuButton
