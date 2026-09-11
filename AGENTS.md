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
    ├── tree.kak         # Interactive multi-root collapsible file tree
    ├── git.kak          # Git status recognition, highlighters, and action menu popup
    └── highlighters.kak # Syntax regex highlighting ($ prefix, commands, comments)
```

---

## 2. Core Concepts & Workflow

1. **Prefix lines (`$ `):**
   Lines beginning with `$ ` (configurable via `kiki_prefix`) represent runnable shell commands (e.g. `$ ag -l 'term'`, `$ git status`, `$ sudo systemctl restart nginx`).
2. **Topic files (`*.kiki`):**
   Topic notes are kept in `kiki_topics` (defaults to `~/.config/kak/kiki/` or user's custom directory like `~/dex/Vocab/Kiki/`).
3. **Execution Modes:**
   - **Inline (`i`):** Executes command and inserts pre-selected output directly below the command line (automatically rendering ANSI colors via `ansi-render-selection` on output lines if available).
   - **Scratch (`s`):** Executes command into a disposable, dedicated `*kiki-scratch*` buffer with modeline tag `[kiki:scratch]` (automatically colorizes output via `ansi-render` if available).
   - **FIFO (`f`):** Asynchronously streams output into a timestamped buffer `*kiki-fifo-<cmd>-<time>*` via named pipe (`mkfifo`) (automatically colorizes output via `ansi-render` on stream completion if available).
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
  1. Resolves path/location from explicit arguments, active selection, `kiki-path-select` regex, or current line.
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
- **kiki-cd-do Fallback:** Changes directory to the path under cursor/prompt. On normal non-directory lines, automatically falls back to changing directory to the current buffer's parent directory (`dirname "$kak_buffile"`), or does nothing if the buffer is unsaved.

### E. Interactive Multi-Root File Tree (`rc/tree.kak`)
- **Fluid & Editable:** Tree buffer `*kiki-file-tree*` is a fully editable scratch buffer with `[kiki:tree]` tag.
- **Root & Subdirectory Collapsing:** Root directories (`- /path/`) and nested folders (`  + subdir/`) can be collapsed (`+ `) and re-expanded (`- `) with `<ret>` (or `<c-o>`).
- **Git Action Popup in Tree:** Pressing `,g` (aliases: `` ` ``, `<a-g>`) on any file or directory in the file tree opens the Git action popup (`tree-git` on directories, or file status popup on files).
- **Directory Trap:** A `RuntimeError` hook intercepts Kakoune's native `:edit <dir>` (*"is a directory"*) error and immediately launches `kiki-file-tree` on that directory.
- **Step-Into & Move-to-Parent:** Pressing `<tab>` promotes any subfolder into the tree's root header (`- /subfolder/path/`) and loads its contents. Pressing `<c-l>` moves the tree up to its parent folder (`- /parent/path/`).
- **Keybindings in Kiki Buffers:**
  - `<ret>` / `<enter>`: Execute command via FIFO (`kiki-fifo`), open file tree on directories, open file on files, trigger Git action popup on git status lines, toggle expand/collapse in file tree, or open topic.
  - `<tab>`: Execute command inline (`kiki-inline`), rotate next modified file in file tree (triggering action popup), open file tree on directories / step into folder, rotate next Git status file (triggering action popup), open file on files, or open topic.
  - `<s-tab>`: Rotate previous modified file in file tree (triggering action popup), step back in file tree (`kiki-tree-parent`), or rotate previous Git status file (triggering action popup).
  - `O`: Smart contextual open (topic in topic list, file tree if path, FIFO if command, fallback native `O`).
  - `p`: Open or replace buffer view in connected Kakoune preview client (`preview`).
  - `P`: Change directory to folder path or parent of file path.
  - `<c-o>`: Toggle directory expand/collapse or open file.
  - `<c-l>`: Move up to parent folder.
  - `*`: Recursively expand directory tree.
  - `-`: Narrow unselected subtrees/siblings.
  - `r`: Refresh directory node or Git status block in-place.
  - `.`: Toggle hidden dotfiles.
  - `<a-c>`: Insert `kiki_prefix` into current line (if empty) or next available empty line below, and enter insert mode.
  - `<a-C>`: Insert `kiki_prefix` into current line (if empty) or previous available empty line above, and enter insert mode.
  - `,g` / `` ` `` / `<a-g>`: Open Git action popup for any file or directory under cursor.
  - `D`: Execute command in terminal shell, or drop to shell in directory/path under cursor.
  - `q`: Close/delete Kiki buffer.

### F. Git Status Recognition & Action Menu (`rc/git.kak`)
- **Status Highlighting:** Highlights git status lines automatically (staged: green, modified: yellow, untracked: magenta, deleted: red).
- **Interactive Action Menu (`kiki-git`):** Pressing `<ret>` on any git status entry opens an action popup without editing the file directly.
- **Repo Detection Priority:** In `kiki-buffer` (`*.kiki`, `*kiki-*`) git repo is resolved from `$PWD` first (falls back to `dirname "$kak_buffile"`); in non-kiki buffers `dirname "$kak_buffile"` is tried first (falls back to `$PWD`).
- **Popup Consistency:** `g` shows `kiki-git-status` in every git popup; `<tab>`/`<s-tab>` rotates next/prev file in every popup including `git`/`tree-git`/`commit`.

---

## 4. Complete Command & Mapping Reference

### User Mode: `kiki` (Prefix Key: `,` or configured leader)

| Key | Command | Description |
| :--- | :--- | :--- |
| `c` | — | Insert `kiki_prefix` (`$ `) at cursor position |
| `C` | — | Prefix current line with `kiki_prefix` (`I$ `) |
| `<a-c>` | `kiki-smart-new-command` | Insert `kiki_prefix` into current or next empty line |
| `<a-C>` | `kiki-smart-new-command-above` | Insert `kiki_prefix` into current or previous empty line |
| `y` | `kiki-select` | Select and yank command text after prefix |
| `i` | `kiki-inline` | Execute command and insert pre-selected output below |
| `s` | `kiki-scratch` | Execute command into `*kiki-scratch*` buffer |
| `f` | `kiki-fifo` | Asynchronously stream command output to FIFO buffer |
| `b` | `kiki-background`| Execute command detached in background with PID |
| `!` | `kiki-shell` | Run command in interactive terminal shell in `$PWD` |
| `g` | `kiki-smart-git-popup` | Open git action popup on file/directory (aliases: `` ` ``, `<a-g>`) |
| `` ` `` | `kiki-smart-git-popup` | Open git action popup on file/directory (alias for `g`) |
| `u` | `kiki-open-url` | Open URL from line or buffer in web browser |
| `l` | `kiki-ls` | Run `ls -alh` on path under cursor/selection |
| `e` | `kiki-edit` | Open file at path (supports `file:line:col` and topic files) |
| `o` | `kiki-file-tree` | Open interactive collapsible file tree |
| `p` | `kiki-preview` | Open or replace buffer in connected preview client |
| `t` | `kiki-topic` | Open topic file by name (`<topic>.kiki`) |
| `T` | `kiki-list-topics` | List available topic files in a scratch buffer |
| `P` | `kiki-cd` | Change directory to path, or buffer parent on normal lines |
| `D` | `kiki-drop-to-shell` | Suspend Kakoune and drop to shell in selected directory |
| `q` | `kiki-scratchpad` | Open disposable quick scratchpad (`*kiki-scratchpad-<timestamp>*`) |
| `,` | — | Open quick scratchpad (`scratchpad.kiki`) |
| `d` | — | Enter `delete` buffer cleanup menu |

### User Mode: `modified` (Modified / Conflict File Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `s` | `kiki-git-stage` | Stage file (`git add`) |
| `a` | `kiki-git-stage` | Stage file (`git add`) |
| `X` | `kiki-git-restore` | Restore file changes with confirmation (`git restore`) |
| `S` | `kiki-git-stage-all` | Stage all changes (`git add -A`) |
| `c` | — | Enter `commit` commit popup menu |
| `v` | `kiki-git-diff` | View diff for file in interactive terminal shell |
| `d` | `kiki-git-diff-all` | View all unstaged diffs in interactive terminal shell |
| `D` | `kiki-git-diff-all-cached` | View all staged diffs in interactive terminal shell |
| `l` | `kiki-git-log` | View git log in interactive terminal shell |
| `r` | `kiki-git-refresh` | Refresh Git status output in-place |
| `p` | `kiki-git-preview` | Preview file in connected preview client |
| `e` | `kiki-git-edit` | Open file directly in Kakoune |
| `q` | `kiki-smart-close` | Quit buffer |

### User Mode: `staged` (Staged File Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `u` | `kiki-git-unstage` | Unstage file (`git restore --staged`) |
| `X` | `kiki-git-restore-staged` | Restore & unstage file with confirmation |
| `U` | `kiki-git-unstage-all` | Unstage all changes (`git restore --staged .`) |
| `c` | — | Enter `commit` commit popup menu |
| `v` | `kiki-git-diff-cached` | View cached diff for file in interactive terminal shell |
| `d` | `kiki-git-diff-all` | View all unstaged diffs in interactive terminal shell |
| `D` | `kiki-git-diff-all-cached` | View all staged diffs in interactive terminal shell |
| `l` | `kiki-git-log` | View git log in interactive terminal shell |
| `r` | `kiki-git-refresh` | Refresh Git status output in-place |
| `p` | `kiki-git-preview` | Preview file in connected preview client |
| `e` | `kiki-git-edit` | Open file directly in Kakoune |
| `q` | `kiki-smart-close` | Quit buffer |

### User Mode: `untracked` (Untracked File Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `a` | `kiki-git-add` | Add file (`git add`) |
| `s` | `kiki-git-stage` | Stage file (`git add`) |
| `X` | `kiki-git-clean` | Clean/remove untracked file with confirmation (`git clean`) |
| `S` | `kiki-git-stage-all` | Stage all changes (`git add -A`) |
| `c` | — | Enter `commit` commit popup menu |
| `v` | `kiki-git-diff` | View diff for file in interactive terminal shell |
| `d` | `kiki-git-diff-all` | View all unstaged diffs in interactive terminal shell |
| `D` | `kiki-git-diff-all-cached` | View all staged diffs in interactive terminal shell |
| `l` | `kiki-git-log` | View git log in interactive terminal shell |
| `r` | `kiki-git-refresh` | Refresh Git status output in-place |
| `p` | `kiki-git-preview` | Preview file in connected preview client |
| `e` | `kiki-git-edit` | Open file directly in Kakoune |
| `q` | `kiki-smart-close` | Quit buffer |

### User Mode: `tree-git` (File Tree Git Repo Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `s` | `kiki-git-status` | Show git status in streaming FIFO buffer (alias) |
| `c` | — | Enter `commit` commit popup menu |
| `l` | `kiki-git-log` | View git log in interactive terminal shell |
| `d` | `kiki-git-diff-all` | View unstaged diff in interactive terminal shell |
| `q` | — | Close popup menu |

### User Mode: `git` (Limited/Common Git Actions Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `s` | `kiki-git-status` | Show git status in streaming FIFO buffer (alias) |
| `c` | — | Enter `commit` commit popup menu |
| `l` | `kiki-git-log` | View git log in interactive terminal shell |
| `d` | `kiki-git-diff-all` | View diff in interactive terminal shell |
| `r` | `kiki-git-refresh` | Refresh Git status output in-place |
| `q` | `kiki-smart-close` | Quit buffer |

### User Mode: `commit` (Git Commit Popup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `<tab>` | `kiki-git-rotate-file 1` | Rotate to next file (popup stays open) |
| `<s-tab>` | `kiki-git-rotate-file -1` | Rotate to previous file (popup stays open) |
| `g` | `kiki-git-status` | Show git status in streaming FIFO buffer |
| `c` | `kiki-git-commit` | Commit staged changes (`git commit`) |
| `a` | `kiki-git-commit-all` | Commit all tracked changes (`git commit -a`) |
| `A` | `kiki-git-commit-amend` | Amend commit (`git commit --amend`) |
| `N` | `kiki-git-commit-amend-no-edit` | Amend commit without editing message (`git commit --amend --no-edit`) |
| `q` | — | Close popup menu |

### User Mode: `delete` (Buffer Cleanup)

| Key | Command | Description |
| :--- | :--- | :--- |
| `a` | `kiki-close-all-buffers` | Close all Kiki-managed buffers |
| `f` | `kiki-close-fifo-buffers` | Close all `*kiki-fifo-*` buffers |
| `t` | `kiki-close-topics-buffers` | Close all `*kiki-topics-*` buffers |
| `r` | `kiki-close-tree-buffers` | Close all `*kiki-file-tree*` buffers |
| `s` | `kiki-close-scratchpad-buffers` | Close all `*kiki-scratchpad-*` buffers |
| `p` | `kiki-close-preview-buffers` | Close all `*kiki-preview*` buffers |
| `k` | `kiki-close-file-buffers` | Close all open `.kiki` file buffers |

---

## 5. Options Reference

```kak
declare-option str kiki_prefix "$ "                      # Command prefix string
declare-option str kiki_topics "~/.config/kak/kiki/"     # Topic files directory
declare-option str kiki_buffer_type ""                   # Buffer category, set to kiki-buffer for all kiki buffers
declare-option bool kiki_tree_show_hidden false          # Show/hide dotfiles in file tree
declare-option str kiki_shell ""                         # Custom shell for drop-to-shell (auto-detects zsh/fish/bash)
```

---

## 6. Guidelines for Extending Kiki

When modifying or adding features:
1. **Always use `-override`:** All commands must use `define-command -override`.
2. **Never pollute registers:** Use `%sh{}` temporary files or `execute-keys -draft` rather than overwriting `"`, `.`, or system clipboards.
3. **Use the dispatchers:** Route new execution commands through `kiki-cmd-dispatch` and path commands through `kiki-path-dispatch`.
4. **Preserve modular boundaries:** Keep command execution in `rc/execution.kak`, navigation in `rc/navigation.kak`, and shared utilities in `rc/core.kak`.
5. **Keep shell quoting safe:** Use `printf '%s\n'` and avoid nesting unescaped `%sh{}` blocks inside `printf` strings.
