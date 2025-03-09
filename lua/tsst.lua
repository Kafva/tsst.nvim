local M = {}

-- Test modules should be imported from '.'
vim.o.runtimepath = vim.o.runtimepath .. ',.'

local ANSI_RED = string.char(27) .. '[91m'
local ANSI_RED_BG = string.char(27) .. '[101m'
local ANSI_GREEN = string.char(27) .. '[32m'
local ANSI_ITALICS = string.char(27) .. '[3m'
local ANSI_RESET = string.char(27) .. '[0m'

---@param msg string|nil
local function failed_message(msg)
    local info = debug.getinfo(3, 'Sl')
    local src = info.source
    local lnum = info.currentline
    return '\nAssertion failed: '
        .. src
        .. ':'
        .. lnum
        .. ': '
        .. (msg or '')
        .. '\n'
end

---@param filepath string
---@return string
local function readfile(filepath)
    local content
    local fd, err
    fd, err = vim.uv.fs_open(filepath, 'r', 438)

    if not fd then
        error(err or ('Failed to open ' .. filepath))
    end

    content, err = vim.uv.fs_read(fd, 8192)

    if not content then
        error(err or ('Failed to read ' .. filepath))
    end

    _, err = vim.uv.fs_close(fd)
    if err then
        error(err)
    end

    return content
end

---@param toprint string
---@param tocompare string
---@return string
local function string_color_diff(toprint, tocompare)
    local msg = ''
    local len = math.max(#tocompare, #toprint)
    for i = 1, len do
        if i > #toprint then
            goto continue
        end

        local char = toprint:sub(i, i)
        if i <= #tocompare and char ~= tocompare:sub(i, i) then
            if char == ' ' then
                msg = msg .. ANSI_RED_BG .. char .. ANSI_RESET
            else
                msg = msg .. ANSI_RED .. char .. ANSI_RESET
            end
        else
            msg = msg .. char
        end
        ::continue::
    end

    return msg
end

---@param expected any
---@param actual any
---@return string
local function getdiff(expected, actual)
    local expected_s = tostring(expected)
    local actual_s = tostring(actual)
    return "Expected:  " .. string_color_diff(expected_s, actual_s) .. "\n" ..
           "Actual:    " .. string_color_diff(actual_s, expected_s) .. "\n"
end

---@return integer?
function M.run_test(testfile)
    local modpath = testfile:gsub('/', '.'):gsub('.lua$', '')
    local ok, testmod = pcall(require, modpath)
    if not ok then
        io.write('Error loading test module: ' .. tostring(testmod) .. '\n')
        io.flush()
        return nil
    end
    local modname = modpath:gsub("tests.", '')
    io.write(string.format(ANSI_ITALICS .. ">>> %s" .. ANSI_RESET .. "\n", modname))

    for _, tc in pairs(testmod.testcases) do
        testmod.before_each()
        local testcase_ok, errmsg = pcall(tc.fn)
        local status = testcase_ok and (ANSI_GREEN .. ' OK ' .. ANSI_RESET)
            or (ANSI_RED .. 'FAIL' .. ANSI_RESET)
        io.write(string.format("[ %s ] %s\n", status, tc.desc))
        io.flush()

        if not testcase_ok then
            io.write(errmsg .. '\n')
            io.flush()
            return nil
        end
    end

    return #testmod.testcases
end

vim.api.nvim_create_user_command('RunTests', function(opts)
    local targets = vim.split(opts.fargs[1], ' ')
    local passed_count = 0
    local module_count = nil
    for _, target in pairs(targets) do
        module_count = M.run_test(target)
        if module_count == nil then
            break
        else
            passed_count = passed_count + module_count
        end
    end

    if module_count ~= nil then
        io.write(string.format("All %d tests passed\n", passed_count))
        io.flush()
    end

    vim.cmd [[silent qa!]]
end, { nargs = 1 })

-- Test utilities --------------------------------------------------------------

function M.rm_f(filepath)
    local _, err, errno = vim.uv.fs_unlink(filepath)
    if errno ~= nil and errno ~= 'ENOENT' then
        error(err)
    end
end

---@param expected any
---@param actual any
function M.assert_eql(expected, actual)
    if expected == actual then
        return
    end
    local msg = failed_message()
    msg = msg .. getdiff(expected, actual)
    error(msg)
end

---@param expected any[]
---@param actual any[]
function M.assert_eql_tables(expected, actual)
    for i,_ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg .. string.format('Difference at index %d\n', i)
            msg = msg .. getdiff(expected[i], actual[i])
            error(msg)
        end
    end
end

---@param expected_file string
---@param actual string[]
function M.assert_eql_file(expected_file, actual)
    local expected = vim.split(readfile(expected_file), '\n', {trimempty = true})
    for i,_ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg .. string.format('Difference at %s:%d\n', expected_file, i)
            msg = msg .. getdiff(expected[i], actual[i])
            error(msg)
        end
    end
end

return M
