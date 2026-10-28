if vim.env.SSH_TTY then
    vim.g.clipboard = {
        name = "OSC 52",
        copy = {
            ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
            ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
        },
        paste = {
            ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
            ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
        },
    }
end
local opt = vim.opt

vim.g.have_nerd_font = true
opt.termguicolors = true
opt.number = true
opt.numberwidth = 3
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.wrap = true
vim.opt.linebreak = true

opt.scrolloff = 16
opt.sidescrolloff = 8

opt.smartindent = true
opt.autoindent = true

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
opt.inccommand = "split"

opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.swapfile = false
opt.autoread = true
opt.backup = false
opt.writebackup = false
opt.confirm = true
opt.showmode = false
opt.cmdheight = 1
opt.updatetime = 250
opt.timeoutlen = 500
opt.splitright = true
opt.splitbelow = true
opt.fillchars = { eob = " " }
opt.list = true
opt.listchars = { tab = "  ", trail = ".", nbsp = "+" }
opt.completeopt = "menu,menuone,noselect"

opt.foldlevel = 99
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

pcall(function()
    vim.o.winborder = "single"
end)

pcall(function()
    vim.o.pumborder = "single"
end)

vim.o.winbar = ""
