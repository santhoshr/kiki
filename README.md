# Kiki - Leave kakoune, less often.

Kiki is a plugin for [Kakoune](https://github.com/mawww/kakoune) that provides
advanced interactions with your native shell without leaving the comfort of
your editor. It was designed to lessen the number of times you need to switch
between your text editor and your terminal, as well as provide a simple workflow
for getting things done.

**Kiki provides the following functionality:**
 - **Execution of shell commands** from within the editor. Output can be piped:
   - Inline directly below the command (`<i>` or `<tab>`), with selective ANSI color rendering (`ansi-render-selection` if available).
   - In a dedicated scratch buffer (`<s>`), colorized via `ansi-render` if available.
   - In a streaming asynchronous FIFO buffer (`<f>` or `<ret>`), colorized via `ansi-render` if available.
   - In a background job reporting the PID (`<b>`).
   - In an interactive terminal shell (`<!>` or `<D>`).
 - **Documentation that is executable:**
   - Write shell commands and notes side-by-side in any file or topic note (`*.kiki`).
 - **Smart Contextual Keybindings in Kiki Buffers:**
   - `<ret>`: Stream output via FIFO on commands, open files/folders, toggle tree nodes, or open topics.
   - `<tab>`: Execute inline on commands, open files, step into folders in the file tree, or open topics.
   - `O`: Smart contextual open (topics in topic list, file tree on paths, FIFO on commands).
   - `P`: Change Kakoune's working directory to folder path or parent of file path.
   - `D`: Run command in terminal shell or drop to shell in target directory.
   - `<a-c>`: Insert prefix on current or next empty line (downward) in both **normal and insert modes**.
   - `<a-C>`: Insert prefix on current or previous empty line (upward) in both **normal and insert modes**.
   - `q`: Close/delete current Kiki buffer.
 - **Interactive Multi-Root File Tree (`kiki-file-tree` / `<o>`):**
   - Collapsible and expandable directory tree navigation (`+ ` and `- `).
   - Step into subfolder as tree root (`<tab>`) and move up to parent folder (`<c-l>`).
   - Recursively expand subtrees (`*`) and narrow sibling subtrees (`-`).
   - In-place node refresh (`r`) and toggle hidden dotfiles (`.`).
 - **Filesystem & URL Navigation:**
   - Open URLs directly in default browser from line, selection, or buffer (`<u>` / `:open-url`).
   - Auto-detects paths, URLs, and compiler error locations (`file:line:col`).
   - `ls -alh` inline descriptor on path (`<l>`).
   - `:edit` file at path with automatic topic fallback (`<e>`).
   - Change directory (`<p>`).
 - **Persistent Topic Notes & Scratchpads:**
   - Create and organize modular topic files in `~/.config/kak/kiki/` (`<t>` and `<T>`).
   - Persistent scratchpad (`<,>`) and disposable timestamped scratchpads (`<q>`).
 - **Native OS Sudo Caching:**
   - Transparently validates and caches `sudo` authentication with masked password prompt.
 - **Intelligent Interactive Shell Auto-Detection:**
   - Automatically drops into `zsh`, `fish`, `bash`, or your configured shell (`kiki_shell`).
 - **Dedicated Buffer Management Menu (`<d>`):**
   - Quick cleanup commands to close all Kiki buffers, FIFO streams, trees, or scratchpads.

---

## Installing the plugin:

### Using [plug.kak](https://github.com/andreyorst/plug.kak)
```kak
plug "santhoshr/kiki" config %{
    # Optional configuration:
    set-option global kiki_prefix "$ "
    set-option global kiki_topics "~/.config/kak/kiki/"
    set-option global kiki_shell "" # Auto-detects zsh/fish/bash
}
```

### Manual / Autoload
Link or clone the repository to Kakoune's autoload or bundle directory:
```bash
git clone https://github.com/santhoshr/kiki.git ~/.config/kak/bundle/kiki
```

And source it in your `kakrc`:
```kak
source "%val{config}/bundle/kiki/kiki.kak"
```

### Setting up your user mode mapping:
I suggest binding the `kiki` user mode to an easy leader key like `,` (comma) or `\`:
```kak
map global normal ',' ':enter-user-mode<space>kiki<ret>' -docstring 'kiki'
```

For the following interactive examples, when a key like `<i>` or `<f>` is referenced, it assumes you first enter the `kiki` user mode (e.g. `,i` or `,f`), or press the key directly inside any Kiki buffer!

That's all it takes! Once you are done installing kiki, let's do some interactive
examples right here within the `README.md` file you are currently reading. Open this
file in Kakoune and let's get started!

---

## Executing a command:

To execute a command, Kiki looks for a configurable prefix string on the current line. This
string is the Kakoune option `kiki_prefix` (default: `$ `). The prefix and command will be syntax
highlighted across your buffers.

Everything after the `kiki_prefix` is treated as the shell command you wish to run. All execution
commands cleanly decouple `stdin` (`< /dev/null`) so your editor never freezes waiting on input.

```bash
# Notes or text before the prefix on the same line are ignored:
Build check: $ cargo check
```

### 1. Executing inline (`<i>` or `<tab>`)

Executing commands inline provides the following benefits:
 - Documentation on commands you run can be saved directly in your notes.
 - Output of commands can be captured, searched, and manipulated in place.
 - Output is automatically selected upon insertion for easy formatting.

To run a command inline, place your cursor on the line below and press `<i>` (or `<tab>` in Kiki buffers):

```bash
$ echo $PATH

$ ls -alh

$ uname -a
```

### 2. Executing in a scratch buffer (`<s>`)

Executing commands in a scratch buffer allows the following:
 - Large command outputs don't clutter your working file.
 - Output is captured into a disposable `*kiki-scratch*` buffer with modeline tag `[kiki:scratch]`.
 - Output can be modified and saved to a new file whenever needed.

To run in a scratch buffer, place your cursor on the line below and press `<s>`:

```bash
$ man grep
```

### 3. Executing in a FIFO buffer (`<f>` or `<ret>`)

Using a FIFO buffer gives you unique asynchronous streaming benefits:
 - Command output streams live into a timestamped buffer `*kiki-fifo-<cmd>-<time>*`.
 - The buffer updates incrementally as soon as stdout/stderr receives data, without waiting for the process to finish.
 - Long-running build commands, tests, or monitors can stream smoothly in the background.

Try streaming the following command by pressing `<f>` (or `<ret>` in Kiki buffers):

```bash
$ echo "Starting build..." && sleep 1 && echo "Compiling modules..." && sleep 2 && echo "Build finished successfully!"
```

### 4. Executing in the background (`<b>`)

Spawns the command completely detached in the background subshell and echoes the process PID in Kakoune's status line and debug log:

```bash
$ sleep 10 && notify-send "Background task done!"
```

### 5. Running in an interactive terminal shell (`<!>` or `<D>`)

Spawns your active terminal emulator running the command in Kakoune's current `$PWD`, pausing on completion so you can inspect output or interact directly:

```bash
$ git log --graph --oneline --decorate -n 20
```

---

## Quickly creating & inserting commands:

These shortcuts insert your `kiki_prefix` so you don't need to type it manually every time.

### Smart New Command (`<a-c>` & `<a-C>`) — Normal & Insert Modes
Press `<a-c>` (downward) or `<a-C>` (upward) in either **normal mode** or **insert mode**:
- **`<a-c>` (downward):** Finds the next available line break below (or inserts line breaks if none exist), inserts `$ `, ensures blank line separation above and below, and places the cursor in insert mode.
- **`<a-C>` (upward):** Finds the previous available line break above (or inserts line breaks if none exist), inserts `$ `, ensures blank line separation above and below, and places the cursor in insert mode.
- If the current line is empty, it places the prompt with clean blank line separation above and below and enters insert mode.

### Prefixing existing lines (`<c>` and `<C>`)
- `<c>`: Inserts `$ ` at the current cursor position.
- `<C>`: Prefixes the beginning of the current line with `$ `.

Try it on the line below:
```
uptime
```

---

## Interactive Multi-Root File Tree (`<o>`):

Press `,o` or run `:kiki-file-tree [<path>]` to open a fluid, collapsible file tree in a scratch buffer `*kiki-file-tree*`.

```
- /home/user/project/
  + src/
  - tests/
      test_main.rs
  Cargo.toml
  README.md
```

### File Tree Keybindings:
- `<ret>` / `<c-o>`: Toggle folder expand (`+ `) / collapse (`- `), or open file directly into an editor buffer.
- `,g` / `` ` `` / `<a-g>`: Open **Git Action Popup** for any file or directory under cursor in the file tree (or in any Kiki buffer).
- `<tab>`: **Step Into** — promotes the selected subfolder to become the root directory of the tree view.
- `<c-l>`: **Move to Parent** — moves the tree view up to the parent directory.
- `*`: **Recursive Expand** — recursively unfolds all subdirectories under cursor.
- `-`: **Narrow** — hides unselected sibling folders to keep view focused.
- `r`: **In-Place Refresh** — re-reads the selected directory node from disk without losing your tree state.
- `.`: **Toggle Hidden Files** — shows or hides dotfiles on the fly.
- `p`: **Preview Client** — opens or replaces the buffer view in a connected Kakoune preview client in real time.
- `P`: Change Kakoune's working directory (`$PWD`) to the selected folder.
- `D`: Drop into an interactive shell in the selected folder.
- `q`: Close the file tree buffer.

#### Git Repository Action Popup in File Tree (`,g` / `` ` `` / `<a-g>`):
Pressing `,g` (aliases `` ` ``, `<a-g>`) on any directory in `*kiki-file-tree*` opens the `tree-git` popup:
- `<tab>`/`<s-tab>`: **Next/Prev file** — rotate to next/prev changed file
- `g`/`s`: **Status** — opens `git status` in a FIFO buffer for that repository.
- `c`: **Commit...** — opens the Git commit menu (`commit`).
- `l`: **Log** — runs `git log` in an interactive shell terminal for that repo.
- `d`: **Diff** — runs `git diff` in an interactive shell terminal for that repo.
- `q`: **Quit popup** — closes the popup without changes.

Pressing `,g` (aliases `` ` ``, `<a-g>`) on any file (in the file tree or inside normal editor buffers) opens the contextual Git action popup (`untracked`, `modified`, `staged`, or `git`) scoped to that file.

> **Tip:** You can also run `:edit /path/to/dir/` (or `:e .`) as usual. Kiki automatically catches Kakoune's directory error and opens the file tree for that folder.

---

## Navigating your filesystem & URLs:

Kiki automatically detects file paths, URLs, compiler errors, and grep matches on the current line:

```
src/main.rs:42:15: error: unresolved name
MacApps:52:Stapler.app
https://kakoune.org
~/.config/kak/kakrc
```

- **Open URL (`<u>` or `:open-url`):**
  Hover on any line with an HTTP/HTTPS URL and press `,u` to open it in your default web browser (`xdg-open` / `open` / `$BROWSER`). If multiple URLs exist on the line or in the buffer, Kiki opens a menu prompt to choose.
- **`ls -alh` inline (`<l>`):**
  Hover your cursor on the line with the path and press `<l>` to print detailed file information inline.
  ```python
  # I'm referencing a system configuration file:
  config_file = "/etc/hosts"
  ```
- **Edit file (`<e>`):**
  Hover on the path above and press `<e>`. Kiki opens the file directly, positioning the cursor at `line:col` if specified in compiler/grep format. If the file does not exist in `$PWD`, it automatically searches your topic notes.
- **Preview in connected client (`<p>` or `:kiki-preview`):**
  Hover on a path or file tree item and press `<p>`. If a Kakoune client named `preview` (or `$toolsclient`) is connected to the session, it updates the view in that client instantly. If not, it spawns a new terminal window attached to your session.
- **Change working directory (`<P>` or `P`):**
  Changes Kakoune's working directory to the target folder or parent folder of a file path on the line. When invoked on a normal non-directory line (e.g. via popup `,P`), it automatically changes directory to the current buffer's parent directory (or does nothing if the buffer is unsaved).
- **Drop to shell (`<D>`):**
  Suspends Kakoune and opens an interactive shell in the directory under cursor.

---

## Topic Notes & Scratchpads:

### Topics (`*.kiki`)
Topics are persistent notes stored in your `kiki_topics` directory (default: `~/.config/kak/kiki/`). They are ideal for cheatsheets, project runbooks, or command snippets.

- **Open / Create Topic (`<t>`):**
  Type `$ topicname` on a line and press `<t>` to open `~/.config/kak/kiki/topicname.kiki`.
- **List All Topics (`<T>`):**
  Press `<T>` to open a scratch buffer listing all available topics with `$ ` prefixes. Press `<ret>` on any topic in the list to open it immediately.

### Scratchpads
- **Quick Persistent Scratchpad (`<,>`):**
  Opens `~/.config/kak/kiki/scratchpad.kiki`. Anything you save here is permanently stored.
- **Disposable Scratchpad (`<q>`):**
  Opens a fresh disposable scratchpad buffer `*kiki-scratchpad-<timestamp>*`.

---

## Interactive Git Status & Action Menu:

When you run `$ git status` or `$ git status -s` inside Kiki buffers, Kiki automatically highlights the status entries:
- **Green**: Staged changes (`new file:`, `A `, `M `)
- **Yellow**: Unstaged modifications (`modified:`, ` M`)
- **Magenta**: Untracked files (`Untracked files:`, `??`)
- **Red**: Deleted files (`deleted:`, ` D`) or merge conflicts

Pressing `<ret>` or rotating with `<tab>` / `<s-tab>` opens the **Smart Git Action Popup** (via `,g` / `` ` ``) tailored to the file's current status:
- **Modified files:** `<s>` Stage, `<X>` Restore (prompt confirmation), `<S>` Stage All, `<v>` Diff, `<e>` Edit, `<p>` Preview
- **Staged files:** `<u>` Unstage, `<X>` Restore & Discard Staged (prompt confirmation), `<U>` Unstage All, `<v>` Diff (cached), `<e>` Edit, `<p>` Preview
- **Untracked files:** `<a>` Add, `<s>` Stage, `<X>` Clean untracked file (prompt confirmation), `<S>` Stage All, `<v>` Diff, `<e>` Edit, `<p>` Preview

| Key | Action | Contextual Description |
| :--- | :--- | :--- |
| `<tab>` | **Next File** | Rotates to next changed file with action popup open (in every popup including `git`/`tree-git`/`commit`) |
| `<s-tab>` | **Prev File** | Rotates to previous changed file with action popup open (in every popup including `git`/`tree-git`/`commit`) |
| `g` | **Status** | Shows `git status` in streaming FIFO buffer (available in every git popup) |
| `s` | **Stage** | Stages modified or untracked file (`git add`) |
| `a` | **Add** | Adds/stages untracked or modified file (`git add`) |
| `u` | **Unstage** | Unstages staged file (`git restore --staged`) |
| `X` | **Restore / Clean** | Prompts confirmation, then restores modified/staged file (`git restore`) or cleans untracked file (`git clean`) |
| `S` | **Stage All** | Stages all modified and untracked files (`git add -A`) |
| `U` | **Unstage All** | Unstages all staged changes (`git restore --staged .`) |
| `A` | **Add All (CWD)** | Stages all changes in current directory (`git add .`) |
| `c` | **Commit Menu** | Enters the commit popup menu (`commit`) |
| `v` | **Diff** | Drops to terminal shell running `git diff` for file (cached diff if staged) |
| `d` | **Diff All (Unstaged)** | Drops to terminal shell running `git diff` for all files |
| `D` | **Diff All (Staged)** | Drops to terminal shell running `git diff --cached` for all files |
| `l` | **Git Log** | Drops to terminal shell running `git log` |
| `r` | **Refresh** | Refreshes the Git status block in-place without altering other text |
| `p` | **Preview** | Previews the target file in connected `preview` client |
| `e` | **Edit** | Opens the file directly in Kakoune |
| `q` | **Quit Buffer** | Closes/quits current buffer |

### Git Commit Popup (`commit`):
Press `c` inside the Git action popup to enter the commit menu:
- `<tab>`/`<s-tab>`: Rotate to next/prev changed file
- `g`: Status (`git status` in FIFO buffer)
- `c`: Run `git commit` in interactive terminal shell
- `a`: Run `git commit -a` (commit all tracked changes) in terminal shell
- `A`: Run `git commit --amend` in interactive terminal shell
- `N`: Run `git commit --amend --no-edit` in interactive terminal shell
- `q`: Quit popup menu

---

## Smart Keybindings in Kiki Buffers (`filetype=kiki`):

Inside any Kiki-managed buffer (`*kiki-scratch*`, `*kiki-fifo-*`, `*kiki-file-tree*`, `*kiki-topics-*`, or `*.kiki` files), normal mode keys act contextually without needing a leader prefix:

| Key | Contextual Behavior |
| :--- | :--- |
| `<ret>` | Streams command (FIFO) / Opens file / Opens tree / Toggles tree folder / Opens topic / Opens Git action popup |
| `<tab>` | Executes inline / Opens file / Steps into folder / Rotates next Git status file (opens action popup) |
| `<s-tab>` | Steps back in tree / Rotates previous Git status file (opens action popup) |
| `O` | Smart open (FIFO on command, file tree on path, opens topic in list) |
| `p` | Opens or updates buffer view in connected preview client (`preview`) |
| `P` | Changes working directory to folder or file's parent directory |
| `D` | Terminal shell on command, or drops into interactive shell in folder |
| `<a-c>` | Inserts `$ ` on current or next empty line below (normal & insert mode) |
| `<a-C>` | Inserts `$ ` on current or previous empty line above (normal & insert mode) |
| `<c-o>` | Toggles folder expand/collapse in tree or opens file |
| `<c-l>` | Moves up to parent folder in tree |
| `*` | Recursively expands tree node |
| `-` | Narrows/hides sibling folders in tree |
| `r` | Refreshes directory node or Git status block in-place |
| `.` | Toggles hidden dotfiles in tree |
| `,g` / `` ` `` / `<a-g>` | Opens Git action popup for any file or directory (in file tree or buffers) |
| `q` | Closes buffer |

---

## Buffer Cleanup Menu (`<d>`):

Press `,d` to enter the cleanup menu:

| Key | Command | Description |
| :--- | :--- | :--- |
| `a` | `kiki-close-all-buffers` | Close all Kiki-managed buffers |
| `f` | `kiki-close-fifo-buffers` | Close all `*kiki-fifo-*` streaming buffers |
| `t` | `kiki-close-topics-buffers` | Close all `*kiki-topics-*` list buffers |
| `r` | `kiki-close-tree-buffers` | Close all `*kiki-file-tree*` buffers |
| `s` | `kiki-close-scratchpad-buffers` | Close all `*kiki-scratchpad-*` buffers |
| `p` | `kiki-close-preview-buffers` | Close all `*kiki-preview*` buffers |
| `k` | `kiki-close-file-buffers` | Close all open `.kiki` file buffers |

---

## Sudo Authentication & Ticket Caching:

When running commands containing `sudo` (e.g. `$ sudo systemctl restart nginx`):
1. Kiki tests your OS-level sudo ticket with `sudo -n true`.
2. If already validated, the command runs instantly without interrupting you.
3. If password authentication is needed, Kakoune opens a secure masked prompt: `Password:`.
4. Kiki authenticates using `sudo -S -v`, updating `/run/sudo/ts/` so future commands run seamlessly.

---

## Interactive Shell Auto-Detection:

When dropping to a terminal shell (`<D>` or `,D`), Kiki automatically detects your active shell by inspecting ancestor processes of the Kakoune session, supporting:
- **`zsh`**
- **`fish`**
- **`bash`**
- **`nushell`** (`nu`)
- Custom shell configured via `set-option global kiki_shell "fish"`

---

## Configuration & Options:

You can customize Kiki in your `kakrc`:

```kak
# Custom command prefix (default: "$ ")
set-option global kiki_prefix "$ "

# Topics storage directory (default: "~/.config/kak/kiki/")
set-option global kiki_topics "~/.config/kak/kiki/"

# Custom shell for drop-to-shell (auto-detects zsh/fish/bash by default)
set-option global kiki_shell ""

# Show hidden files by default in file tree (default: false)
set-option global kiki_tree_show_hidden false
```

---

## Complete Keybinding Cheat Sheet:

### User Mode `,` (Leader)

| Key | Command | Description |
| :--- | :--- | :--- |
| `c` | — | Insert `kiki_prefix` (`$ `) at cursor position |
| `C` | — | Prefix current line with `kiki_prefix` (`I$ `) |
| `<a-c>` | `kiki-smart-new-command` | Insert `kiki_prefix` on current or next empty line |
| `<a-C>` | `kiki-smart-new-command-above` | Insert `kiki_prefix` on current or previous empty line |
| `y` | `kiki-select` | Select and yank command text after prefix |
| `i` | `kiki-inline` | Execute command and insert output below |
| `s` | `kiki-scratch` | Execute command into `*kiki-scratch*` buffer |
| `f` | `kiki-fifo` | Stream command output to FIFO buffer |
| `b` | `kiki-background`| Execute command detached in background with PID |
| `!` | `kiki-shell` | Run command in interactive terminal shell |
| `g` | `kiki-smart-git-popup` | Open git action popup on file/directory (aliases `` ` ``, `<a-g>`) |
| `` ` `` | `kiki-smart-git-popup` | Open git action popup on file/directory (alias for `g`) |
| `u` | `kiki-open-url` | Open URL from line or buffer in browser |
| `l` | `kiki-ls` | Run `ls -alh` on path under cursor |
| `e` | `kiki-edit` | Open file at path (supports `file:line:col` and topics) |
| `o` | `kiki-file-tree` | Open interactive collapsible file tree |
| `p` | `kiki-preview` | Open or replace buffer in preview client |
| `t` | `kiki-topic` | Open topic file by name (`<topic>.kiki`) |
| `T` | `kiki-list-topics` | List available topic files in scratch buffer |
| `P` | `kiki-cd` | Change directory to path under cursor, or buffer parent on normal lines |
| `D` | `kiki-drop-to-shell` | Drop to shell in selected directory |
| `q` | `kiki-scratchpad` | Open disposable quick scratchpad |
| `,` | — | Open persistent `scratchpad.kiki` |
| `d` | — | Enter `kiki-delete` buffer cleanup menu |

---

## Acknowledgments & Credits

Kiki was originally conceived and created by **[Alexander Maricich (2019)](https://github.com/w33tmaricich/kiki)**.

This modernized and expanded edition builds upon the original concept by introducing:
- Interactive multi-root collapsible file tree with folder step-into (`<tab>`), move-to-parent (`<c-l>`), recursive expansion (`*`), and in-place refresh (`r`).
- Contextual smart keybindings in Kiki buffers (`<ret>`, `<tab>`, `O`, `P`, `D`, `<a-c>`, `<a-C>`, `q`).
- Ancestor process-tree interactive shell auto-detection (`zsh`, `fish`, `bash`, `nu`).
- Decoupled `stdin` execution preventing editor lockups.
- Dynamic option-driven prefix parsing and synchronized regex syntax highlighting.
- Native OS-level `sudo` ticket validation and caching.
