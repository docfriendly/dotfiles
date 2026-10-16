-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- In tmux den tmux-Buffer als Clipboard-Ziel nutzen (statt xclip, das nvim
-- wegen $DISPLAY sonst bevorzugt): Yank landet im obersten tmux-Buffer, den
-- der Mittelklick in anderen Panes einfuegt; `set-clipboard on` reicht ihn
-- zusaetzlich als CLIPBOARD an Kitty durch. Ausserhalb von tmux bleibt xclip.
-- Eigener Provider statt "tmux": der eingebaute ruft beim Lesen
-- `tmux refresh-client -l` auf, was Kitty zur Rueckfrage "program wants to read
-- from the system clipboard" veranlasst. `save-buffer` liest nur den tmux-Buffer.
if vim.env.TMUX then
  local copy = { "tmux", "load-buffer", "-w", "-" }
  local paste = { "tmux", "save-buffer", "-" }
  vim.g.clipboard = {
    name = "tmux-ohne-refresh",
    copy = { ["+"] = copy, ["*"] = copy },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
