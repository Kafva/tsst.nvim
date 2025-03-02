# tsst.nvim
Basic framework for nvim plugin tests.

Projects that use tsst should define test modules under `./tests/` and have a
copy of tsst.nvim in the same directory, e.g.
```
tests
├── foo_test.lua
├── bar_test.lua
└── tsst.nvim
```

The basic structure of a test module looks like this:
```lua
M = {}

local tsst = require 'tsst'

M.before_each = function()
    -- ...
end

M.testcases = {}

table.insert(M.testcases, {
    desc = 'Run a test',
    fn = function()
        -- ...
    end,
})
```

To run the tests:
```bash
tests/tsst.nvim/tsst
```

See [brk.nvim](https://github.com/Kafva/brk.nvim) for more in depth examples.
