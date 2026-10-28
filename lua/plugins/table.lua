return {
    "kibi2/tirenvi.nvim",
    dependencies = {
        { "kibi2/tir-csv", build = "pip install ." },
        { "kibi2/tir-gfm-lite", build = "pip install ." },
        { "kibi2/tir-embedded", build = "pip install ." },
        { "tpope/vim-repeat" }, -- Optional: enables '.' repeat for column width operations
    },
    config = function()
        require("tirenvi").setup({})
        vim.keymap.set(
            { "n", "o", "x" },
            "<C-h>",
            require("tirenvi").motion.cell_prev,
            { expr = true, desc = "TirEnvi: previous cell" }
        )
        vim.keymap.set({ "n", "o", "x" }, "<C-l>", require("tirenvi").motion.cell_next, { expr = true, desc = "TirEnvi: next cell" })
        vim.keymap.set({ "n", "o", "x" }, "<C-k>", require("tirenvi").motion.block_top, { expr = true, desc = "TirEnvi: block top" })
        vim.keymap.set(
            { "n", "o", "x" },
            "<C-j>",
            require("tirenvi").motion.block_bottom,
            { expr = true, desc = "TirEnvi: block bottom" }
        )
        vim.keymap.set({ "n", "o", "x" }, "<C-u>", require("tirenvi").motion.block_top, { expr = true, desc = "TirEnvi: block up" })
        vim.keymap.set(
            { "n", "o", "x" },
            "<C-d>",
            require("tirenvi").motion.block_bottom,
            { expr = true, desc = "TirEnvi: block down" }
        )
    end,
}
