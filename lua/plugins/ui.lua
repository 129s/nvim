local function setup_noice_highlights()
    local links = {
        NoiceCmdline = "MiniFilesNormal",
        NoiceCmdlineHint = "Comment",
        NoiceCmdlineIcon = "MiniFilesDirectory",
        NoiceCmdlineIconSearch = "DiagnosticInfo",
        NoiceCmdlinePrompt = "MiniFilesDirectory",
        NoiceCompletionItemKindDefault = "MiniFilesDirectory",
        NoiceCompletionItemMenu = "Comment",
        NoiceCompletionItemWord = "MiniFilesFile",
        NoicePopupmenu = "MiniFilesNormal",
        NoicePopupmenuBorder = "MiniFilesBorder",
        NoicePopupmenuMatch = "DiagnosticInfo",
        NoicePopupmenuSelected = "MiniFilesCursorLine",
        NoiceScrollbar = "MiniFilesNormal",
        NoiceScrollbarThumb = "MiniFilesBorder",
    }

    for group, link in pairs(links) do
        vim.api.nvim_set_hl(0, group, { link = link })
    end
end

local cmdline_hint_ns = vim.api.nvim_create_namespace("UserNoiceCmdlineHint")

local function get_cmdline_hint()
    if vim.fn.mode() ~= "c" then
        return nil
    end

    local cmdtype = vim.fn.getcmdtype()
    local completion_type = cmdtype == ":" and "cmdline" or ((cmdtype == "/" or cmdtype == "?") and "buffer" or nil)
    if completion_type == nil then
        return nil
    end

    local line = vim.fn.getcmdline()
    if line == "" then
        return nil
    end

    local before_cursor = line:sub(1, math.max(vim.fn.getcmdpos() - 1, 0))
    if before_cursor == "" then
        return nil
    end

    local ok, items = pcall(vim.fn.getcompletion, before_cursor, completion_type)
    if not ok or type(items) ~= "table" or #items == 0 then
        return nil
    end

    local base = before_cursor:match("(%S*)$") or before_cursor
    for _, item in ipairs(items) do
        if item == before_cursor or item == base or item == line then
            return nil
        end
    end

    for _, item in ipairs(items) do
        if item ~= before_cursor and item ~= base and item ~= line then
            local hint = item
            if vim.startswith(item, before_cursor) then
                hint = item:sub(#before_cursor + 1)
            elseif base ~= "" and vim.startswith(item, base) then
                hint = item:sub(#base + 1)
            end

            if hint ~= "" then
                return hint:sub(1, 80)
            end
        end
    end
end

local function setup_noice_cmdline_hint()
    local cmdline = require("noice.ui.cmdline")
    if cmdline._user_hint_patch then
        return
    end

    local original_on_render = cmdline.on_render
    cmdline.on_render = function(text, buf, line, ...)
        original_on_render(text, buf, line, ...)

        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end

        vim.api.nvim_buf_clear_namespace(buf, cmdline_hint_ns, 0, -1)

        local hint = get_cmdline_hint()
        if hint == nil then
            return
        end

        local ok, rendered = pcall(vim.api.nvim_buf_get_lines, buf, line - 1, line, false)
        if not ok or rendered[1] == nil then
            return
        end

        pcall(vim.api.nvim_buf_set_extmark, buf, cmdline_hint_ns, line - 1, #rendered[1], {
            virt_text = { { hint, "NoiceCmdlineHint" } },
            virt_text_pos = "inline",
            hl_mode = "combine",
            priority = 250,
        })
    end

    cmdline._user_hint_patch = true
end

local function setup_cmdline_tab_cycle()
    local original

    local function keycode(keys)
        return vim.api.nvim_replace_termcodes(keys, true, false, true)
    end

    local function skip_original(direction)
        vim.schedule(function()
            if vim.fn.mode() ~= "c" or vim.fn.wildmenumode() ~= 1 or original == nil then
                return
            end

            if vim.fn.getcmdline() == original then
                vim.api.nvim_feedkeys(keycode(direction), "n", false)
            end
        end)
    end

    vim.keymap.set("c", "<Tab>", function()
        if vim.fn.wildmenumode() == 1 then
            original = original or vim.fn.getcmdline()
            skip_original("<C-n>")
            return "<C-n>"
        end

        original = nil
        return "<Tab>"
    end, { expr = true, replace_keycodes = true, desc = "Next completion" })

    vim.keymap.set("c", "<S-Tab>", function()
        if vim.fn.wildmenumode() == 1 then
            original = original or vim.fn.getcmdline()
            skip_original("<C-p>")
            return "<C-p>"
        end

        original = nil
        return "<S-Tab>"
    end, { expr = true, replace_keycodes = true, desc = "Previous completion" })

    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = vim.api.nvim_create_augroup("UserCmdlineCompletion", { clear = true }),
        callback = function()
            original = nil
        end,
    })
end

local function dropbar_scratch_source()
    return {
        get_symbols = function(buf, win)
            local bar = require("dropbar.bar")
            local filetype = vim.bo[buf].filetype
            local name = filetype ~= "" and ("Scratch:" .. filetype) or "Scratch"

            return {
                bar.dropbar_symbol_t:new({
                    buf = buf,
                    win = win,
                    icon = "󰈔 ",
                    name = name,
                    icon_hl = "DropBarIconKindFile",
                    name_hl = "DropBarKindFile",
                    on_click = false,
                }),
            }
        end,
    }
end

local dropbar_base_winbar = "%{%v:lua.dropbar()%}"
local dropbar_comment_winbar = dropbar_base_winbar .. "%=%#DropBarIconKindDefault#%{v:lua.DropbarCommentVisibility()}%*"

_G.DropbarCommentVisibility = function()
    local hide = package.loaded["hide-comment"]
    return hide ~= nil and hide.is_enabled() and "󰈉 " or "󰈈 "
end

local function update_dropbar_comment_status(win)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end

    local is_terminal = vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
    if is_terminal then
        if vim.wo[win].winbar == dropbar_comment_winbar then
            vim.wo[win].winbar = dropbar_base_winbar
        end
    elseif vim.wo[win].winbar == dropbar_base_winbar then
        vim.wo[win].winbar = dropbar_comment_winbar
    end
end

local function terminal_path_source()
    return {
        get_symbols = function(buf, win)
            local bar = require("dropbar.bar")
            local path = vim.api.nvim_buf_get_name(buf):match("^term://(.-)//") or vim.fn.getcwd()
            path = vim.fn.fnamemodify(vim.fs.normalize(path), ":~")

            return {
                bar.dropbar_symbol_t:new({
                    buf = buf,
                    win = win,
                    icon = require("dropbar.configs").opts.icons.kinds.symbols.Folder,
                    name = path,
                    icon_hl = "DropBarIconKindFolder",
                    name_hl = "DropBarKindDir",
                    on_click = false,
                }),
            }
        end,
    }
end

local function terminal_name(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    local command = name:match("^term://.-//%d+:(.*)$") or vim.o.shell
    local executable = command:match("^%S+") or command
    return vim.fn.fnamemodify(executable, ":t")
end

local function add_dropbar_comment_status(win)
    update_dropbar_comment_status(win)
end

local function setup_dropbar()
    require("dropbar").setup({
        sources = {
            terminal = {
                name = terminal_name,
            },
        },
        icons = {
            ui = {
                bar = {
                    separator = " > ",
                },
            },
        },
        bar = {
            attach_events = {
                "TermOpen",
                "BufEnter",
                "BufWinEnter",
                "BufWritePost",
                "FileType",
                "LspAttach",
            },
            enable = function(buf, win)
                buf = vim._resolve_bufnr(buf)
                if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
                    return false
                end

                local filetype = vim.bo[buf].filetype
                if
                    vim.fn.win_gettype(win) ~= ""
                    or vim.wo[win].winbar ~= ""
                    or filetype == "help"
                    or filetype == "minifiles"
                    or filetype == "minifiles-help"
                    or vim.bo[buf].buftype == "prompt"
                    or vim.bo[buf].buftype == "quickfix"
                then
                    return false
                end

                return not require("config.bigfile").is_large(buf)
            end,
            sources = function(buf)
                local sources = require("dropbar.sources")
                local utils = require("dropbar.utils")
                local filetype = vim.bo[buf].filetype
                local buftype = vim.bo[buf].buftype
                local name = vim.api.nvim_buf_get_name(buf)

                if name == "" then
                    return { dropbar_scratch_source() }
                end

                if filetype == "markdown" then
                    return {
                        sources.path,
                        sources.markdown,
                    }
                end

                if buftype == "terminal" then
                    return {
                        sources.terminal,
                        terminal_path_source(),
                    }
                end

                return {
                    sources.path,
                    utils.source.fallback({
                        sources.lsp,
                        sources.treesitter,
                    }),
                }
            end,
        },
    })

    local group = vim.api.nvim_create_augroup("DropbarCommentStatus", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "LspAttach", "TermOpen" }, {
        group = group,
        callback = function()
            vim.schedule(function()
                add_dropbar_comment_status(vim.api.nvim_get_current_win())
            end)
        end,
    })
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        add_dropbar_comment_status(win)
    end
end

return {
    {
        "mcauley-penney/visual-whitespace.nvim",
        event = "ModeChanged *:[vV\22]",
        opts = {},
    },
    { "sitiom/nvim-numbertoggle" },
    {
        "hedyhli/outline.nvim",
        lazy = true,
        cmd = { "Outline", "OutlineOpen" },
        keys = { -- Example mapping to toggle outline
            { "<leader>to", "<cmd>Outline<CR>", desc = "Toggle outline" },
        },
        opts = {
            -- Your setup opts here
        },
    },
    {
        "Bekaboo/dropbar.nvim",
        enabled = false,
        dependencies = {
            "nvim-telescope/telescope-fzf-native.nvim",
            build = "make",
        },
        config = function()
            setup_dropbar()
            local dropbar_api = require("dropbar.api")
            vim.keymap.set("n", "<Leader>;", dropbar_api.pick, { desc = "Pick symbols in winbar" })
            vim.keymap.set("n", "g;", dropbar_api.goto_context_start, { desc = "Go to start of current context" })
            vim.keymap.set("n", "<c-;>", dropbar_api.select_next_context, { desc = "Select next context" })
        end,
    },

    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        -- enabled = false,
        opts = {
            options = {
                theme = "catppuccin-mocha",
                globalstatus = true,
                component_separators = { left = "|", right = "|" },
                section_separators = { left = "", right = "" },
            },
        },
    },
    {
        "folke/noice.nvim",
        event = "VeryLazy",
        dependencies = {
            "MunifTanjim/nui.nvim",
        },
        init = function()
            vim.opt.wildmenu = true
            vim.opt.wildmode = "noselect,full"
            vim.opt.wildoptions = "pum,fuzzy"
        end,
        opts = {
            cmdline = {
                enabled = true,
                view = "cmdline",
                format = {
                    input = { view = "cmdline", icon = "󰥻 " },
                },
            },
            popupmenu = {
                enabled = true,
                backend = "nui",
            },
            commands = {
                history = {
                    view = "popup",
                },
                all = {
                    view = "popup",
                },
            },
            lsp = {
                -- progress = { enabled = false },
                -- hover = { enabled = false },
                -- signature = { enabled = false },
                -- message = { enabled = false },
                override = {
                    ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
                    ["vim.lsp.util.stylize_markdown"] = true,
                    ["cmp.entry.get_documentation"] = false,
                },
                view = "notify",
            },
            -- presets = {
            --     bottom_search = false,
            --     command_palette = false,
            --     long_message_to_split = false,
            --     inc_rename = false,
            --     lsp_doc_border = false,
            --     cmdline_output_to_split = false,
            -- },
            views = {
                cmdline = {
                    zindex = 320,
                    focusable = false,
                    enter = false,
                    position = {
                        row = -1,
                        col = 0,
                    },
                    size = {
                        width = "100%",
                        height = 1,
                    },
                    border = {
                        style = "none",
                    },
                    win_options = {
                        winhighlight = {
                            Normal = "NoiceCmdline",
                            IncSearch = "",
                            CurSearch = "",
                            Search = "",
                        },
                    },
                },
                cmdline_input = {
                    view = "cmdline",
                },
                cmdline_popupmenu = {
                    relative = "editor",
                    zindex = 330,
                    scrollbar = false,
                    position = {
                        row = -3,
                        col = 0,
                    },
                    size = {
                        width = "auto",
                        height = "auto",
                        min_width = 24,
                        max_width = 80,
                        max_height = 8,
                    },
                    border = {
                        style = "single",
                        padding = { 0, 1 },
                    },
                    win_options = {
                        winhighlight = {
                            Normal = "NoicePopupmenu",
                            FloatBorder = "NoicePopupmenuBorder",
                            CursorLine = "NoicePopupmenuSelected",
                            PmenuMatch = "NoicePopupmenuMatch",
                        },
                    },
                },
                popup = {
                    border = {
                        style = "single",
                        padding = { 0, 1 },
                    },
                    win_options = {
                        winhighlight = {
                            Normal = "NoicePopupmenu",
                            FloatBorder = "NoicePopupmenuBorder",
                            CursorLine = "NoicePopupmenuSelected",
                            PmenuMatch = "NoicePopupmenuMatch",
                        },
                    },
                },
                popupmenu = {
                    zindex = 330,
                    scrollbar = false,
                    size = {
                        width = "auto",
                        height = "auto",
                        min_width = 24,
                        max_width = 80,
                        max_height = 8,
                    },
                    border = {
                        style = "single",
                        padding = { 0, 1 },
                    },
                    win_options = {
                        winhighlight = {
                            Normal = "NoicePopupmenu",
                            FloatBorder = "NoicePopupmenuBorder",
                            CursorLine = "NoicePopupmenuSelected",
                            PmenuMatch = "NoicePopupmenuMatch",
                        },
                    },
                },
            },
        },
        config = function(_, opts)
            require("noice").setup(opts)
            setup_noice_highlights()
            setup_noice_cmdline_hint()
            setup_cmdline_tab_cycle()

            vim.api.nvim_create_autocmd("ColorScheme", {
                group = vim.api.nvim_create_augroup("UserNoiceHighlights", { clear = true }),
                callback = setup_noice_highlights,
            })
            vim.keymap.set("n", "<leader>tn", function()
                require("noice").cmd("all")
            end)
        end,
    },
    {
        "folke/snacks.nvim",
        lazy = false,
        priority = 900,
        opts = {
            bigfile = {
                enabled = true,
                size = require("config.bigfile").size,
                line_length = require("config.bigfile").line_length,
                setup = function(ctx)
                    require("config.bigfile").apply(ctx.buf)
                end,
            },
            indent = {
                enabled = true,
                animate = { enabled = false },
                -- Avoid parsing the Treesitter scope for every h/l in Visual mode.
                scope = {
                    cursor = false,
                    treesitter = { enabled = false },
                },
            },
            notifier = {
                enabled = true,
                style = function(buf, notif, ctx)
                    ctx.opts.border = "none"
                    local whl = ctx.opts.wo.winhighlight
                    ctx.opts.wo.winhighlight = whl:gsub(ctx.hl.icon, "SnacksNotifierMinimal")

                    local icon = notif.icon .. " "
                    local icon_width = vim.api.nvim_strwidth(icon)

                    local lines = vim.split(notif.msg, "\n")
                    for i, line in ipairs(lines) do
                        lines[i] = string.rep(" ", icon_width) .. line
                    end
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

                    vim.api.nvim_buf_set_extmark(buf, ctx.ns, 0, 0, {
                        virt_text = { { icon, ctx.hl.icon } },
                        virt_text_pos = "overlay",
                        priority = 10,
                    })
                end,
                timeout = 6000,
                margin = { right = 0 },
                icons = {
                    error = "",
                    warn = "",
                    info = "",
                    debug = "",
                    trace = "",
                },
            },
            picker = { enabled = true, focus = "list", show_delay = 0 },
            quickfile = { enabled = true },
            words = { enabled = true },
        },
        keys = {
            -- {
            --     "<leader>ff",
            --     function()
            --         Snacks.picker.files()
            --     end,
            --     desc = "Files",
            -- },
            {
                "<leader>ff",
                function()
                    Snacks.picker.smart()
                end,
                desc = "Smart",
            },
            {
                "<leader>fg",
                function()
                    Snacks.picker.grep()
                end,
                desc = "Grep",
            },
            {
                "<leader>fb",
                function()
                    Snacks.picker.buffers()
                end,
                desc = "Buffers",
            },
            {
                "<leader>fh",
                function()
                    Snacks.picker.help()
                end,
                desc = "Help",
            },
            {
                "<leader>fd",
                function()
                    Snacks.picker.diagnostics()
                end,
                desc = "Diagnostics",
            },
            {
                "<leader>fr",
                function()
                    Snacks.picker.resume()
                end,
                desc = "Resume picker",
            },
        },
    },
}
