return {
    {
        "nvim-mini/mini.nvim",
        config = function()
            require("mini.icons").setup()
            MiniIcons.mock_nvim_web_devicons()

            -- local animate = require("mini.animate")
            -- local punchy_timing = animate.gen_timing.cubic({
            --     easing = "out",
            --     duration = 130,
            --     unit = "total",
            -- })

            -- animate.setup({
            --     cursor = { enable = false },
            --     scroll = {
            --         timing = punchy_timing,
            --         subscroll = animate.gen_subscroll.equal({ max_output_steps = 80 }),
            --     },
            --     resize = {
            --         timing = punchy_timing,
            --         subresize = animate.gen_subresize.equal(),
            --     },
            --     open = {
            --         timing = punchy_timing,
            --         winconfig = animate.gen_winconfig.wipe({ direction = "from_edge" }),
            --         winblend = animate.gen_winblend.linear({ from = 75, to = 100 }),
            --     },
            --     close = {
            --         timing = punchy_timing,
            --         winconfig = animate.gen_winconfig.wipe({ direction = "to_edge" }),
            --         winblend = animate.gen_winblend.linear({ from = 100, to = 75 }),
            --     },
            -- })
            local ai = require("mini.ai")
            local ts_ai = ai.gen_spec.treesitter
            local ts_capture = function(capture)
                return ts_ai({ a = capture, i = capture })
            end

            ai.setup({
                goto_left = "gh",
                goto_right = "gl",
                custom_textobjects = {
                    a = ts_ai({ a = "@assignment.outer", i = "@assignment.inner" }),
                    x = ts_ai({ a = "@parameter.outer", i = "@parameter.inner" }),
                    c = ts_ai({ a = "@call.outer", i = "@call.inner" }),
                    -- b = ts_ai({ a = "@block.outer", i = "@block.inner" }),
                    f = ts_ai({ a = "@function.outer", i = "@function.inner" }),
                    t = ts_ai({ a = "@class.outer", i = "@class.inner" }),
                    i = ts_ai({ a = "@conditional.outer", i = "@conditional.inner" }),
                    l = ts_ai({ a = "@loop.outer", i = "@loop.inner" }),
                    r = ts_ai({ a = "@return.outer", i = "@return.inner" }),
                    s = ts_capture("@statement.outer"),
                },
            })
            require("mini.comment").setup({
                mappings = {
                    -- toggle comment (like `gcip` - comment inner paragraph) for both
                    -- normal and visual modes
                    comment = "gc",

                    -- Toggle comment on current line
                    comment_line = "gcc",

                    -- Toggle comment on visual selection
                    comment_visual = "gc",

                    -- Define 'comment' textobject (like `dgc` - delete whole comment block)
                    -- Works also in Visual mode if mapping differs from `comment_visual`
                    textobject = "gc",
                },
            })
            require("mini.pairs").setup({
                -- In which modes mappings from this `config` should be created
                modes = { insert = true, command = true, terminal = true },

                -- Global mappings. Each right hand side should be a pair information, a
                -- table with at least these fields (see more in |MiniPairs.map|):
                -- - <action> - one of 'open', 'close', 'closeopen'.
                -- - <pair> - two character string for pair to be used.
                -- By default pair is not inserted after `\`, quotes are not recognized by
                -- <CR>, `'` does not insert the pair after a letter.
                -- Only parts of tables can be tweaked (others will use these defaults).
                mappings = {
                    ["("] = { action = "open", pair = "()", neigh_pattern = "^[^\\]" },
                    ["["] = { action = "open", pair = "[]", neigh_pattern = "^[^\\]" },
                    ["{"] = { action = "open", pair = "{}", neigh_pattern = "^[^\\]" },

                    [")"] = { action = "close", pair = "()", neigh_pattern = "^[^\\]" },
                    ["]"] = { action = "close", pair = "[]", neigh_pattern = "^[^\\]" },
                    ["}"] = { action = "close", pair = "{}", neigh_pattern = "^[^\\]" },

                    ['"'] = { action = "closeopen", pair = '""', neigh_pattern = "^[^\\]", register = { cr = false } },
                    ["'"] = { action = "closeopen", pair = "''", neigh_pattern = "^[^%a\\]", register = { cr = false } },
                    ["`"] = { action = "closeopen", pair = "``", neigh_pattern = "^[^\\]", register = { cr = false } },
                },
            })
            require("mini.surround").setup()
            require("mini.bufremove").setup()
            require("mini.cmdline").setup({
                autocomplete = {
                    enable = true,
                    delay = 0,
                    predicate = function(data)
                        return data.line ~= ""
                    end,
                    map_arrows = true,
                },
                autocorrect = {
                    enable = false,
                },
                autopeek = {
                    enable = true,
                },
            })

            require("config.files").setup()
        end,
    },
}
