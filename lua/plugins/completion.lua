local source_icons = {
    -- avante = "󰚩",
    buffer = "",
    cmdline = "",
    copilot = "",
    lazydev = "",
    lsp = "",
    path = "",
    snippets = "",
}

local source_names = {
    -- avante = "AI",
    buffer = "Buf",
    cmdline = "Cmd",
    copilot = "Copilot",
    lazydev = "Lua",
    lsp = "LSP",
    path = "Path",
    snippets = "Snip",
}

local function get_mini_icon(ctx)
    local ok, mini_icons = pcall(require, "mini.icons")
    if not ok then
        return ctx.kind_icon, ctx.kind_hl
    end

    if ctx.source_id == "path" and ctx.item ~= nil and ctx.item.data ~= nil and ctx.item.data.type ~= nil then
        local unknown_types = { link = true, socket = true, fifo = true, char = true, block = true, unknown = true }
        local icon_type = unknown_types[ctx.item.data.type] and "os" or ctx.item.data.type
        local icon_name = unknown_types[ctx.item.data.type] and "" or ctx.label
        local icon, hl = mini_icons.get(icon_type, icon_name)
        if icon ~= nil then
            return icon, hl
        end
    end

    local icon, hl = mini_icons.get("lsp", ctx.kind)
    return icon or ctx.kind_icon, hl or ctx.kind_hl
end

local function source_icon(ctx)
    if ctx.source_id == "buffer" and vim.api.nvim_get_mode().mode == "c" then
        local cmdtype = vim.fn.getcmdtype()
        if cmdtype == "/" then
            return ""
        elseif cmdtype == "?" then
            return ""
        end
    end

    return source_icons[ctx.source_id] or "•"
end

local function source_highlight(ctx)
    if ctx.source_id == "buffer" and vim.api.nvim_get_mode().mode == "c" then
        return "BlinkCmpSearchIcon"
    end

    if ctx.source_id == "cmdline" then
        return "BlinkCmpCmdlineIcon"
    end

    return "BlinkCmpSourceIcon"
end

local function setup_blink_highlights()
    local links = {
        BlinkCmpCmdlineIcon = "MiniFilesDirectory",
        BlinkCmpDoc = "MiniFilesNormal",
        BlinkCmpDocBorder = "MiniFilesBorder",
        BlinkCmpKind = "MiniFilesDirectory",
        BlinkCmpLabel = "MiniFilesFile",
        BlinkCmpLabelDescription = "Comment",
        BlinkCmpLabelDetail = "Comment",
        BlinkCmpLabelMatch = "DiagnosticInfo",
        BlinkCmpMenu = "MiniFilesNormal",
        BlinkCmpMenuBorder = "MiniFilesBorder",
        BlinkCmpMenuSelection = "MiniFilesCursorLine",
        BlinkCmpScrollBarGutter = "MiniFilesNormal",
        BlinkCmpScrollBarThumb = "MiniFilesBorder",
        BlinkCmpSearchIcon = "DiagnosticInfo",
        BlinkCmpSignatureHelp = "MiniFilesNormal",
        BlinkCmpSignatureHelpBorder = "MiniFilesBorder",
        BlinkCmpSource = "Comment",
        BlinkCmpSourceIcon = "MiniFilesDirectory",
    }

    for group, link in pairs(links) do
        vim.api.nvim_set_hl(0, group, { link = link })
    end
end

return {
    {
        "saghen/blink.cmp",
        event = "InsertEnter",
        version = "1.*",
        dependencies = {
            {
                "zbirenbaum/copilot.lua",
                cmd = "Copilot",
                -- One language server per Neovim instance: completion state is
                -- per-client, so lspmux multiplexing causes cross-session
                -- errors (`Document for URI could not be found`).
                opts = {
                    panel = { enabled = false },
                    suggestion = { enabled = false },
                },
                config = function(_, opts)
                    require("copilot").setup(opts)
                    require("config.copilot").on_setup()
                end,
            },
            {
                "fang2hou/blink-copilot",
            },
            {
                "L3MON4D3/LuaSnip",
                version = "2.*",
                config = function()
                    require("luasnip.loaders.from_vscode").lazy_load()
                    require("luasnip.loaders.from_vscode").lazy_load({
                        paths = { vim.fn.stdpath("config") .. "/snippets" },
                    })
                end,
            },
            "rafamadriz/friendly-snippets",
            {
                "folke/lazydev.nvim",
                ft = "lua",
                opts = {},
            },
        },
        opts = {
            enabled = function()
                return vim.g.user_completion_enabled ~= false
            end,
            keymap = {
                preset = "default",
                ["<C-space>"] = false,
                -- Emacs insert-mode bindings own these keys and call the
                -- completion API themselves (config.insert_emacs). Signature
                -- help and documentation scrolling move to Meta keys.
                ["<C-b>"] = false,
                ["<C-e>"] = false,
                ["<C-f>"] = false,
                ["<C-k>"] = false,
                ["<C-n>"] = false,
                ["<C-p>"] = false,
                ["<C-y>"] = false,
                ["<M-k>"] = { "show_signature", "hide_signature" },
                ["<M-n>"] = { "scroll_documentation_down", "fallback" },
                ["<M-p>"] = { "scroll_documentation_up", "fallback" },
                -- Terminals encode Ctrl-/ as the Ctrl-_ byte.
                ["<C-/>"] = { "show", "fallback" },
                ["<C-_>"] = { "show", "fallback" },
                ["<CR>"] = { "accept", "fallback" },
                ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
                ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
            },
            appearance = {
                nerd_font_variant = "mono",
            },
            completion = {
                list = {
                    selection = {
                        preselect = true,
                        auto_insert = false,
                    },
                },
                menu = {
                    border = "single",
                    max_height = 8,
                    min_width = 26,
                    scrollbar = true,
                    draw = {
                        columns = {
                            { "source_icon" },
                            { "kind_icon" },
                            { "label", "label_description", gap = 1 },
                            { "source_name" },
                        },
                        components = {
                            kind_icon = {
                                ellipsis = false,
                                text = function(ctx)
                                    local icon = get_mini_icon(ctx)
                                    return icon .. ctx.icon_gap
                                end,
                                highlight = function(ctx)
                                    local _, hl = get_mini_icon(ctx)
                                    return hl
                                end,
                            },
                            label = {
                                width = { fill = true, max = 42 },
                            },
                            label_description = {
                                width = { max = 18 },
                            },
                            source_icon = {
                                ellipsis = false,
                                text = source_icon,
                                highlight = source_highlight,
                            },
                            source_name = {
                                width = { max = 8 },
                                text = function(ctx)
                                    return source_names[ctx.source_id] or ctx.source_name
                                end,
                                highlight = "BlinkCmpSource",
                            },
                        },
                    },
                },
                documentation = {
                    auto_show = true,
                    window = {
                        border = "single",
                        max_height = 14,
                        max_width = 72,
                    },
                },
                ghost_text = {
                    enabled = true,
                },
            },
            cmdline = { enabled = false },
            sources = {
                default = function()
                    if vim.bo.filetype == "minifiles" or vim.bo.filetype == "minifiles-help" then
                        return { "buffer" }
                    end

                    return { "lsp", "path", "snippets", "buffer", "lazydev", "copilot" }
                end,
                providers = {
                    buffer = {
                        name = "Buf",
                        max_items = 24,
                    },
                    cmdline = {
                        name = "Cmd",
                        max_items = 24,
                    },
                    copilot = {
                        name = "Copilot",
                        module = "blink-copilot",
                        async = true,
                        score_offset = 100,
                    },
                    lazydev = {
                        module = "lazydev.integrations.blink",
                        name = "Lua",
                        score_offset = 100,
                    },
                    lsp = {
                        name = "LSP",
                        override = {
                            get_trigger_characters = function(self)
                                local trigger_characters = self:get_trigger_characters()
                                if vim.bo.filetype == "odin" then
                                    table.insert(trigger_characters, "{")
                                end
                                return trigger_characters
                            end,
                        },
                    },
                    path = {
                        name = "Path",
                    },
                    snippets = {
                        name = "Snip",
                    },
                },
            },
            snippets = {
                preset = "luasnip",
            },
            fuzzy = {
                implementation = "prefer_rust_with_warning",
            },
            signature = {
                enabled = true,
                trigger = {
                    show_on_insert = true,
                },
                window = {
                    border = "single",
                    max_height = 8,
                    max_width = 72,
                },
            },
        },
        config = function(_, opts)
            setup_blink_highlights()
            vim.api.nvim_create_autocmd("ColorScheme", {
                group = vim.api.nvim_create_augroup("UserBlinkHighlights", { clear = true }),
                callback = setup_blink_highlights,
            })
            require("blink.cmp").setup(opts)
        end,
    },
}
