return {
    {
        "aaronik/treewalker.nvim",
        lazy = false,
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function(_, opts)
            require("treewalker").setup(opts)
            if vim.fn.exists(":Treewalker") ~= 2 then
                vim.cmd("runtime plugin/init.lua")
            end
        end,
    },
    {
        "chrisgrieser/nvim-spider",
        lazy = false,
        enabled = true,
    },
}
