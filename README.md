# vim

Personal Vim configuration written in pure Vim9script, using Vim's native package system with no plugin manager. Vim only — Neovim is not supported.

## Requirements

- Vim 9.1+ (9.2+ recommended for `autocomplete`, `hlyank`, and other newer features)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`grep` uses `rg --vimgrep`)
- `catppuccin` colorscheme
- Per-language LSP servers (optional, see below)

## Install

```bash
git clone https://github.com/latteyt/vim.git ~/.config/vim
```

## Layout

```
~/.config/vim/
├── vimrc                   # entry point, sources init.vim
├── init.vim                # main configuration
└── pack/lattetao/opt/      # native packages (loaded on demand via packadd!)
    ├── autopair/           # automatic bracket pairing
    ├── dirvish/            # directory browser (replaces netrw)
    ├── fim/                # fill-in-the-middle completion (requires API key)
    ├── fzf/                # fuzzy file finder
    ├── llm/                # opencode integration (requires API key)
    └── lsp/                # self-written async LSP client
```

## Plugins

| Plugin | Origin | Description |
|--------|--------|-------------|
| comment | Vim builtin | comment operations |
| hlyank | Vim builtin | highlight yank |
| editorconfig | Vim builtin | editor configuration |
| termdebug / matchit | Vim builtin | debugging / matching jumps |
| dirvish | this repo | directory browsing, `-` toggles file ↔ parent dir |
| autopair | this repo | automatic bracket pairing |
| fzf | this repo | `:Fd` fuzzy file search |
| lsp | this repo | async diagnostics + completion + jump/format |
| llm | this repo | send text to opencode (requires `DEEPSEEK_API_KEY`) |
| fim | this repo | FIM completion (requires `DEEPSEEK_API_KEY`) |
| osc52 | Vim builtin | remote clipboard over SSH |

`llm` / `fim` are loaded only when the `DEEPSEEK_API_KEY` environment variable is set; `osc52` only when `SSH_TTY` is set.

## LSP

A self-written async LSP client communicating with language servers over Vim channels, supporting async diagnostics and code completion.

Default languages and servers (`g:lsp_config` can override):

| Language | Server |
|----------|--------|
| Go | `gopls` |
| C / C++ | `clangd` |
| Python | `basedpyright-langserver` |
| TypeScript | `tsc --lsp` |
| Lua | `lua-language-server` |
| Rust | `rust-analyzer` |

Commands:

- `:LSPGotoDefinition` / `:LSPGotoTypeDefinition` / `:LSPGotoImplementation`
- `:LSPFormat`

## llm (opencode integration)

Interact with AI through a local opencode server (default `http://localhost:4096`):

- `:LLMCopy` — copy selected lines (with file path + line numbers) to the system clipboard
- `:LLMSend` — send selected lines to opencode and submit
- `:LLMAsk {question}` — send selected lines along with a question

## fim (Fill-in-the-Middle)

DeepSeek-based FIM completion in insert mode:

- `<C-g><C-g>` — trigger suggestion
- `<Tab>` — accept next word
- `<C-j>` — accept all
- `<C-l>` — accept line

## Key mappings

General `[x` / `]x` style navigation (supports `v:count`):

| Mapping | Action |
|---------|--------|
| `[a` / `]a` | previous / next argument |
| `[b` / `]b` | previous / next buffer |
| `[l` / `]l` | previous / next location item |
| `[q` / `]q` | previous / next quickfix item |
| `[t` / `]t` | previous / next tag |
| `[<Space>` / `]<Space>` | insert blank line above / below |

Others:

- `-` (normal mode) — toggle file and parent directory (dirvish)
- `<leader>y` / `<leader>s` (visual mode, `<leader>` is `\`) — LLMCopy / LLMSend
- `date`` / `email`` (iabbrev) — insert current time / email
