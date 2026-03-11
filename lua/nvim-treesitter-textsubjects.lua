local parsers = {
    get_buf_lang = function(bufnr)
        local ft = vim.bo[bufnr or 0].filetype
        if not ft or ft == '' then
            return nil
        end
        return vim.treesitter.language.get_lang(ft)
    end,
    has_parser = function(lang)
        if not lang then
            return false
        end
        -- Check if the language parser is available
        local ok = pcall(vim.treesitter.language.add, lang)
        return ok
    end
}

local M = {}

-- Register the make-range! directive for modern Neovim
-- This directive combines range of two captures into metadata.range
-- Usage: (#make-range! "range" @_start @_end)
local function register_make_range_directive()
    pcall(vim.treesitter.query.add_directive, 'make-range!', function(match, _, _, predicate, metadata)
        -- predicate[1] = "make-range!"
        -- predicate[2] = "range" (the key name)
        -- predicate[3] = capture id for start node
        -- predicate[4] = capture id for end node
        local start_id = predicate[3]
        local end_id = predicate[4]

        -- In modern Neovim, match[id] is a list of nodes, not a single node
        local start_nodes = match[start_id]
        local end_nodes = match[end_id]

        local start_node = start_nodes and start_nodes[1]
        local end_node = end_nodes and end_nodes[#end_nodes]

        if start_node and end_node then
            local start_row, start_col = start_node:range()
            local _, _, end_row, end_col = end_node:range()
            metadata.range = { start_row, start_col, end_row, end_col }
        end
    end, { force = true, all = true })
end

function M.configure(config_overrides)
    require('textsubjects.config').set(config_overrides)
end

function M.is_supported(lang)
    local seen = {}
    local function has_nested_textsubjects_language(nested_lang)
        if not nested_lang then
            return false
        end

        if not parsers.has_parser(nested_lang) then
            return false
        end

        if vim.treesitter.query.get(nested_lang, 'textsubjects-smart')
            or vim.treesitter.query.get(nested_lang, 'textsubjects-container-outer')
            or vim.treesitter.query.get(nested_lang, 'textsubjects-container-inner') then
            return true
        end
        if seen[nested_lang] then
            return false
        end
        seen[nested_lang] = true

        local query = vim.treesitter.query.get(nested_lang, 'injections')
        if query then
            -- Modern query object has captures as an array, not query.info.captures
            for _, capture in ipairs(query.captures or {}) do
                if capture == 'language' or has_nested_textsubjects_language(capture) then
                    return true
                end
            end

            -- For query.info.patterns, we need to check if this still exists in modern API
            -- This may need to be updated based on actual modern API structure
            if query.info and query.info.patterns then
                for _, info in ipairs(query.info.patterns) do
                    -- we're looking for #set injection.language <whatever>
                    if info[1] and info[1][1] == "set!" and info[1][2] == "injection.language" then
                        if has_nested_textsubjects_language(info[1][3]) then
                            return true
                        end
                    end
                end
            end
        end

        return false
    end

    return has_nested_textsubjects_language(lang)
end

function M.init()
    -- Register custom directive before setting up autocmds
    register_make_range_directive()

    if vim.fn.has('nvim-0.9') == 1 then
        vim.api.nvim_create_autocmd({ 'FileType' }, {
            callback = function(details)
                require('nvim-treesitter.textsubjects').detach(details.buf)

                local lang = vim.treesitter.language.get_lang(details.match)
                if not M.is_supported(lang) then
                    return
                end

                require('nvim-treesitter.textsubjects').attach(details.buf)
            end,
        })
        vim.api.nvim_create_autocmd({ 'BufUnload' }, {
            callback = function(details)
                require('nvim-treesitter.textsubjects').detach(details.buf)
            end,
        })
    else
        require "nvim-treesitter".define_modules {
            textsubjects = {
                module_path = "nvim-treesitter.textsubjects",
                enable = false,
                disable = {},
                prev_selection = nil,
                keymaps = {},
                is_supported = M.is_supported,
            }
        }
    end
end

return M
