# Kiki — Codebase & Architecture Guide for LLMs

> **Quick Overview for LLMs:**
> Kiki is a command-runner, topic-note organizer, and filesystem navigation plugin for the [Kakoune](https://kakoune.org) text editor.
> It allows users to write shell commands prefixed with `$ ` inside plain text or topic notes (`*.kiki`), and execute, pipe, or navigate them seamlessly using dedicated Kakoune user modes.

---

## 1. Directory & File Structure

```
bundle/kiki/
├── kiki.kak             # Main entrypoint: options, user modes, autoloader, shortcut mappings
├── LLMS.md              # Machine-readable architectural guide and codebase reference
├── README.md            # Human documentation
└── rc/
    ├── core.kak         # Core dispatchers, sudo authentication, modelines, selectors
    ├── execution.kak    # Execution engines (inline, scratch, fifo, background, shell)
    ├── navigation.kak   # Filesystem & topic navigation (edit, ls, cd, topic, list-topics)
    ├── buffers.kak      # Buffer management, filetype hooks, cleanup commands
    └── highlighters.kak # Syntax regex highlighting ($ prefix, commands, comments)
```

---

## 2. Core Concepts & Workflow

1. **Prefix lines (`$ `):**
   Lines beginning with `$ ` (configurable via `kiki_prefix`) represent runnable shell commands (e.g. `$ ag -l 'term'`, `$ git status`, `$ sudo systemctl restart nginx`).
2. **Topic files (`*.kiki`):**
   Topic notes are kept in `kiki_topics` (defaults to `~/.config/kak/kiki/` or user's custom directory like `~/dex/Vocab/Kiki/`).
3. **Execution Modes:**
   - **Inline (`i`):** Executes command and inserts pre-selected output directly below the command line.
   - **Scratch (`s`):** Executes command into a disposable, dedicated `*kiki-scratch*` buffer with modeline tag `[kiki:scratch]`.
   - **FIFO (`f`):** Asynchronously streams output into a timestamped buffer `*kiki-fifo-<cmd>-<time>*` via named pipe (`mkfifo`).
   - **Background (`b`):** Fires command asynchronously in detached subshell (`&`) and reports the PID.
   - **Shell (`!`):** Spawns an interactive terminal running the command in Kakoune's current `$PWD`, pausing on exit.

---

## 3. Architecture & Technical Mechanics

### A. Unified Dispatchers (`rc/core.kak`)
Instead of duplicating argument/selection parsing across commands, Kiki uses two centralized dispatchers:

- **`kiki-cmd-dispatch <action-do> [<args>]`**:
  1. Checks if explicit CLI arguments were passed (`$# -ge 1`).
  2. If not, checks for an active multi-character selection (`$kak_selection`).
  3. If not, falls back to `kiki-select` (stripping `$ ` on the current line) or `<esc>x`.
  4. Routes through `kiki-check-sudo` before calling the `-do` action.

- **`kiki-path-dispatch <action-do> [<args>]`**:
  1. Resolves path/URL from explicit arguments, active selection, `kiki-uri-select` regex, or current line.
  2. Passes cleaned path to navigation helpers (`kiki-edit-do`, `kiki-ls-do`, `kiki-cd-do`, `kiki-topic-do`).

### B. Standard Input (`stdin`) Decoupling
- Raw Kakoune `!` key acts as a text filter that feeds buffer selections into `stdin`. This breaks tools that check `stdin` (e.g. `ag`, `rg`, `grep`, `jq`, `python`, `fzf`).
- Kiki commands **always decouple `stdin`** by executing `( eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null`.

### C. OS-Level `sudo` Authentication & Caching
- **Detection:** `kiki-check-sudo` checks if the command contains `sudo`.
- **Non-interactive Ticket Check:** Runs `sudo -n true`. If cached, runs instantly with zero prompts.
- **Password Prompt:** If not cached, opens Kakoune's masked prompt:
  ```kak
  prompt -password "Password:" %{ kiki-sudo-auth-and-run %{action} %{cmd} }
  ```
- **Validation:** `kiki-sudo-auth-and-run` calls `printf '%s\n' "$kak_text" | sudo -S -v -p ""`. This updates the OS-level `/run/sudo/ts/` ticket, surviving Kakoune restarts.

### D. Path & Location Resolution (`rc/navigation.kak`)
`kiki-edit-do` parses complex compiler/grep strings:
- Formats: `file:line`, `file:line:col`, `file:line:match_text` (e.g. `MacApps:52:Stapler.app`, `src/main.rs:12:4:let x = 1;`).
- Resolves relative paths, absolute paths, and tilde `~`.
- **Topic Fallback:** If the file does not exist in CWD, automatically checks `$kak_opt_kiki_topics/<name>.kiki`.

### E. Interactive Multi-Root File Tree (`rc/tree.kak`)
- **Fluid & Editable:** Tree buffer `*kiki-file-tree*` is a fully editable scratch buffer with `[kiki:tree]` tag.
- **Root & Subdirectory Collapsing:** Root directories (`- /path/`) and nested folders (`  + subdir/`) can be collapsed (`+ `) and re-expanded (`- `) with `<ret>` or `<c-o>`.
- **Step-Into & Move-to-Parent:** Pressing `<tab>` promotes any subfolder into the tree's root header (`- /subfolder/path/`) and loads its contents. Pressing `<c-l>` moves the tree up to its parent folder (`- /parent/path/`).
- **Arbitrary Path Exploration:** Users can type or paste any path (e.g. `~/.config/kak/` or `/var/log/`) on a new line and press `<ret>` to expand it alongside existing trees.
- **Keybindings:** `<ret>` / `<c-o>` (toggle/open), `<tab>` (step-into folder / open file), `<c-l>` (move to parent folder), `*` (recursively expand tree), `-` (narrow unselected subtrees/siblings), `r` (refresh node in-place), `.` (toggle hidden dotfiles), `q` (delete buffer).

---

## 4. Complete Command & Mapping Reference

### User Mode: `kiki` (Prefix Key: `,` or configured leader)

| Key | Command | Description |
| :--- | :--- | :--- |
| `c` | — | Insert `kiki_prefix` (`$ `) at cursor position |
| `C` | — | Prefix current line with `kiki_prefix` (`I$ `) |
| `<a-c>` | — | Create a new command line below and enter insert mode |
| `y` | `kiki-select` | Select and yank command text after prefix |
| `i` | `kiki-inline` | Execute command and insert pre-selected output below |
| `s` | `kiki-scratch` | Execute command into `*kiki-scratch*` buffer |
| `f` | `kiki-fifo` | Asynchronously stream command output to FIFO buffer |
| `b` | `kiki-background`| Execute command detached in background with PID |
| `!` | `kiki-shell` | Run command in interactive terminal shell in `$PWD` |
| `Y` | `kiki-uri-select`| Select and yank URI / path on line |
| `l` | `kiki-ls` | Run `ls -alh` on path under cursor/selection |
| `e` | `kiki-edit` | Open file at path (supports `file:line:col` and topic files) |
| `o` | `kiki-file-tree` | Open interactive collapsible file tree |
| `t` | `kiki-topic` | Open topic file by name (`<topic>.kiki`) |
| `T` | `kiki-list-topics` | List available topic files in a scratch buffer |
| `p` | `kiki-cd` | Change Kakoune working directory to path |
| `,` | — | Open quick scratchpad (`scratchpad.kiki`) |
| `d` | — | Enter `kiki-delete` buffer cleanup menu |

### User Mode: `kiki-delete` (Buffer Cleanup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `a` | `kiki-close-all-buffers` | Close all Kiki-managed buffers |
| `f` | `kiki-close-fifo-buffers` | Close all `*kiki-fifo-*` buffers |
| `t` | `kiki-close-topics-buffers` | Close all `*kiki-topics-*` buffers |
| `r` | `kiki-close-tree-buffers` | Close all `*kiki-file-tree*` buffers |
| `k` | `kiki-close-file-buffers` | Close all open `.kiki` file buffers |

---

## 5. Options Reference

```kak
declare-option str kiki_prefix "$ "                      # Command prefix string
declare-option str kiki_topics "~/.config/kak/kiki/"     # Topic files directory
declare-option str kiki_buffer_type ""                   # Buffer category (file|fifo|scratch|topics|tree)
declare-option bool kiki_tree_show_hidden false          # Show/hide dotfiles in file tree
```

---

## 6. Guidelines for Extending Kiki

When modifying or adding features:
1. **Always use `-override`:** All commands must use `define-command -override`.
2. **Never pollute registers:** Use `%sh{}` temporary files or `execute-keys -draft` rather than overwriting `"`, `.`, or system clipboards.
3. **Use the dispatchers:** Route new execution commands through `kiki-cmd-dispatch` and path commands through `kiki-path-dispatch`.
4. **Preserve modular boundaries:** Keep command execution in `rc/execution.kak`, navigation in `rc/navigation.kak`, and shared utilities in `rc/core.kak`.
5. **Keep shell quoting safe:** Use `printf '%s\n'` and avoid nesting unescaped `%sh{}` blocks inside `printf` strings.
