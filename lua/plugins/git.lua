return {
    {
        "emrearmagan/atlas.nvim",
        enabled = false,
        dependencies = {
            "nvim-tree/nvim-web-devicons", -- optional but recommended
            "sindrets/diffview.nvim", -- optional; or "dlyongemallo/diffview-plus.nvim"
        },
    },
    {
        "NeogitOrg/neogit",
        lazy = true,
        dependencies = {
            "sindrets/diffview.nvim", -- optional

            -- For a custom log pager
            "m00qek/baleia.nvim", -- optional

            -- Only one of these is needed.
            -- "nvim-telescope/telescope.nvim", -- optional
            -- "ibhagwan/fzf-lua", -- optional
            "nvim-mini/mini.pick", -- optional
            -- "folke/snacks.nvim", -- optional
        },
        cmd = "Neogit",
        keys = {
            { "<leader>tg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
        },
    },
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPost", "BufNewFile" },
        opts = {
            max_file_length = require("config.bigfile").line_count,
            current_line_blame = true,
            signs = {
                add = { text = "+" },
                change = { text = "~" },
                delete = { text = "_" },
                topdelete = { text = "^" },
                changedelete = { text = "~" },
                untracked = { text = "┆" },
            },
            on_attach = function(bufnr)
                local gitsigns = require("gitsigns")
                local map = function(mode, lhs, rhs, desc)
                    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
                end

                map("n", "]h", function()
                    if vim.wo.diff then
                        vim.cmd.normal({ "]c", bang = true })
                    else
                        gitsigns.nav_hunk("next")
                    end
                end, "Next hunk")

                map("n", "[h", function()
                    if vim.wo.diff then
                        vim.cmd.normal({ "[c", bang = true })
                    else
                        gitsigns.nav_hunk("prev")
                    end
                end, "Previous hunk")

                map({ "o", "x" }, "ih", gitsigns.select_hunk, "Select hunk")

                map({ "n", "x" }, "<leader>gs", gitsigns.stage_hunk, "Stage hunk")
                map({ "n", "x" }, "<leader>gr", gitsigns.reset_hunk, "Reset hunk")
                map("n", "<leader>gu", gitsigns.undo_stage_hunk, "Undo stage hunk")
                map("n", "<leader>gS", gitsigns.stage_buffer, "Stage buffer")
                map("n", "<leader>gR", gitsigns.reset_buffer, "Reset buffer")
                map("n", "<leader>gp", gitsigns.preview_hunk, "Preview hunk")
                map("n", "<leader>gb", gitsigns.blame_line, "Blame line")
            end,
        },
    },
}
