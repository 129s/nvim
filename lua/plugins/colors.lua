return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        opts = {
            flavour = "mocha",
            integrations = {
                gitsigns = true,
                rainbow_delimiters = true,
            },
            custom_highlights = function(colors)
                return {
                    RainbowDelimiterRed = { fg = colors.red },
                    RainbowDelimiterYellow = { fg = colors.yellow },
                    RainbowDelimiterBlue = { fg = colors.blue },
                    RainbowDelimiterOrange = { fg = colors.peach },
                    RainbowDelimiterGreen = { fg = colors.green },
                    RainbowDelimiterViolet = { fg = colors.mauve },
                    RainbowDelimiterCyan = { fg = colors.teal },
                }
            end,
        },
        config = function(_, opts)
            require("catppuccin").setup(opts)
            vim.cmd.colorscheme("catppuccin")
        end,
    },
    {
        "brenoprata10/nvim-highlight-colors",
        event = "VeryLazy",
        config = function()
            require("nvim-highlight-colors").setup({})
        end,
    },
}
