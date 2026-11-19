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
    debug = "\u{f188}",
    image = "\u{f02e9}",
    hide = "\u{f00d}",
    fullscreen = "\u{f065}",
    restore = "\u{f066}",
    collapse_down = "\u{f078}",
    expand_up = "\u{f077}",
    collapse_right = "\u{f054}",
    expand_left = "\u{f053}",
    console_tabs = { testcase = "\u{f0349}", result = "\u{f0c8b}" },
    runtime = "\u{f0954}",
    memory = "\u{f035b}",
    tabs = {
        failed = "\u{f0159}",
        submission = "\u{f012c}",
        description = "\u{f0219}",
        editorial = "\u{f0336}",
        solutions = "\u{f0ae8}",
        submissions = "\u{f02da}",
    },
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
    debug = "◉",
    image = "▣",
    hide = "×",
    fullscreen = "⤢",
    restore = "⤡",
    collapse_down = "▾",
    expand_up = "▴",
    collapse_right = "▸",
    expand_left = "◂",
    console_tabs = { testcase = "⌕", result = "☑" },
    runtime = "◷",
    memory = "▦",
    tabs = { failed = "✗", submission = "✓", description = "▤", editorial = "✎", solutions = "☰", submissions = "✓" },
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
