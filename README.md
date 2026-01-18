# foldchanged.nvim

Adds a `FoldChanged` User event.

## Installation

With `lazy.nvim`:

```lua
{
  "netmute/foldchanged.nvim"
}
```

## Usage

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "FoldChanged",
  callback = function(ev)
    -- ev.data = { win = <winid>, buf = <bufnr> }
  end,
})
```

