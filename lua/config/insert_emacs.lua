local M = {}

local map = vim.keymap.set
local fn = vim.fn

local RING_MAX = 60
local INSERT_REG = "-"

local ring = {}
local last_kill = nil

-- Text inserted by the most recent <C-y>, used by <M-y>.
local yank = { index = 0, text = "" }

local K_BS = vim.keycode("<BS>")
local K_DEL = vim.keycode("<Del>")
local K_LEFT = vim.keycode("<Left>")
local K_RIGHT = vim.keycode("<Right>")
local K_UP = vim.keycode("<Up>")
local K_DOWN = vim.keycode("<Down>")

-- Keys are inserted at the front of the typeahead buffer ("i") so that they
-- run before keys the user already typed; every mapping therefore feeds a
-- single string, built in input order.
local function feed(keys)
    if keys ~= "" then
        vim.api.nvim_feedkeys(keys, "ni", false)
    end
end

local function repeat_key(key, count)
    return count > 0 and key:rep(count) or ""
end

-- <C-r><C-o> inserts the register literally without auto-indent. Unlike
-- <C-r><C-r>, it also inserts embedded newlines once instead of replaying the
-- text after each newline.
local function insert_keys(text)
    fn.setreg(INSERT_REG, text, "v")
    return vim.keycode("<C-r><C-o>" .. INSERT_REG)
end

local function is_word(ch)
    return fn.match(ch, "\\k") >= 0
end

local function chars(str)
    return fn.split(str, "\\zs")
end

-- Converts a 1-based byte position (as col(".") reports in Insert mode) into a
-- 1-based character index (1 .. #cs + 1).
local function cursor_char(cs, pos)
    local target = pos - 1
    local acc = 0
    for i = 1, #cs do
        acc = acc + #cs[i]
        if acc > target then
            return i
        end
    end
    return #cs + 1
end

local function slice(cs, from, to)
    local out = {}
    for i = from, to do
        out[#out + 1] = cs[i]
    end
    return table.concat(out)
end

local function forward_word(cs, index)
    local i = index
    while i <= #cs and not is_word(cs[i]) do
        i = i + 1
    end
    while i <= #cs and is_word(cs[i]) do
        i = i + 1
    end
    return i
end

local function backward_word(cs, index)
    local i = index - 1
    while i >= 1 and not is_word(cs[i]) do
        i = i - 1
    end
    while i >= 1 and is_word(cs[i]) do
        i = i - 1
    end
    return i + 1
end

local function push_kill(text, kind, prepend)
    if text == "" then
        return
    end

    if last_kill == kind and ring[1] then
        ring[1] = prepend and (text .. ring[1]) or (ring[1] .. text)
    else
        table.insert(ring, 1, text)
        if #ring > RING_MAX then
            ring[#ring] = nil
        end
    end

    last_kill = kind
    yank.index = 0
    yank.text = ""
end

local function context()
    local line = fn.getline(".")
    local cs = chars(line)
    return cs, cursor_char(cs, fn.col("."))
end

-- Text between the start of a window of lines and the insert position. The
-- window is wide enough for any yank: every newline in the yank is one char,
-- so it can span at most #chars(yank.text) lines.
local function text_before_cursor(char_count)
    local lnum = fn.line(".")
    local first = math.max(1, lnum - char_count)
    local parts = fn.getline(first, lnum - 1)
    local text = table.concat(parts, "\n")
    if #parts > 0 then
        text = text .. "\n"
    end
    return text .. fn.getline("."):sub(1, fn.col(".") - 1)
end

local function in_completion()
    return fn.pumvisible() == 1
end

-- Runs a blink.cmp command only while its menu is open. blink's own keymaps
-- would do this through `fallback`, but that schedules the fallback callback;
-- checking here keeps the following key in the typeahead in the right order.
local function completion(cmd)
    local ok, cmp = pcall(require, "blink.cmp")
    if not ok then
        return false
    end

    local visible_ok, visible = pcall(cmp.is_menu_visible)
    if not visible_ok or not visible then
        return false
    end

    cmp[cmd]()
    return true
end

function M.setup()
    map("i", "<C-a>", "<Home>", { desc = "Emacs: beginning of line" })

    map("i", "<C-e>", function()
        if completion("cancel") then
            return
        end
        feed(vim.keycode("<End>"))
    end, { desc = "Emacs: end of line" })

    map("i", "<C-b>", "<Left>", { desc = "Emacs: char left" })
    map("i", "<C-f>", "<Right>", { desc = "Emacs: char right" })

    map("i", "<C-p>", function()
        if completion("select_prev") then
            return
        end
        feed(K_UP)
    end, { desc = "Emacs: line up" })

    map("i", "<C-n>", function()
        if completion("select_next") then
            return
        end
        feed(K_DOWN)
    end, { desc = "Emacs: line down" })

    map("i", "<C-d>", "<Del>", { desc = "Emacs: delete char" })
    map("i", "<C-l>", "<C-o>zz", { desc = "Emacs: recenter" })

    -- <C-k>: kill to the end of the line. At the end of a non-last line kill
    -- the newline too, like Emacs kill-line.
    map("i", "<C-k>", function()
        local cs, i = context()
        if i <= #cs then
            push_kill(slice(cs, i, #cs), "eol", false)
            feed(repeat_key(K_DEL, #cs - i + 1))
        elseif fn.line(".") < fn.line("$") then
            push_kill("\n", "eol", false)
            feed(K_DEL)
        end
    end, { desc = "Emacs: kill to end of line" })

    -- <C-u>: kill to the beginning of the line.
    map("i", "<C-u>", function()
        local cs, i = context()
        if i <= 1 then
            return
        end
        push_kill(slice(cs, 1, i - 1), "bol", true)
        feed(repeat_key(K_BS, i - 1))
    end, { desc = "Emacs: kill to beginning of line" })

    local function kill_word_back()
        local cs, i = context()
        local target = backward_word(cs, i)
        if target >= i then
            return
        end
        push_kill(slice(cs, target, i - 1), "word-back", true)
        feed(repeat_key(K_BS, i - target))
    end

    -- <C-w> is Emacs' kill-region, but in a shell/readline context it means
    -- kill-word-backward; <M-BS>, <M-Del> and <M-C-h> alias it.
    map("i", "<C-w>", kill_word_back, { desc = "Emacs: kill word back" })
    map("i", "<M-BS>", kill_word_back, { desc = "Emacs: kill word back" })
    map("i", "<M-Del>", kill_word_back, { desc = "Emacs: kill word back" })
    map("i", "<M-C-h>", kill_word_back, { desc = "Emacs: kill word back" })

    map("i", "<M-b>", function()
        local cs, i = context()
        feed(repeat_key(K_LEFT, i - backward_word(cs, i)))
    end, { desc = "Emacs: word left" })

    map("i", "<M-f>", function()
        local cs, i = context()
        feed(repeat_key(K_RIGHT, forward_word(cs, i) - i))
    end, { desc = "Emacs: word right" })

    -- <M-d>: kill word forward.
    map("i", "<M-d>", function()
        local cs, i = context()
        local target = forward_word(cs, i)
        if target <= i then
            return
        end
        push_kill(slice(cs, i, target - 1), "word-fwd", false)
        feed(repeat_key(K_DEL, target - i))
    end, { desc = "Emacs: kill word forward" })

    map("i", "<C-y>", function()
        if completion("select_and_accept") then
            return
        end

        local text = ring[1]
        if text == nil or text == "" then
            return
        end

        feed(insert_keys(text))
        yank.index = 1
        yank.text = text
    end, { desc = "Emacs: yank" })

    map("i", "<M-y>", function()
        if in_completion() or yank.index == 0 or #ring < 2 or yank.text == "" then
            return
        end

        local n = #chars(yank.text)
        local before = text_before_cursor(n)
        local total = fn.strchars(before)
        if total < n or fn.strcharpart(before, total - n, n) ~= yank.text then
            return
        end

        local index = yank.index % #ring + 1
        local text = ring[index]

        feed(repeat_key(K_BS, n) .. insert_keys(text))
        yank.index = index
        yank.text = text
    end, { desc = "Emacs: yank pop" })

    -- <C-t>: transpose the characters around the cursor.
    map("i", "<C-t>", function()
        local cs, i = context()
        if #cs < 2 or i == 1 then
            return
        end

        if i > #cs then
            -- At end of line: swap the last two characters, stay at the end.
            local a, b = cs[#cs - 1], cs[#cs]
            feed(repeat_key(K_BS, 2) .. insert_keys(b .. a))
        else
            -- Swap the character before the cursor with the one under it.
            local a, b = cs[i - 1], cs[i]
            feed(K_RIGHT .. repeat_key(K_BS, 2) .. insert_keys(b .. a))
        end
    end, { desc = "Emacs: transpose chars" })

    vim.api.nvim_create_autocmd("InsertLeave", {
        group = vim.api.nvim_create_augroup("UserEmacsInsert", { clear = true }),
        callback = function()
            last_kill = nil
            yank.index = 0
            yank.text = ""
        end,
    })
end

return M
