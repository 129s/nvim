vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = false
vim.o.exrc = true
require("config.exrc")

pcall(vim.loader.enable)

require("config.lazy")
