local function lua_workspace_library()
    local library = {}
    local data_path = vim.fn.stdpath("data")
    local love_candidates = {
        vim.fs.joinpath(data_path, "lazy", "love2d.nvim", "libraries", "love2d", "library"),
        vim.fs.joinpath(data_path, "mason", "packages", "lua-language-server", "meta", "3rd", "love2d", "library"),
    }

    for _, path in ipairs(love_candidates) do
        local stat = vim.uv.fs_stat(path)
        if stat and stat.type == "directory" then
            table.insert(library, path)
            break
        end
    end

    return library
end

local servers = {
    ols = {},
    clangd = {},
    zls = {
        settings = {
            zls = {
                enable_snippets = true,
                enable_argument_placeholders = true,
                semantic_tokens = "partial",
                inlay_hints_show_variable_type_hints = true,
                inlay_hints_show_struct_literal_field_type = true,
                inlay_hints_show_parameter_name = true,
                build_on_save_args = { "-fincremental" },
            },
        },
    },
    lua_ls = {
        settings = {
            Lua = {
                completion = {
                    callSnippet = "Replace",
                },
                diagnostics = {
                    globals = { "vim", "love" },
                },
                workspace = {
                    library = lua_workspace_library(),
                    checkThirdParty = false,
                },
            },
        },
    },
}

-- Language server processes live in `lspmux.service` (systemd --user) instead
-- of one process per nvim instance. All instances in the same workspace share
-- a single server; lspmux spawns it on demand and kills it when idle.
local lspmux = require("config.lspmux")
local lspmux_bin = {
    lua_ls = "lua-language-server",
}

local function lspmux_setup(name, config)
    config.cmd = lspmux.connect
    config.init_options = vim.tbl_deep_extend("force", {
        lspMux = lspmux.options(vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", lspmux_bin[name] or name)),
    }, config.init_options or {})
end

local function on_lsp_attach(event)
    if require("config.bigfile").is_large(event.buf) then
        -- Only detach this buffer. Stopping the client would also break LSP in
        -- every other buffer served by the same process.
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(event.buf) then
                vim.lsp.buf_detach_client(event.buf, event.data.client_id)
            end
        end)
        return
    end

    local map = function(keys, rhs, desc, mode)
        vim.keymap.set(mode or "n", keys, rhs, { buffer = event.buf, desc = desc })
    end

    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gr", vim.lsp.buf.references, "References")
    map("gI", vim.lsp.buf.implementation, "Implementation")
    map("gt", vim.lsp.buf.type_definition, "Type definition")
    map("K", vim.lsp.buf.hover, "Hover")
    map("<leader>la", vim.lsp.buf.code_action, "Code action", { "n", "x" })
    map("<leader>lr", vim.lsp.buf.rename, "Rename")
    -- map("<leader>ld", function()
    --     vim.diagnostic.open_float({ scope = "line" })
    -- end, "Line diagnostic")
    map("<leader>lq", vim.diagnostic.setloclist, "Diagnostic list")

    -- local client = vim.lsp.get_client_by_id(event.data.client_id)
    -- if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
    --     map("<leader>lh", function()
    --         vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }), { bufnr = event.buf })
    --     end, "Toggle inlay hints")
    -- end
end

return {
    {
        "mason-org/mason.nvim",
        opts = {},
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = { "mason-org/mason.nvim" },
        opts = {
            ensure_installed = { "zls", "ols", "lua_ls", "clangd" },
            automatic_enable = false,
        },
    },
    {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        dependencies = { "mason-org/mason.nvim" },
        opts = {
            ensure_installed = { "stylua", "debugpy", "delve", "js-debug-adapter" },
        },
    },
    {
        "neovim/nvim-lspconfig",
        lazy = false,
        dependencies = {
            "saghen/blink.cmp",
            "mason-org/mason-lspconfig.nvim",
        },
        config = function()
            vim.diagnostic.config({
                severity_sort = true,
                underline = true,
                update_in_insert = false,
                virtual_text = {
                    severity = vim.diagnostic.severity.ERROR,
                    spacing = 2,
                    prefix = "",
                },
                float = {
                    border = "single",
                    source = true,
                },
                signs = {
                    text = {
                        [vim.diagnostic.severity.ERROR] = "",
                        [vim.diagnostic.severity.WARN] = "",
                        [vim.diagnostic.severity.INFO] = "",
                        [vim.diagnostic.severity.HINT] = "",
                    },
                },
            })

            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
                callback = on_lsp_attach,
            })

            local capabilities = require("blink.cmp").get_lsp_capabilities()
            for name, config in pairs(servers) do
                lspmux_setup(name, config)
                config.capabilities = vim.tbl_deep_extend("force", {}, capabilities, config.capabilities or {})
                vim.lsp.config(name, config)
            end

            vim.lsp.enable(vim.tbl_keys(servers))
        end,
    },
}
