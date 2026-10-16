-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Yank -> zusaetzlich X-PRIMARY (Mittelklick), nur ausserhalb von tmux.
--
-- Hintergrund: LazyVim setzt clipboard=unnamedplus, d.h. `y` landet nur im Register
-- `+` (X-CLIPBOARD, Strg-Shift-V), nicht in `*` (X-PRIMARY, Mittelklick). In tmux
-- faellt das nicht auf, weil dort der eigene Provider (options.lua) `*` und `+` auf
-- denselben tmux-Buffer legt. Ausserhalb von tmux nimmt nvim xclip, und dort sind
-- `*` und `+` getrennt. Dieser Hook spiegelt Yanks nach `*`, damit sich `y` dort
-- wie in tmux verhaelt.
--
-- Bewusst NUR operator == "y": `clipboard=unnamed,unnamedplus` wuerde auch d/x/c nach
-- PRIMARY schreiben und die Mausmarkierung bei jedem Loeschen ueberschreiben.
-- regname == "" oder "+": benannte Register (`"ay`) loesen nichts aus.
-- setreg() feuert TextYankPost nicht erneut, keine Schleife.
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Yank auch nach PRIMARY (*) spiegeln, ausserhalb von tmux",
  callback = function()
    local e = vim.v.event
    if e.operator == "y" and not vim.env.TMUX and (e.regname == "" or e.regname == "+") then
      vim.fn.setreg("*", e.regcontents, e.regtype)
    end
  end,
})
