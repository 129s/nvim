return {
    {
        "gbprod/cutlass.nvim",
        opts = {
            cut_key = "e",
            -- Select-mode quote keys are mapped below so they still pair.
            exclude = { 's"', "s'", "s`" },
        },
        config = function(_, opts)
            require("cutlass").setup(opts)

            -- Snippet placeholders (blink.cmp + LuaSnip) leave the cursor in
            -- Select mode. Native selection replacement defers to Insert mode
            -- mappings, but cutlass maps every printable Select-mode key to a
            -- single black-hole replacement, so quotes would never pair.
            -- Replace the selection into "_ and insert the pair, cursor inside.
            for _, pair in ipairs({ '""', "''", "``" }) do
                vim.keymap.set("s", pair:sub(1, 1), '<C-o>"_c' .. pair .. "<Left>", {
                    desc = "Pair " .. pair .. " in Select mode",
                })
            end
        end,
    },
    {
        "L3MON4D3/LuaSnip",
        keys = function()
            -- Disable default tab keybinding in LuaSnip
            return {}
        end,
    },
    {
        "monaqa/dial.nvim",
        config = function()
            local augend = require("dial.augend")
            require("dial.config").augends:register_group({
                default = {
                    augend.integer.alias.decimal_int,
                    augend.integer.alias.hex,
                    augend.date.alias["%Y/%m/%d"],
                    augend.date.alias["%Y-%m-%d"],
                    augend.semver.alias.semver,
                    augend.constant.alias.bool,
                    augend.constant.alias.Bool,
                    augend.constant.alias.alpha,
                    augend.constant.alias.Alpha,
                    augend.hexcolor.new({ case = "prefer_lower" }),
                },
            })

            local map = require("dial.map")
            vim.keymap.set("n", "<C-a>", map.inc_normal(), { desc = "Dial increment" })
            vim.keymap.set("n", "<C-x>", map.dec_normal(), { desc = "Dial decrement" })
            vim.keymap.set("n", "g<C-a>", map.inc_gnormal(), { desc = "Dial increment sequence" })
            vim.keymap.set("n", "g<C-x>", map.dec_gnormal(), { desc = "Dial decrement sequence" })
            vim.keymap.set("x", "<C-a>", map.inc_visual(), { desc = "Dial increment selection" })
            vim.keymap.set("x", "<C-x>", map.dec_visual(), { desc = "Dial decrement selection" })
            vim.keymap.set("x", "g<C-a>", map.inc_gvisual(), { desc = "Dial increment selection sequence" })
            vim.keymap.set("x", "g<C-x>", map.dec_gvisual(), { desc = "Dial decrement selection sequence" })
        end,
    },
    {
        "SunnyTamang/select-undo.nvim",
        opts = {},
    },
    {
        "RaafatTurki/hex.nvim",
        config = function()
            require("hex").setup()
        end,
    },
    {
        "Wansmer/treesj",
        enabled = false,
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("treesj").setup({
                use_default_keymaps = false,
            })
            vim.keymap.set("n", "<leader>s", require("treesj").toggle)
            vim.keymap.set("n", "<leader>S", function()
                require("treesj").toggle({ split = { recursive = true } })
            end)
        end,
    },
    {
        "attilarepka/header.nvim",
        enabled = false,
        config = function()
            require("header").setup()
            local header = require("header")
            vim.keymap.set("n", "<leader>ih", function()
                header.add_header()
            end)
            vim.keymap.set("n", "<leader>im", function()
                header.add_license_header("mit")
            end)
        end,
    },
    {
        "qwavies/smart-backspace.nvim",
        event = "VeryLazy",
    },
    {
        "nemanjamalesija/smart-paste.nvim",
        event = "VeryLazy",
        config = function()
            local smart_paste = require("smart-paste")
            local paste = require("smart-paste.paste")
            smart_paste.setup()

            -- Wrap the shared paste path so dot-repeat keeps the same cursor behavior.
            local original_smart_paste = paste.smart_paste
            local original_do_paste = paste.do_paste
            local restore_after_paste = false

            local function restore_cursor(cursor)
                local line_count = vim.api.nvim_buf_line_count(0)
                local row = math.min(cursor[1], line_count)
                local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
                local column = math.min(cursor[2], #line)
                vim.api.nvim_win_set_cursor(0, { row, column })
            end

            paste.smart_paste = function(key_entry, context)
                restore_after_paste = key_entry.lhs ~= "gp" and key_entry.lhs ~= "gP"
                return original_smart_paste(key_entry, context)
            end

            paste.do_paste = function(motion_type)
                local cursor = restore_after_paste and vim.api.nvim_win_get_cursor(0) or nil
                original_do_paste(motion_type)
                if cursor then
                    restore_cursor(cursor)
                end
            end
        end,
    },
    {
        "cutehax0r/hide-comment.nvim",
        config = function()
            require("hide-comment").setup()
            local hide = require("hide-comment")
            vim.keymap.set("n", "<leader>tc", function()
                hide.toggle()
                vim.cmd.redrawstatus()
            end, { desc = "Toggle comment visibility" })
        end,
    },
    {
        "mateuszwieloch/automkdir.nvim",
        enabled = false,
        lazy = false,
        opts = {},
    },
}
