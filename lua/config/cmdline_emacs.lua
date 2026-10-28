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

local function insert_keys(text)
    fn.setreg(INSERT_REG, text, "v")
    return vim.keycode("<C-r><C-r>" .. INSERT_REG)
end

local function is_word(ch)
    return fn.match(ch, "\\k") >= 0
end

local function chars(str)
    return fn.split(str, "\\zs")
end

-- Converts a 1-based byte position (as getcmdpos() reports) into a
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
    local line = fn.getcmdline()
    local cs = chars(line)
    return cs, cursor_char(cs, fn.getcmdpos())
end

local function is_search()
    local cmdtype = fn.getcmdtype()
    return cmdtype == "/" or cmdtype == "?"
end

local function in_completion()
    return fn.pumvisible() == 1 or fn.wildmenumode() == 1
end

local function native(keys)
    feed(vim.keycode(keys))
end

function M.setup()
    map("c", "<C-a>", "<Home>", { desc = "Emacs: beginning of line" })
    map("c", "<C-b>", "<Left>", { desc = "Emacs: char left" })
    map("c", "<C-f>", "<Right>", { desc = "Emacs: char right" })

    map("c", "<M-b>", function()
        local cs, i = context()
        feed(repeat_key(K_LEFT, i - backward_word(cs, i)))
    end, { desc = "Emacs: word left" })

    map("c", "<M-f>", function()
        local cs, i = context()
        feed(repeat_key(K_RIGHT, forward_word(cs, i) - i))
    end, { desc = "Emacs: word right" })

    -- <C-d>: delete char under the cursor, nothing at end of line.
    map("c", "<C-d>", function()
        local cs, i = context()
        if i <= #cs then
            feed(K_DEL)
        end
    end, { desc = "Emacs: delete char" })

    -- <C-k>: kill to end of line.
    map("c", "<C-k>", function()
        local cs, i = context()
        if i > #cs then
            return
        end
        push_kill(slice(cs, i, #cs), "eol", false)
        feed(repeat_key(K_DEL, #cs - i + 1))
    end, { desc = "Emacs: kill to end of line" })

    -- <C-u>: kill to beginning of line.
    map("c", "<C-u>", function()
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
    -- kill-word-backward; <M-BS> and <M-C-h> alias it.
    map("c", "<C-w>", kill_word_back, { desc = "Emacs: kill word back" })
    map("c", "<M-BS>", kill_word_back, { desc = "Emacs: kill word back" })
    map("c", "<M-C-h>", kill_word_back, { desc = "Emacs: kill word back" })

    -- <M-d>: kill word forward.
    map("c", "<M-d>", function()
        local cs, i = context()
        local target = forward_word(cs, i)
        if target <= i then
            return
        end
        push_kill(slice(cs, i, target - 1), "word-fwd", false)
        feed(repeat_key(K_DEL, target - i))
    end, { desc = "Emacs: kill word forward" })

    map("c", "<C-y>", function()
        if in_completion() then
            native("<C-y>")
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

    map("c", "<M-y>", function()
        if in_completion() or yank.index == 0 or #ring < 2 or yank.text == "" then
            return
        end

        local cs, i = context()
        local n = #chars(yank.text)
        local from = i - n
        if from < 1 or slice(cs, from, i - 1) ~= yank.text then
            return
        end

        local index = yank.index % #ring + 1
        local text = ring[index]

        feed(repeat_key(K_BS, n) .. insert_keys(text))
        yank.index = index
        yank.text = text
    end, { desc = "Emacs: yank pop" })

    -- <C-t>: transpose the characters around the cursor.
    map("c", "<C-t>", function()
        if is_search() or in_completion() then
            native("<C-t>")
            return
        end

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

    map("c", "<C-g>", function()
        feed(vim.keycode(is_search() and "<C-g>" or "<C-c>"))
    end, { desc = "Emacs: abort" })

    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = vim.api.nvim_create_augroup("UserEmacsCmdline", { clear = true }),
        callback = function()
            last_kill = nil
            yank.index = 0
            yank.text = ""
        end,
    })
end

return M
