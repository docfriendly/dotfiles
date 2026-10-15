-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Zeilenanfang/-ende wie in der Shell (Readline/Emacs)
-- Insert: Home/End; Normal/Visual/Operator-pending: ^ und $
-- Achtung: <C-a> ist damit nicht mehr "Zahl hochzählen" (siehe unten)
vim.keymap.set("i", "<C-a>", "<Home>", { desc = "Zeilenanfang" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "Zeilenende" })
vim.keymap.set({ "n", "x", "o" }, "<C-a>", "^", { desc = "Erstes Zeichen der Zeile" })
vim.keymap.set({ "n", "x", "o" }, "<C-e>", "$", { desc = "Zeilenende" })

-- Zahlen hoch-/runterzählen: <C-a> ist jetzt Zeilenanfang, deshalb <C-y> (+1).
-- <C-x> (-1) bleibt Vim-Standard; auf QWERTZ liegen Y und X nebeneinander.
-- Überlegungen zu den Nachbartasten:
--   <C-y>  Normal: Zeile zurückscrollen (Partner von <C-e>, entfällt ohnehin; <C-d>/<C-u> bleiben)
--          -> frei. Insert bewusst unberührt: blink.cmp nutzt <C-y> zum Übernehmen.
--   <C-s>  LazyVim: Datei speichern -> nicht belegen (und Terminal-Flow-Control XOFF).
--   <C-c>  bricht Operatoren ab / verlässt Insert wie Esc -> Sicherheitsnetz, nicht belegen.
-- Kein Rekursions-Problem: vim.keymap.set ist standardmäßig non-recursive,
-- "<C-a>" meint hier also das eingebaute Hochzählen, nicht das ^-Mapping oben.
vim.keymap.set({ "n", "x" }, "<C-y>", "<C-a>", { desc = "Zahl +1" })
vim.keymap.set({ "n", "x" }, "g<C-y>", "g<C-a>", { desc = "Zahlen fortlaufend +1" })
