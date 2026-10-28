local map = vim.keymap.set

map({ "n", "x" }, "<Space>", "<Nop>", { silent = true })

-- Disable accidental navigation and editing from dedicated keyboard keys.
map({ "n", "i", "x" }, "<Home>", "<Nop>", { silent = true })
map({ "n", "i", "x" }, "<End>", "<Nop>", { silent = true })
map({ "n", "i", "x" }, "<PageUp>", "<Nop>", { silent = true })
map({ "n", "i", "x" }, "<PageDown>", "<Nop>", { silent = true })
map({ "n", "i", "x" }, "<Del>", "<Nop>", { silent = true })
map({ "n", "i", "x" }, "<Insert>", "<Nop>", { silent = true })

map({ "n", "i", "x" }, "<C-s>", "<cmd>write<cr>", { desc = "Save file" })

map("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
end, { desc = "Insert line below" })
map("n", "<S-CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { row, 0 })
end, { desc = "Insert line above" })
map("n", "<BS>", '"_dd', { desc = "Delete line" })

-- Spider owns word motions; mappings live here because config.keymaps loads after plugins.
-- config.wordmotion keeps w/b inside the line: the press that would cross the
-- newline stops at the line end/start instead.
local wordmotion = require("config.wordmotion")
map({ "n", "o", "x" }, "w", wordmotion.w, { desc = "Spider word (stops at EOL)" })
map({ "n", "o", "x" }, "b", wordmotion.b, { desc = "Spider back (stops at BOL)" })

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "nohlsearch" })

map("n", "j", function()
    return vim.v.count == 0 and "gj" or "j"
end, { expr = true, silent = true, desc = "Down" })
map("n", "k", function()
    return vim.v.count == 0 and "gk" or "k"
end, { expr = true, silent = true, desc = "Up" })

map("n", "gg", "<cmd>normal! gg^<cr>", { silent = true, remap = false, desc = "File start" })

-- Keep `0` at the first non-blank character; Shift-0 goes to column one.
map("n", "0", "^", { desc = "First non-blank" })

map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Previous search result" })
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up" })

local function cycle_buffer(direction)
    local buffers = vim.tbl_filter(function(buf)
        return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted
    end, vim.api.nvim_list_bufs())

    if #buffers == 0 then
        return
    end

    local current = vim.api.nvim_get_current_buf()
    local current_index = vim.fn.index(buffers, current) + 1
    if current_index == 0 then
        current_index = direction > 0 and 0 or 1
    end

    local next_index = ((current_index - 1 + direction) % #buffers) + 1
    vim.api.nvim_set_current_buf(buffers[next_index])
end

map("n", "<S-h>", function()
    cycle_buffer(-1)
end, { desc = "Move to prev buffer" })
map("n", "<S-l>", function()
    cycle_buffer(1)
end, { desc = "Move to next buffer" })

map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

map("x", "<", "<gv", { desc = "Indent left" })
map("x", ">", ">gv", { desc = "Indent right" })

-- path
-- map("n", "<leader>pa", function()
--     local path = vim.fn.expand("%:p")
--     vim.fn.setreg("+", path)
--     vim.notify(path, vim.log.levels.INFO, { title = "Copied path" })
-- end, { desc = "Copy file path" })

-- buffer
map("n", "<leader>bd", "<cmd>bd<cr>", { desc = "Buffer delete" })

require("config.cmdline_emacs").setup()
require("config.insert_emacs").setup()

require("config.marks").setup()

-- diagnostics
map("n", "<leader>td", function()
    vim.diagnostic.enable(not vim.diagnostic.is_enabled())
end, { desc = "Toggle diagnostics" })
map("n", "[d", function()
    vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
map("n", "]d", function()
    vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "next diagnostic" })

require("config.terminal").setup()

map("n", "<leader>cr", "<cmd>ExrcReload<cr>", { desc = "Reload project exrc" })

-- movement
-- treewalker is treesitter-only (no LSP involvement): when the buffer has no
-- parser, fall back to native paragraph/brace motions.
local treewalker_fallback = {
    move_up = "{", -- paragraph back
    move_down = "}", -- paragraph forward
    move_out = "[{", -- enclosing unmatched "{"
    move_in = "%", -- matching brace
}

local function treewalker_available()
    local ok, parser = pcall(vim.treesitter.get_parser, 0)
    return ok and parser ~= nil
end

local function treewalker_action(method)
    return function()
        if treewalker_available() or not treewalker_fallback[method] then
            require("treewalker")[method]()
        else
            vim.api.nvim_feedkeys(vim.keycode(treewalker_fallback[method]), "n", false)
        end
    end
end

vim.keymap.set({ "n", "v" }, "<C-k>", treewalker_action("move_up"), { silent = true, desc = "Move up (paragraph)" })
vim.keymap.set({ "n", "v" }, "<C-j>", treewalker_action("move_down"), { silent = true, desc = "Move down (paragraph)" })
vim.keymap.set({ "n", "v" }, "<C-h>", treewalker_action("move_out"), { silent = true, desc = "Move out (brace)" })
vim.keymap.set({ "n", "v" }, "<C-l>", treewalker_action("move_in"), { silent = true, desc = "Move in (brace)" })

-- swapping
vim.keymap.set("n", "<A-k>", treewalker_action("swap_up"), { silent = true })
vim.keymap.set("n", "<A-j>", treewalker_action("swap_down"), { silent = true })
vim.keymap.set("n", "<A-h>", treewalker_action("swap_left"), { silent = true })
vim.keymap.set("n", "<A-l>", treewalker_action("swap_right"), { silent = true })
