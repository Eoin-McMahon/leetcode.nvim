local icons = {
    bar = "│",
    circle = "",
    square = "󱓻",
    lock = "",
    unlock = "",
    star = "",
    run = "\u{f04b}",
    submit = "\u{f093}",
    upvote = "\u{f062}",
    reset = "\u{f0e2}",
    add = "\u{f067}",
    param = "\u{f0da}",
    status = {
        ac = "",
        notac = "󱎖",
        todo = "",
    },
    caret = {
        right = "",
    },
}

icons.hl = {
    status = {
        ac = { icons.status.ac, "leetcode_easy" },
        notac = { icons.status.notac, "leetcode_medium" },
        -- todo = { icons.status.todo, "leetcode_alt" },
    },
    lock = { icons.lock, "leetcode_medium" },
    unlock = { icons.unlock, "leetcode_medium" },
}

icons.indent = ("\t%s "):format(icons.bar)

---Replacements for terminals without a Nerd Font (`nerd_font = false`).
icons.plain = {
    circle = "●",
    square = "■",
    lock = "[P]",
    unlock = "[P]",
    star = "★",
    run = "▶",
    submit = "⇪",
    upvote = "▲",
    reset = "↺",
    add = "+",
    param = "›",
    status = { ac = "✓", notac = "✗", todo = "·" },
    caret = { right = ">" },
}

---Swap in the plain glyphs, keeping `icons.hl` in step.
function icons.use_plain()
    for key, value in pairs(icons.plain) do
        if type(value) == "table" then
            icons[key] = vim.tbl_extend("force", icons[key], value)
        else
            icons[key] = value
        end
    end
    icons.hl.status.ac[1] = icons.status.ac
    icons.hl.status.notac[1] = icons.status.notac
    icons.hl.lock[1] = icons.lock
    icons.hl.unlock[1] = icons.unlock
end

return icons
