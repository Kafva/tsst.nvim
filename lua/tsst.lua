local M = {}

---@class TsstModule
---@field testcases TsstCase[]
---@field before_each function

---@class TsstCase
---@field desc string
---@field fn function

-- Test modules should be imported from '.'
vim.o.runtimepath = vim.o.runtimepath .. ',.'

local ANSI_GREY = string.char(27) .. '[90m'
local ANSI_RED = string.char(27) .. '[91m'
local ANSI_RED_BG = string.char(27) .. '[101m'
local ANSI_GREEN = string.char(27) .. '[32m'
local ANSI_YELLOW = string.char(27) .. '[93m'
local ANSI_ITALICS = string.char(27) .. '[3m'
local ANSI_RESET = string.char(27) .. '[0m'

-- Note: A testcase will be successful as long as no failed assertions occur,
-- it is not obligatory to return a TsstResult.
---@enum TsstResult
local TsstResult = {
    OK = 'ok',
    SKIP = 'skip',
    FAIL = 'fail',
}

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
            elseif char == '\t' then
                msg = msg .. ANSI_RED_BG .. '~' .. ANSI_RESET
            else
                msg = msg .. ANSI_RED .. char .. ANSI_RESET
            end
        else
            if char == ' ' then
                msg = msg .. ANSI_GREY .. '.' .. ANSI_RESET
            elseif char == '\t' then
                msg = msg .. ANSI_GREY .. '~' .. ANSI_RESET
            else
                msg = msg .. char
            end
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
    return 'Expected:  '
        .. string_color_diff(expected_s, actual_s)
        .. '\n'
        .. 'Actual:    '
        .. string_color_diff(actual_s, expected_s)
        .. '\n'
end

-- Returns the total and skipped number of testcases, nil if at least one
-- case failed.
---@return integer?, integer?
function M.run_test(testfile)
    local modpath = testfile:gsub('/', '.'):gsub('.lua$', '')
    local ok, testmod = pcall(require, modpath)
    if not ok then
        io.write('Error loading test module: ' .. tostring(testmod) .. '\n')
        io.flush()
        return nil
    end
    local modname = modpath:gsub('tests.', '')
    io.write(
        string.format(ANSI_ITALICS .. '>>> %s' .. ANSI_RESET .. '\n', modname)
    )

    local skipped_cases = 0
    for _, tc in pairs(testmod.testcases) do
        testmod.before_each()
        local testcase_ok, r = pcall(tc.fn)
        local status
        if r == TsstResult.SKIP then
            status = ANSI_YELLOW .. 'SKIP' .. ANSI_RESET
            skipped_cases = skipped_cases + 1
        elseif testcase_ok then
            status = ANSI_GREEN .. ' OK ' .. ANSI_RESET
        else
            status = ANSI_RED .. 'FAIL' .. ANSI_RESET
        end

        io.write(string.format('[ %s ] %s\n', status, tc.desc))
        io.flush()

        if not testcase_ok then
            io.write(r .. '\n')
            io.flush()
            return nil
        end
    end

    return #testmod.testcases, skipped_cases
end

vim.api.nvim_create_user_command('RunTests', function(opts)
    local targets = vim.split(opts.fargs[1], ' ')
    local total_test_cases = 0
    local passed_test_cases = 0
    local module_total, module_skipped
    for _, target in pairs(targets) do
        module_total, module_skipped = M.run_test(target)
        if module_total == nil then
            break
        end
        total_test_cases = total_test_cases + module_total
        passed_test_cases = passed_test_cases + module_total - module_skipped
    end

    if module_total ~= nil then
        if total_test_cases == passed_test_cases then
            io.write(string.format('Passed %d tests\n', passed_test_cases))
        else
            io.write(
                string.format(
                    'Passed %d tests (skipped=%d)\n',
                    passed_test_cases,
                    total_test_cases - passed_test_cases
                )
            )
        end
        io.flush()
    end

    vim.cmd [[silent qa!]]
end, { nargs = 1 })

-- Test utilities --------------------------------------------------------------

-- Skip the current test
function M.skip()
    return TsstResult.SKIP
end

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
    for i, _ in ipairs(expected) do
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
    local expected =
        vim.split(readfile(expected_file), '\n', { trimempty = true })
    for i, _ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg
                .. string.format('Difference at %s:%d\n', expected_file, i)
            msg = msg .. getdiff(expected[i], actual[i])
            error(msg)
        end
    end
end

return M
