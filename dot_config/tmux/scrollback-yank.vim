" Nur fuers tmux-Scrollback-Popup (Prefix+[, tmux.conf.tmpl) gesourct --
" kein Teil der normalen LazyVim-Config. tmux-yank (nur copy-mode) und
" Neovims unnamedplus (kein $DISPLAY/SSH_TTY in diesem Kontext) greifen
" hier beide nicht -- deshalb Yank manuell durch osc52-copy pipen, das
" schon fuer tmux-fingers den SSH-Client-Fan-out (Kitty x230, Termius
" iPhone) macht (siehe ~/.local/bin/osc52-copy).
autocmd TextYankPost <buffer> if v:event.operator ==# 'y'
      \ | call system('~/.local/bin/osc52-copy', join(v:event.regcontents, "\n"))
      \ | endif
