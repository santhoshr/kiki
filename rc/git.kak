# Kiki Git Status Recognition & Interactive Action Menu

# User modes for Git actions
try %{ declare-user-mode git }
try %{ declare-user-mode tree-git }
try %{ declare-user-mode untracked }
try %{ declare-user-mode modified }
try %{ declare-user-mode staged }
try %{ declare-user-mode staged-modified }
try %{ declare-user-mode commit }

# Options for tracking git target and status
declare-option -hidden str kiki_git_target ""
declare-option -hidden str kiki_git_status_type ""
declare-option -hidden str kiki_tree_git_repo ""

# Highlighting for Git Status inside Kiki buffers
try %{ add-highlighter -override global/kiki_git_branch regex "(?m)^## [^\n]+" 0:cyan+b }
try %{ add-highlighter -override global/kiki_git_header_staged regex "(?m)^Changes to be committed:" 0:green+b }
try %{ add-highlighter -override global/kiki_git_header_unstaged regex "(?m)^Changes not staged for commit:" 0:yellow+b }
try %{ add-highlighter -override global/kiki_git_header_untracked regex "(?m)^Untracked files:" 0:magenta+b }
try %{ add-highlighter -override global/kiki_git_header_unmerged regex "(?m)^Unmerged paths:" 0:red+b }
try %{ add-highlighter -override global/kiki_git_hint regex "(?m)^\s*\([^\n]+\)" 0:comment }

try %{ add-highlighter -override global/kiki_git_modified regex "(?m)^\s*(modified:)\s+([^\n]+)" 1:yellow+b 2:default }
try %{ add-highlighter -override global/kiki_git_new_file regex "(?m)^\s*(new file:)\s+([^\n]+)" 1:green+b 2:default }
try %{ add-highlighter -override global/kiki_git_deleted regex "(?m)^\s*(deleted:)\s+([^\n]+)" 1:red+b 2:default }
try %{ add-highlighter -override global/kiki_git_renamed regex "(?m)^\s*(renamed:)\s+([^\n]+)" 1:cyan+b 2:default }
try %{ add-highlighter -override global/kiki_git_both_modified regex "(?m)^\s*(both modified:)\s+([^\n]+)" 1:red+b 2:default }

# Line parser and action menu trigger
define-command -override -hidden -params 1 \
    kiki-git-line-action %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        target=""
        status_type="modified"

        # 1. Standard git status formats
        if printf '%s\n' "$raw" | grep -Eq '^modified:[[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^modified:[[:space:]]*//')
            status_type="modified"
        elif printf '%s\n' "$raw" | grep -Eq '^new file:[[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^new file:[[:space:]]*//')
            status_type="staged"
        elif printf '%s\n' "$raw" | grep -Eq '^deleted:[[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^deleted:[[:space:]]*//')
            status_type="deleted"
        elif printf '%s\n' "$raw" | grep -Eq '^renamed:[[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^renamed:[[:space:]]*//' -e 's/.*->[[:space:]]*//')
            status_type="renamed"
        elif printf '%s\n' "$raw" | grep -Eq '^both modified:[[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^both modified:[[:space:]]*//')
            status_type="conflict"

        # 2. Short porcelain formats (e.g. M file, ?? file, A  file)
        elif printf '%s\n' "$raw" | grep -Eq '^[MADRC?U ][MADRC?U ][[:space:]]+'; then
            target=$(printf '%s\n' "$raw" | sed -e 's/^[MADRC?U ][MADRC?U ][[:space:]]*//' -e 's/.*->[[:space:]]*//')

        # 3. Plain filename (e.g. untracked files section list in standard git status)
        elif [ -n "$raw" ] && ! printf '%s\n' "$raw" | grep -Eq '^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|\(use "git|\(use git|\$|>|^[+-][[:space:]])'; then
            clean_raw=$(printf '%s\n' "$raw" | sed -e 's/^[\\\"'\''`(<]*//' -e 's/[\\\"'\''`)>]*$//')
            if [ -e "$clean_raw" ]; then
                target="$clean_raw"
            elif [ -n "$kak_opt_kiki_tree_git_repo" ] && [ -d "$kak_opt_kiki_tree_git_repo" ] \
                 && [ -e "${kak_opt_kiki_tree_git_repo%/}/${clean_raw}" ]; then
                target="${kak_opt_kiki_tree_git_repo%/}/${clean_raw}"
            fi
        fi
        target=$(printf '%s\n' "$target" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^[\\\"'\''\`]*//' -e 's/[\\\"'\''\`]*$//')
        # If target is relative, try to resolve it to an absolute path using kiki_tree_git_repo
        case "$target" in
            /*) ;;
            "")  ;;
            *)
                if [ -n "$kak_opt_kiki_tree_git_repo" ] && [ -d "$kak_opt_kiki_tree_git_repo" ] \
                   && [ -e "${kak_opt_kiki_tree_git_repo%/}/${target}" ]; then
                    target="${kak_opt_kiki_tree_git_repo%/}/${target}"
                fi
                ;;
        esac

        # Helper to compute parent/repo display
        display_repo() {
            r="$1"
            if [ -n "$r" ]; then
                r_clean="${r%/}"
                r_base=$(basename "$r_clean")
                r_parent=$(basename "$(dirname "$r_clean")")
                if [ -n "$r_parent" ] && [ "$r_parent" != "/" ] && [ "$r_parent" != "." ]; then
                    printf "%s/%s" "$r_parent" "$r_base"
                else
                    printf "%s" "$r_base"
                fi
            fi
        }

        # Check if target is a directory
        if [ -n "$target" ] && [ -d "$target" ]; then
            # If target is a directory, check if it is or belongs to a git repository
            top=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$top" ]; then
                printf "set-option buffer kiki_tree_git_repo %%{%s}\n" "$target"
                printf "set-option buffer kiki_git_target %%{%s}\n" "$target"
                printf "set-option buffer kiki_git_status_type %%{%s}\n" "dir"
                repo_label=$(display_repo "$top")
                printf "enter-user-mode tree-git\n"
                printf "echo -markup \"{cyan}[kiki-git]{default} {yellow}%s{default} Git directory: {yellow}%s{default}\"\n" "$repo_label" "$target"
                exit 0
            fi
        fi

        # Double check actual git porcelain status of target
        if [ -n "$target" ]; then
            repo_dir=""
            if [ -n "$kak_opt_kiki_tree_git_repo" ] && [ -d "$kak_opt_kiki_tree_git_repo" ]; then
                repo_dir="$kak_opt_kiki_tree_git_repo"
            fi
            if [ -z "$repo_dir" ]; then
                repo_dir=$(git rev-parse --show-toplevel 2>/dev/null)
            fi
            if [ -z "$repo_dir" ] && [ -e "$target" ]; then
                repo_dir=$(git -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null)
            fi

            if [ -n "$repo_dir" ]; then
                printf "set-option buffer kiki_tree_git_repo %%{%s}\n" "$repo_dir"
                actual_porc=$(git -C "$repo_dir" status --porcelain -- "$target" 2>/dev/null | head -n1)
            else
                actual_porc=$(git status --porcelain -- "$target" 2>/dev/null | head -n1)
            fi

            is_clean_file=0
            if [ -n "$actual_porc" ]; then
                code=$(printf '%s\n' "$actual_porc" | cut -c1-2)
                case "$code" in
                    "??"|"?? ") status_type="untracked" ;;
                    "A "*|"M "*|"D "*|"R "*|"C "*) status_type="staged" ;;
                    " M"|" D"|" U") status_type="modified" ;;
                    "MM"|"AM") status_type="staged+modified" ;;
                    *) status_type="modified" ;;
                esac
            else
                # If target exists and is tracked or clean
                if [ -n "$repo_dir" ] && git -C "$repo_dir" ls-files --error-unmatch "$target" >/dev/null 2>&1; then
                    status_type="clean"
                    is_clean_file=1
                elif [ -e "$target" ]; then
                    status_type="untracked"
                fi
            fi

            printf "set-option buffer kiki_git_target %%{%s}\n" "$target"
            printf "set-option buffer kiki_git_status_type %%{%s}\n" "$status_type"

            repo_disp=""
            [ -n "$repo_dir" ] && repo_disp=$(display_repo "$repo_dir")
            [ -z "$repo_disp" ] && [ -n "$top" ] && repo_disp=$(display_repo "$top")
            prefix_info=""
            if [ -n "$repo_disp" ]; then
                prefix_info="{yellow}${repo_disp}{default} "
            fi

            # Compute display path: relative to repo_dir if possible, else basename
            target_disp="$target"
            _ref="${repo_dir:-$top}"
            if [ -n "$_ref" ]; then
                _ref="${_ref%/}/"
                case "$target" in
                    "$_ref"*) target_disp="./${target#"$_ref"}" ;;
                esac
            fi
            [ "$target_disp" = "$target" ] && target_disp="$(basename "$target")"

            if [ "$is_clean_file" -eq 1 ]; then
                printf "enter-user-mode git\n"
                printf "echo -markup \"{cyan}[kiki-git]{default} %sFile (clean): {green}%s{default}\"\n" "$prefix_info" "$target_disp"
            else
                case "$status_type" in
                    "untracked")
                        printf "enter-user-mode untracked\n"
                        printf "echo -markup \"{cyan}[kiki-git]{default} %sUntracked: {magenta}%s{default}\"\n" "$prefix_info" "$target_disp"
                        ;;
                    "staged")
                        printf "enter-user-mode staged\n"
                        printf "echo -markup \"{cyan}[kiki-git]{default} %sStaged: {green}%s{default}\"\n" "$prefix_info" "$target_disp"
                        ;;
                    "staged+modified")
                        printf "enter-user-mode staged-modified\n"
                        printf "echo -markup \"{cyan}[kiki-git]{default} %sStaged+Modified: {green}%s{default}\"\n" "$prefix_info" "$target_disp"
                        ;;
                    *)
                        printf "enter-user-mode modified\n"
                        printf "echo -markup \"{cyan}[kiki-git]{default} %sModified: {yellow}%s{default}\"\n" "$prefix_info" "$target_disp"
                        ;;
                esac
            fi
        else
            top=""
            if [ -n "$kak_buffile" ] && [ -e "$kak_buffile" ]; then
                top=$(git -C "$(dirname "$kak_buffile")" rev-parse --show-toplevel 2>/dev/null)
            fi
            if [ -z "$top" ]; then
                top=$(git rev-parse --show-toplevel 2>/dev/null)
            fi
            if [ -n "$top" ]; then
                printf "set-option buffer kiki_tree_git_repo %%{%s}\n" "$top"
            fi
            repo_disp=""
            [ -n "$top" ] && repo_disp=$(display_repo "$top")
            prefix_info=""
            [ -n "$repo_disp" ] && prefix_info="{yellow}${repo_disp}{default} "

            printf "set-option buffer kiki_git_target \"\"\n"
            printf "set-option buffer kiki_git_status_type \"\"\n"
            printf "enter-user-mode git\n"
            printf "echo -markup \"{cyan}[kiki-git]{default} %sCommon git actions\"\n" "$prefix_info"
        fi
    }}

# Git popup trigger for resolved file tree paths (files or directories)
define-command -override -hidden -params 1 \
    kiki-tree-git-action %{ evaluate-commands %sh{
        path="$1"
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        if [ -z "$path" ]; then
            printf '%s %%{ enter-user-mode git }\n' "$eval_cmd"
            exit 0
        fi

        if [ -d "$path" ]; then
            top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$top" ]; then
                r_clean="${top%/}"
                r_base=$(basename "$r_clean")
                r_parent=$(basename "$(dirname "$r_clean")")
                if [ -n "$r_parent" ] && [ "$r_parent" != "/" ] && [ "$r_parent" != "." ]; then
                    repo_disp="${r_parent}/${r_base}"
                else
                    repo_disp="${r_base}"
                fi
                printf '%s %%{ set-option buffer kiki_tree_git_repo %%{%s}; set-option buffer kiki_git_target %%{%s}; set-option buffer kiki_git_status_type "dir"; enter-user-mode tree-git; echo -markup "{cyan}[kiki-git]{default} {yellow}%s{default} Git repo: {yellow}%s{default}" }\n' "$eval_cmd" "$path" "$path" "$repo_disp" "$path"
            else
                printf '%s %%{ echo -markup "{yellow}[kiki-git]{default} %s is not a git repository" }\n' "$eval_cmd" "$path"
            fi
            exit 0
        fi

        if [ -f "$path" ] || [ -e "$path" ]; then
            top=$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$top" ]; then
                printf '%s %%{ set-option buffer kiki_tree_git_repo %%{%s}; kiki-git-line-action %%{%s} }\n' "$eval_cmd" "$top" "$path"
            else
                printf '%s %%{ echo -markup "{yellow}[kiki-git]{default} %s is not in a git repository" }\n' "$eval_cmd" "$path"
            fi
            exit 0
        fi

        printf '%s %%{ kiki-git-line-action %%{%s} }\n' "$eval_cmd" "$path"
    }}

# Git actions:
# Stage file
define-command -override -docstring "kiki-git-stage: stage current git file target" \
    kiki-git-stage %{ evaluate-commands %sh{
        target="$kak_opt_kiki_git_target"
        if [ -n "$target" ]; then
            git add -- "$target" 2>&1
            printf "kiki-git-refresh\n"
        fi
    }}

# Unstage file
define-command -override -docstring "kiki-git-unstage: unstage current git file target" \
    kiki-git-unstage %{ evaluate-commands %sh{
        target="$kak_opt_kiki_git_target"
        if [ -n "$target" ]; then
            git restore --staged -- "$target" >/dev/null 2>&1 || git reset HEAD -- "$target" >/dev/null 2>&1
            printf "kiki-git-refresh\n"
        fi
    }}

# Add file (alias for stage)
define-command -override -docstring "kiki-git-add: add current git file target" \
    kiki-git-add %{
        kiki-git-stage
    }

# Stage all changes (git add -A)
define-command -override -docstring "kiki-git-stage-all: stage all changes (git add -A)" \
    kiki-git-stage-all %{ evaluate-commands %sh{
        git add -A 2>&1
        printf "kiki-git-refresh\n"
    }}

# Add all in current directory (git add .)
define-command -override -docstring "kiki-git-add-all: add changes in current directory (git add .)" \
    kiki-git-add-all %{ evaluate-commands %sh{
        git add . 2>&1
        printf "kiki-git-refresh\n"
    }}

# Unstage all changes (git restore --staged .)
define-command -override -docstring "kiki-git-unstage-all: unstage all changes (git restore --staged .)" \
    kiki-git-unstage-all %{ evaluate-commands %sh{
        git restore --staged . >/dev/null 2>&1 || git reset HEAD >/dev/null 2>&1
        printf "kiki-git-refresh\n"
    }}

# Restore modified file changes (with confirmation)
define-command -override -docstring "kiki-git-restore: prompt confirmation to restore modified file changes" \
    kiki-git-restore %{
        prompt "Restore %opt{kiki_git_target}? (y/n): " %{
            kiki-git-restore-do %val{text}
        }
    }

define-command -override -hidden -params 1 \
    kiki-git-restore-do %{ evaluate-commands %sh{
        ans="$1"
        case "$ans" in
            y*|Y*)
                target="$kak_opt_kiki_git_target"
                if [ -n "$target" ]; then
                    git restore -- "$target" >/dev/null 2>&1 || git checkout -- "$target" >/dev/null 2>&1
                    printf "kiki-git-refresh\n"
                fi
                ;;
            *)
                printf "echo \"kiki-git: restore canceled\"\n"
                ;;
        esac
    }}

# Restore staged file and discard staged changes (with confirmation)
define-command -override -docstring "kiki-git-restore-staged: prompt confirmation to restore staged file" \
    kiki-git-restore-staged %{
        prompt "Restore and discard staged changes in %opt{kiki_git_target}? (y/n): " %{
            kiki-git-restore-staged-do %val{text}
        }
    }

define-command -override -hidden -params 1 \
    kiki-git-restore-staged-do %{ evaluate-commands %sh{
        ans="$1"
        case "$ans" in
            y*|Y*)
                target="$kak_opt_kiki_git_target"
                if [ -n "$target" ]; then
                    git restore --staged --worktree -- "$target" >/dev/null 2>&1 || {
                        git restore --staged -- "$target" >/dev/null 2>&1 || git reset HEAD -- "$target" >/dev/null 2>&1
                        git restore -- "$target" >/dev/null 2>&1 || git checkout -- "$target" >/dev/null 2>&1
                    }
                    printf "kiki-git-refresh\n"
                fi
                ;;
            *)
                printf "echo \"kiki-git: restore canceled\"\n"
                ;;
        esac
    }}

# Clean untracked file (with confirmation)
define-command -override -docstring "kiki-git-clean: prompt confirmation to clean/remove untracked file" \
    kiki-git-clean %{
        prompt "Clean untracked %opt{kiki_git_target}? (y/n): " %{
            kiki-git-clean-do %val{text}
        }
    }

define-command -override -hidden -params 1 \
    kiki-git-clean-do %{ evaluate-commands %sh{
        ans="$1"
        case "$ans" in
            y*|Y*)
                target="$kak_opt_kiki_git_target"
                if [ -n "$target" ]; then
                    git clean -f -d -- "$target" >/dev/null 2>&1 || rm -rf -- "$target" >/dev/null 2>&1
                    printf "kiki-git-refresh\n"
                fi
                ;;
            *)
                printf "echo \"kiki-git: clean canceled\"\n"
                ;;
        esac
    }}

# Diff unstaged changes for target file (or full repo if no target) using drop to shell terminal
define-command -override -docstring "kiki-git-diff: show git diff (smart file diff, or full repo diff if no target) in interactive shell terminal" \
    kiki-git-diff %{ evaluate-commands %sh{
        target="$kak_opt_kiki_git_target"
        status_type="$kak_opt_kiki_git_status_type"
        if [ -z "$target" ]; then
            printf 'kiki-shell-do %%{git diff}\n'
            exit 0
        fi
        porc=$(git status --porcelain -- "$target" 2>/dev/null | head -n1)
        code=$(printf '%s\n' "$porc" | cut -c1-2)
        if [ "$code" = "??" ] || [ "$code" = "?? " ] || [ "$status_type" = "untracked" ]; then
            printf 'kiki-shell-do %%{git diff --no-index -- /dev/null "%s" || true}\n' "$target"
        elif [ "$code" = "M " ] || [ "$code" = "A " ] || [ "$code" = "D " ] || [ "$code" = "R " ] || [ "$code" = "C " ] || [ "$status_type" = "staged" ]; then
            # If only staged, run git diff --cached
            printf 'kiki-shell-do %%{git diff --cached -- "%s"}\n' "$target"
        else
            printf 'kiki-shell-do %%{git diff -- "%s"}\n' "$target"
        fi
    }}

# Diff staged changes for target file (or full staged repo if no target) using drop to shell terminal
define-command -override -docstring "kiki-git-diff-cached: show git diff --cached in interactive shell terminal" \
    kiki-git-diff-cached %{ evaluate-commands %sh{
        target="$kak_opt_kiki_git_target"
        if [ -z "$target" ]; then
            printf 'kiki-shell-do %%{git diff --cached}\n'
            exit 0
        fi
        printf 'kiki-shell-do %%{git diff --cached -- "%s"}\n' "$target"
    }}

# Diff all unstaged changes using drop to shell terminal
define-command -override -docstring "kiki-git-diff-all: show git diff (all unstaged) in interactive shell terminal" \
    kiki-git-diff-all %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git diff}\n' "$repo"
        else
            printf 'kiki-shell-do "git diff"\n'
        fi
    }}

# Diff all staged changes using drop to shell terminal
define-command -override -docstring "kiki-git-diff-all-cached: show git diff --cached (all staged) in interactive shell terminal" \
    kiki-git-diff-all-cached %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git diff --cached}\n' "$repo"
        else
            printf 'kiki-shell-do "git diff --cached"\n'
        fi
    }}

# Commit actions (drop to shell terminal)
define-command -override -docstring "kiki-git-commit: run git commit in interactive shell terminal" \
    kiki-git-commit %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git commit}\n' "$repo"
        else
            printf 'kiki-shell-do "git commit"\n'
        fi
    }}

define-command -override -docstring "kiki-git-commit-all: run git commit -a in interactive shell terminal" \
    kiki-git-commit-all %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git commit -a}\n' "$repo"
        else
            printf 'kiki-shell-do "git commit -a"\n'
        fi
    }}

define-command -override -docstring "kiki-git-commit-amend: run git commit --amend in interactive shell terminal" \
    kiki-git-commit-amend %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git commit --amend}\n' "$repo"
        else
            printf 'kiki-shell-do "git commit --amend"\n'
        fi
    }}

define-command -override -docstring "kiki-git-commit-amend-no-edit: run git commit --amend --no-edit in interactive shell terminal" \
    kiki-git-commit-amend-no-edit %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git commit --amend --no-edit}\n' "$repo"
        else
            printf 'kiki-shell-do "git commit --amend --no-edit"\n'
        fi
    }}

# Git status in fifo buffer with automatic first-file cursor focus
define-command -override -docstring "kiki-git-status: show git status in streaming fifo buffer and focus first file" \
    kiki-git-status %{ evaluate-commands %sh{
        pfx="${kak_opt_kiki_prefix:-\$ }"
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -z "$repo" ] || [ ! -d "$repo" ]; then
            if [ -n "$kak_buffile" ] && [ -e "$kak_buffile" ]; then
                buf_dir=$(dirname "$kak_buffile")
                top=$(git -C "$buf_dir" rev-parse --show-toplevel 2>/dev/null)
                if [ -n "$top" ]; then
                    repo="$top"
                fi
            fi
        fi
        if [ -z "$repo" ] || [ ! -d "$repo" ]; then
            top=$(git rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$top" ]; then
                repo="$top"
            else
                repo="$PWD"
            fi
        fi

        output_dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak-make.XXXXXXXX)
        output="${output_dir}/fifo"
        mkfifo "${output}"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            ( printf '%sgit status # %s\n' "$pfx" "$repo" > "${output}" && (cd "${repo}" && git status) >> "${output}" 2>&1 ) > /dev/null 2>&1 < /dev/null &
        else
            ( printf '%sgit status\n' "$pfx" > "${output}" && git status >> "${output}" 2>&1 ) > /dev/null 2>&1 < /dev/null &
        fi

        timestamp=$(date +%H%M%S)
        buffer_name="*kiki-fifo-git-status-${timestamp}*"
        client="${kak_client:-}"

        printf %s\\n "evaluate-commands -try-client '$kak_opt_toolsclient' %{
            edit! -fifo ${output} -scroll ${buffer_name}
            set-option buffer filetype kiki
            set-option buffer kiki_buffer_type kiki-buffer
            set-option buffer kiki_tree_git_repo %{${repo}}
            kiki-set-modeline kiki-buffer
            hook -always -once buffer BufCloseFifo .* %{
                nop %sh{ rm -rf \"${output_dir}\" }
                try %{ ansi-render }
                evaluate-commands -try-client '${client}' %{
                    kiki-git-jump-first-file
                }
            }
        }"
    }}

define-command -override -hidden \
    kiki-git-jump-first-file %{ evaluate-commands %sh{
        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-git-jump-first-file-do "%s"\n' "$tmp_buf"
    }}

define-command -override -hidden -params 1 \
    kiki-git-jump-first-file-do %{ evaluate-commands %sh{
        tmp_buf="$1"
        first_line=$(awk '
        function is_tree_line(s) {
            return (s ~ /^[ \t]*[+-][ \t]/ || s ~ /^[+-][ \t]/)
        }
        function is_cmd_or_topic(s) {
            if (s ~ /^[ \t]*>/ || s ~ /^>/) return 1
            if (s ~ /^[ \t]*\$[ \t]/ || s ~ /^\$[ \t]/) return 1
            return 0
        }
        function is_git_header(s) {
            return (s ~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|## )/)
        }
        function is_git_hint(s) {
            return (s ~ /^\(use "git/ || s ~ /^\(use git/ || s ~ /^\([^\)]+\)$/)
        }
        function is_explicit_git_file(raw,   s) {
            s = raw
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s ~ /^(modified:|new file:|deleted:|renamed:|both modified:)[ \t]+/) return 1
            if (raw ~ /^[MADRC?U ][MADRC?U ][ \t]+/) return 1
            return 0
        }
        BEGIN { first_file = 0 }
        {
            raw = $0
            s = raw
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s == "") next
            if (is_tree_line(raw) || is_cmd_or_topic(raw)) next
            if (is_git_header(s) || is_git_hint(s)) next

            if (is_explicit_git_file(raw)) {
                if (first_file == 0) first_file = NR
                next
            }

            if (raw ~ /^\t[^\t ]/ || raw ~ /^ {2,}[^ ]/) {
                if (first_file == 0) first_file = NR
                next
            }
        }
        END {
            if (first_file > 0) print first_file
            else print 0
        }' "$tmp_buf")

        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        if [ "$first_line" -gt 0 ] 2>/dev/null; then
            target_line=$(sed -n "${first_line}p" "$tmp_buf" 2>/dev/null)
            escaped_line=$(printf '%s' "$target_line" | sed "s/'/''/g")
            printf '%s %%{ select %s.1,%s.1; kiki-git-line-action '\''%s'\'' }\n' "$eval_cmd" "$first_line" "$first_line" "$escaped_line"
        else
            repo_disp=""
            [ -n "$kak_opt_kiki_tree_git_repo" ] && repo_disp=$(display_repo "$kak_opt_kiki_tree_git_repo")
            [ -z "$repo_disp" ] && [ -n "$top" ] && repo_disp=$(display_repo "$top")
            prefix_info=""
            [ -n "$repo_disp" ] && prefix_info="{yellow}${repo_disp}{default} "
            printf '%s %%{ select 1.1,1.1; set-option buffer kiki_git_target ""; set-option buffer kiki_git_status_type ""; enter-user-mode git; echo -markup "{cyan}[kiki-git]{default} %sWorking tree clean" }\n' "$eval_cmd" "$prefix_info"
        fi

        rm -f "$tmp_buf"
    }}

# Rotate/switch among changed files in Git status output (direction 1 = next, -1 = prev)
define-command -override -hidden -params 1 \
    kiki-git-rotate-file %{ evaluate-commands %sh{
        dir="$1"
        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-git-rotate-file-do "%s" "%s"\n' "$dir" "$tmp_buf"
    }}

define-command -override -hidden -params 2 \
    kiki-git-rotate-file-do %{ evaluate-commands %sh{
        dir="$1"
        tmp_buf="$2"
        cur_line="$kak_cursor_line"
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        result=$(awk -v cur="$cur_line" -v dir="$dir" -v bname="$kak_bufname" -v pfx="${kak_opt_kiki_prefix:-\$ }" '
        function is_tree_line(s) {
            return (s ~ /^[ \t]*[+-][ \t]/ || s ~ /^[+-][ \t]/)
        }
        function is_cmd_or_topic(s) {
            if (s ~ /^[ \t]*>/ || s ~ /^>/) return 1
            if (substr(s, 1, length(pfx)) == pfx) return 1
            if (s ~ /^[ \t]*\$[ \t]/ || s ~ /^\$[ \t]/) return 1
            return 0
        }
        function is_git_header(s) {
            return (s ~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|## )/)
        }
        function is_git_hint(s) {
            return (s ~ /^\(use "git/ || s ~ /^\(use git/ || s ~ /^\([^\)]+\)$/)
        }
        function is_explicit_git_file(raw,   s) {
            s = raw
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s ~ /^(modified:|new file:|deleted:|renamed:|both modified:)[ \t]+/) return 1
            if (raw ~ /^[MADRC?U ][MADRC?U ][ \t]+/) return 1
            return 0
        }
        function is_git_status_content(raw,   s) {
            s = raw
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s == "") return 1
            if (is_tree_line(raw) || is_cmd_or_topic(raw)) return 0
            if (is_git_header(s) || is_git_hint(s) || is_explicit_git_file(raw)) return 1
            if (raw ~ /^\t[^\t ]/ || raw ~ /^ {2,}[^ ]/) return 1
            return 0
        }

        BEGIN { total = 0 }
        {
            total++
            lines[total] = $0
        }
        END {
            if (total == 0) { print "0"; exit }
            if (cur < 1) cur = 1
            if (cur > total) cur = total

            # Determine git status block boundaries [block_start, block_end]
            is_fifo_git = (bname ~ /\*kiki-fifo-git/ || bname ~ /\*kiki-fifo-.*git/)
            if (is_fifo_git) {
                block_start = 1
                block_end = total
            } else {
                block_start = cur
                block_end = cur

                # Search backward for block start
                for (i = cur; i >= 1; i--) {
                    if (is_tree_line(lines[i]) || (lines[i] ~ /^[ \t]*>/ || lines[i] ~ /^>/)) {
                        block_start = i + 1
                        break
                    }
                    if (substr(lines[i], 1, length(pfx)) == pfx || substr(lines[i], 1, 2) == "$ ") {
                        c_str = lines[i]
                        if (substr(c_str, 1, length(pfx)) == pfx) c_str = substr(c_str, length(pfx) + 1)
                        else c_str = substr(c_str, 3)
                        gsub(/^[ \t]+|[ \t]+$/, "", c_str)
                        if (c_str ~ /^git/) {
                            block_start = i
                        } else {
                            block_start = i + 1
                        }
                        break
                    }
                    if (!is_git_status_content(lines[i])) {
                        block_start = i + 1
                        break
                    }
                    block_start = i
                }

                # Search forward for block end
                for (i = cur; i <= total; i++) {
                    if (is_tree_line(lines[i]) || is_cmd_or_topic(lines[i])) {
                        block_end = i - 1
                        break
                    }
                    if (!is_git_status_content(lines[i])) {
                        block_end = i - 1
                        break
                    }
                    block_end = i
                }

                # Trim blank lines at boundaries
                while (block_start <= block_end && lines[block_start] ~ /^[ \t]*$/) block_start++
                while (block_end >= block_start && lines[block_end] ~ /^[ \t]*$/) block_end--
            }

            if (block_start > block_end) {
                print "0"
                exit
            }

            # Collect all changed files within [block_start, block_end]
            file_count = 0
            for (i = block_start; i <= block_end; i++) {
                raw = lines[i]
                s = raw
                gsub(/^[ \t]+|[ \t]+$/, "", s)
                if (s == "") continue
                if (is_tree_line(raw) || is_cmd_or_topic(raw)) continue
                if (is_git_header(s) || is_git_hint(s)) continue

                if (is_explicit_git_file(raw)) {
                    file_count++
                    file_lines[file_count] = i
                } else if (raw ~ /^\t[^\t ]/ || raw ~ /^ {2,}[^ ]/) {
                    file_count++
                    file_lines[file_count] = i
                }
            }

            if (file_count == 0) {
                print "0"
                exit
            }

            # Find current position relative to file_lines
            cur_idx = 0
            for (i = 1; i <= file_count; i++) {
                if (file_lines[i] == cur) {
                    cur_idx = i
                    break
                }
            }

            if (dir > 0) {
                if (cur_idx > 0) {
                    next_idx = cur_idx + 1
                    if (next_idx > file_count) next_idx = 1
                } else {
                    next_idx = 1
                    for (i = 1; i <= file_count; i++) {
                        if (file_lines[i] > cur) {
                            next_idx = i
                            break
                        }
                    }
                }
            } else {
                if (cur_idx > 0) {
                    next_idx = cur_idx - 1
                    if (next_idx < 1) next_idx = file_count
                } else {
                    next_idx = file_count
                    for (i = file_count; i >= 1; i--) {
                        if (file_lines[i] < cur) {
                            next_idx = i
                            break
                        }
                    }
                }
            }

            print file_lines[next_idx]
        }' "$tmp_buf")

        if [ "$result" -gt 0 ] 2>/dev/null; then
            target_line=$(sed -n "${result}p" "$tmp_buf" 2>/dev/null)
            escaped_line=$(printf '%s' "$target_line" | sed "s/'/''/g")
            printf '%s %%{ select %s.1,%s.1; kiki-git-line-action '\''%s'\'' }\n' "$eval_cmd" "$result" "$result" "$escaped_line"
        else
            repo_disp=""
            [ -n "$kak_opt_kiki_tree_git_repo" ] && repo_disp=$(display_repo "$kak_opt_kiki_tree_git_repo")
            prefix_info=""
            [ -n "$repo_disp" ] && prefix_info="{yellow}${repo_disp}{default} "
            printf '%s %%{ set-option buffer kiki_git_target ""; set-option buffer kiki_git_status_type ""; enter-user-mode git; echo -markup "{cyan}[kiki-git]{default} %sWorking tree clean" }\n' "$eval_cmd" "$prefix_info"
        fi

        rm -f "$tmp_buf"
    }}

# Git log in interactive shell terminal
define-command -override -docstring "kiki-git-log: show git log in interactive shell terminal" \
    kiki-git-log %{ evaluate-commands %sh{
        repo="$kak_opt_kiki_tree_git_repo"
        if [ -n "$repo" ] && [ -d "$repo" ]; then
            printf 'kiki-shell-do %%{cd "%s" && git log}\n' "$repo"
        else
            printf 'kiki-shell-do "git log"\n'
        fi
    }}

# Refresh git status in-place without affecting other buffer content
define-command -override -docstring "kiki-git-refresh: refresh git status output at cursor without affecting other content" \
    kiki-git-refresh %{ evaluate-commands %sh{
        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-git-refresh-do "%s"\n' "$tmp_buf"
    }}

define-command -override -hidden -params 1 \
    kiki-git-refresh-do %{ evaluate-commands %sh{
        tmp_buf="$1"
        res=$(awk -v cur="$kak_cursor_line" -v pfx="${kak_opt_kiki_prefix:-\$ }" -v bname="$kak_bufname" '
        function is_git_line(raw,   s) {
            s = raw
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s == "") return 1
            if (s ~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit)/) return 1
            if (s ~ /^\(use "git/ || s ~ /^\(use git/ || s ~ /^(modified:|new file:|deleted:|renamed:|both modified:)/) return 1
            if (raw ~ /^\t[^\t ]/ || raw ~ /^ {2,}[^ ]/) return 1
            return 0
        }
        BEGIN { total = 0 }
        { total++; lines[total] = $0 }
        END {
            if (cur < 1 || cur > total) { print "NONE"; exit }

            cmd_line = 0; cmd = ""
            if (substr(lines[cur], 1, length(pfx)) == pfx) {
                cmd_line = cur; cmd = substr(lines[cur], length(pfx) + 1)
            } else if (substr(lines[cur], 1, 2) == "$ ") {
                cmd_line = cur; cmd = substr(lines[cur], 3)
            }

            if (cmd_line == 0) {
                for (i = cur; i >= 1; i--) {
                    if (substr(lines[i], 1, 1) == ">") break
                    if (substr(lines[i], 1, length(pfx)) == pfx) {
                        c_str = substr(lines[i], length(pfx) + 1)
                        gsub(/^[ \t]+|[ \t]+$/, "", c_str)
                        if (c_str ~ /^git/) { cmd_line = i; cmd = c_str }
                        break
                    } else if (substr(lines[i], 1, 2) == "$ ") {
                        c_str = substr(lines[i], 3)
                        gsub(/^[ \t]+|[ \t]+$/, "", c_str)
                        if (c_str ~ /^git/) { cmd_line = i; cmd = c_str }
                        break
                    }
                }
            }

            gsub(/^[ \t]+|[ \t]+$/, "", cmd)
            if (cmd_line > 0 && cmd ~ /^git/) {
                start_line = cmd_line + 1
                end_line = start_line - 1
                for (i = start_line; i <= total; i++) {
                    if (substr(lines[i], 1, length(pfx)) == pfx || substr(lines[i], 1, 2) == "$ " || substr(lines[i], 1, 1) == ">") break
                    end_line = i
                }
                while (end_line < total && end_line >= start_line && lines[end_line] ~ /^[ \t]*$/) {
                    end_line--
                }
                print cmd "|" start_line "|" end_line "|" cmd_line
                exit
            }

            is_git_line_cur = 0
            if (is_git_line(lines[cur])) {
                for (i = cur; i >= 1; i--) {
                    if (substr(lines[i], 1, 1) == ">" || substr(lines[i], 1, length(pfx)) == pfx || substr(lines[i], 1, 2) == "$ ") break
                    if (lines[i] ~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit)/) {
                        is_git_line_cur = 1; break
                    }
                }
                if (!is_git_line_cur) {
                    for (i = cur; i <= total; i++) {
                        if (substr(lines[i], 1, 1) == ">" || substr(lines[i], 1, length(pfx)) == pfx || substr(lines[i], 1, 2) == "$ ") break
                        if (lines[i] ~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit)/) {
                            is_git_line_cur = 1; break
                        }
                    }
                }
            }

            if (is_git_line_cur) {
                start_line = cur
                while (start_line > 1 && is_git_line(lines[start_line - 1]) && substr(lines[start_line - 1], 1, 1) != ">" && substr(lines[start_line - 1], 1, length(pfx)) != pfx && substr(lines[start_line - 1], 1, 2) != "$ ") {
                    start_line--
                }
                end_line = cur
                while (end_line < total && is_git_line(lines[end_line + 1]) && substr(lines[end_line + 1], 1, 1) != ">" && substr(lines[end_line + 1], 1, length(pfx)) != pfx && substr(lines[end_line + 1], 1, 2) != "$ ") {
                    end_line++
                }
                while (end_line < total && end_line >= start_line && lines[end_line] ~ /^[ \t]*$/) {
                    end_line--
                }
                if (start_line <= end_line) {
                    print "git status|" start_line "|" end_line "|0"
                    exit
                }
            }

            print "NONE"
        }' "$tmp_buf")

        rm -f "$tmp_buf"

        if [ "$res" = "NONE" ] || [ -z "$res" ]; then
            printf 'echo -markup "{yellow}kiki-git: no git status block found at cursor"\n'
            exit 0
        fi

        cmd=$(printf '%s\n' "$res" | cut -d'|' -f1)
        start_line=$(printf '%s\n' "$res" | cut -d'|' -f2)
        end_line=$(printf '%s\n' "$res" | cut -d'|' -f3)
        cmd_line=$(printf '%s\n' "$res" | cut -d'|' -f4)

        tmp_out=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-git-out.XXXXXXXX)
        repo_in_cmd=""
        case "$cmd" in
            *#*)
                repo_in_cmd=$(printf '%s\n' "$cmd" | sed -e 's/.*#[[:space:]]*//' -e 's/[[:space:]]*$//')
                ;;
        esac
        if [ -n "$repo_in_cmd" ] && [ -d "$repo_in_cmd" ]; then
            ( cd "$repo_in_cmd" && eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null
        elif [ -n "$kak_opt_kiki_tree_git_repo" ] && [ -d "$kak_opt_kiki_tree_git_repo" ]; then
            ( cd "$kak_opt_kiki_tree_git_repo" && eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null
        else
            ( eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null
        fi

        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        commands_to_eval=""
        if [ "$start_line" -le "$end_line" ]; then
            if [ -s "$tmp_out" ]; then
                commands_to_eval="select ${start_line}.1,${end_line}.99999999; execute-keys %{|cat \"${tmp_out}\"<ret>}"
            else
                commands_to_eval="select ${start_line}.1,${end_line}.99999999; execute-keys %{d}"
            fi
        else
            if [ -s "$tmp_out" ]; then
                commands_to_eval="select ${cmd_line}.1,${cmd_line}.99999999; execute-keys %{o<esc>|cat \"${tmp_out}\"<ret>}"
            fi
        fi

        # Find target position in newly updated status output
        target_info=$(awk -v tgt="$kak_opt_kiki_git_target" -v start="$start_line" '
        BEGIN { match_idx = 0; first_file_idx = 0 }
        {
            raw = $0
            gsub(/^[ \t]+|[ \t]+$/, "", raw)
            if (raw == "") next

            curr_tgt = ""
            if (raw ~ /^modified:[ \t]+/) curr_tgt = substr(raw, 10)
            else if (raw ~ /^new file:[ \t]+/) curr_tgt = substr(raw, 10)
            else if (raw ~ /^deleted:[ \t]+/) curr_tgt = substr(raw, 9)
            else if (raw ~ /^renamed:[ \t]+/) { curr_tgt = raw; sub(/^renamed:[ \t]*/, "", curr_tgt); sub(/.*->[ \t]*/, "", curr_tgt) }
            else if (raw ~ /^both modified:[ \t]+/) curr_tgt = substr(raw, 15)
            else if (raw ~ /^[MADRC?U ][MADRC?U ][ \t]+/) { curr_tgt = substr(raw, 4); sub(/.*->[ \t]*/, "", curr_tgt) }
            else if (raw !~ /^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|\(use "git|## )/) {
                if ($0 ~ /^\t[^\t ]/ || $0 ~ /^ {2,}[^ ]/) curr_tgt = raw
            }

            gsub(/^[ \t]+|[ \t]+$/, "", curr_tgt)
            if (curr_tgt != "") {
                if (first_file_idx == 0) {
                    first_file_idx = NR
                    first_file_line = $0
                }
                if (tgt != "" && curr_tgt == tgt) {
                    match_idx = NR
                    match_line = $0
                    exit
                }
            }
        }
        END {
            if (match_idx > 0) {
                print (start + match_idx - 1) "|" match_line
            } else if (first_file_idx > 0) {
                print (start + first_file_idx - 1) "|" first_file_line
            } else {
                print "0|"
            }
        }' "$tmp_out")

        target_pos=$(printf '%s\n' "$target_info" | cut -d'|' -f1)
        target_line=$(printf '%s\n' "$target_info" | cut -d'|' -f2-)
        escaped_line=$(printf '%s' "$target_line" | sed "s/'/''/g")

        if [ "$target_pos" -gt 0 ] 2>/dev/null; then
            commands_to_eval="${commands_to_eval}; select ${target_pos}.1,${target_pos}.1; kiki-git-line-action '${escaped_line}'"
        else
            repo_disp=""
            [ -n "$repo_in_cmd" ] && repo_disp=$(display_repo "$repo_in_cmd")
            [ -z "$repo_disp" ] && [ -n "$kak_opt_kiki_tree_git_repo" ] && repo_disp=$(display_repo "$kak_opt_kiki_tree_git_repo")
            prefix_info=""
            [ -n "$repo_disp" ] && prefix_info="{yellow}${repo_disp}{default} "
            commands_to_eval="${commands_to_eval}; select 1.1,1.1; set-option buffer kiki_git_target ''; set-option buffer kiki_git_status_type ''; enter-user-mode git; echo -markup '{cyan}[kiki-git]{default} ${prefix_info}Working tree clean'"
        fi

        if [ -n "$commands_to_eval" ]; then
            printf '%s %%{ %s }\n' "$eval_cmd" "$commands_to_eval"
        fi

        printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_out"
    }}

# Preview target in preview client
define-command -override -docstring "kiki-git-preview: preview target file in preview client" \
    kiki-git-preview %{
        kiki-preview-do %opt{kiki_git_target}
    }

# Edit target directly in Kakoune
define-command -override -docstring "kiki-git-edit: edit target file in Kakoune" \
    kiki-git-edit %{
        kiki-edit-do %opt{kiki_git_target}
    }

# Mappings for user mode untracked (Untracked / New File Popup)
map global untracked <tab> ':kiki-git-rotate-file 1<ret>' -docstring 'Next file'
map global untracked <s-tab> ':kiki-git-rotate-file -1<ret>' -docstring 'Prev file'
map global untracked a ':kiki-git-add<ret>' -docstring 'Add'
map global untracked s ':kiki-git-stage<ret>' -docstring 'Stage'
map global untracked X ':kiki-git-clean<ret>' -docstring 'Clean (prompt)'
map global untracked S ':kiki-git-stage-all<ret>' -docstring 'Stage all'
map global untracked c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global untracked v ':kiki-git-diff<ret>' -docstring 'Diff'
map global untracked d ':kiki-git-diff-all<ret>' -docstring 'Diff unstaged'
map global untracked D ':kiki-git-diff-all-cached<ret>' -docstring 'Diff staged'
map global untracked l ':kiki-git-log<ret>' -docstring 'Log'
map global untracked r ':kiki-git-refresh<ret>' -docstring 'Refresh'
map global untracked p ':kiki-git-preview<ret>' -docstring 'Preview'
map global untracked e ':kiki-git-edit<ret>' -docstring 'Edit'
map global untracked q ':kiki-smart-close<ret>' -docstring 'Quit buffer'

# Mappings for user mode modified (Modified / Conflict File Popup)
map global modified <tab> ':kiki-git-rotate-file 1<ret>' -docstring 'Next file'
map global modified <s-tab> ':kiki-git-rotate-file -1<ret>' -docstring 'Prev file'
map global modified s ':kiki-git-stage<ret>' -docstring 'Stage'
map global modified a ':kiki-git-stage<ret>' -docstring 'Stage'
map global modified X ':kiki-git-restore<ret>' -docstring 'Restore (prompt)'
map global modified S ':kiki-git-stage-all<ret>' -docstring 'Stage all'
map global modified c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global modified v ':kiki-git-diff<ret>' -docstring 'Diff'
map global modified d ':kiki-git-diff-all<ret>' -docstring 'Diff unstaged'
map global modified D ':kiki-git-diff-all-cached<ret>' -docstring 'Diff staged'
map global modified l ':kiki-git-log<ret>' -docstring 'Log'
map global modified r ':kiki-git-refresh<ret>' -docstring 'Refresh'
map global modified p ':kiki-git-preview<ret>' -docstring 'Preview'
map global modified e ':kiki-git-edit<ret>' -docstring 'Edit'
map global modified q ':kiki-smart-close<ret>' -docstring 'Quit buffer'

# Mappings for user mode staged (Staged File Popup)
map global staged <tab> ':kiki-git-rotate-file 1<ret>' -docstring 'Next file'
map global staged <s-tab> ':kiki-git-rotate-file -1<ret>' -docstring 'Prev file'
map global staged u ':kiki-git-unstage<ret>' -docstring 'Unstage'
map global staged X ':kiki-git-restore-staged<ret>' -docstring 'Restore (prompt)'
map global staged U ':kiki-git-unstage-all<ret>' -docstring 'Unstage all'
map global staged c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global staged v ':kiki-git-diff-cached<ret>' -docstring 'Diff (cached)'
map global staged d ':kiki-git-diff-all<ret>' -docstring 'Diff unstaged'
map global staged D ':kiki-git-diff-all-cached<ret>' -docstring 'Diff staged'
map global staged l ':kiki-git-log<ret>' -docstring 'Log'
map global staged r ':kiki-git-refresh<ret>' -docstring 'Refresh'
map global staged p ':kiki-git-preview<ret>' -docstring 'Preview'
map global staged e ':kiki-git-edit<ret>' -docstring 'Edit'
map global staged q ':kiki-smart-close<ret>' -docstring 'Quit buffer'

# Mappings for user mode staged-modified (Staged + Modified File Popup)
map global staged-modified <tab> ':kiki-git-rotate-file 1<ret>' -docstring 'Next file'
map global staged-modified <s-tab> ':kiki-git-rotate-file -1<ret>' -docstring 'Prev file'
map global staged-modified s ':kiki-git-stage<ret>' -docstring 'Stage'
map global staged-modified u ':kiki-git-unstage<ret>' -docstring 'Unstage'
map global staged-modified X ':kiki-git-restore-staged<ret>' -docstring 'Restore (prompt)'
map global staged-modified S ':kiki-git-stage-all<ret>' -docstring 'Stage all'
map global staged-modified U ':kiki-git-unstage-all<ret>' -docstring 'Unstage all'
map global staged-modified c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global staged-modified v ':kiki-git-diff<ret>' -docstring 'Diff'
map global staged-modified d ':kiki-git-diff-all<ret>' -docstring 'Diff unstaged'
map global staged-modified D ':kiki-git-diff-all-cached<ret>' -docstring 'Diff staged'
map global staged-modified l ':kiki-git-log<ret>' -docstring 'Log'
map global staged-modified r ':kiki-git-refresh<ret>' -docstring 'Refresh'
map global staged-modified p ':kiki-git-preview<ret>' -docstring 'Preview'
map global staged-modified e ':kiki-git-edit<ret>' -docstring 'Edit'
map global staged-modified q ':kiki-smart-close<ret>' -docstring 'Quit buffer'

# Mappings for user mode git (Compact Common Git Actions Popup / Clean tree)
map global git <tab> ':kiki-git-rotate-file 1<ret>' -docstring 'Next file'
map global git <s-tab> ':kiki-git-rotate-file -1<ret>' -docstring 'Prev file'
map global git s ':kiki-git-status<ret>' -docstring 'Status'
map global git c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global git l ':kiki-git-log<ret>' -docstring 'Log'
map global git d ':kiki-git-diff-all<ret>' -docstring 'Diff'
map global git r ':kiki-git-refresh<ret>' -docstring 'Refresh'
map global git p ':kiki-git-preview<ret>' -docstring 'Preview'
map global git e ':kiki-git-edit<ret>' -docstring 'Edit'
map global git q ':kiki-smart-close<ret>' -docstring 'Quit buffer'

# Mappings for user mode tree-git (File tree git common popup)
map global tree-git s ':kiki-git-status<ret>' -docstring 'Status'
map global tree-git c ':enter-user-mode commit<ret>' -docstring 'Commit...'
map global tree-git l ':kiki-git-log<ret>' -docstring 'Log'
map global tree-git d ':kiki-git-diff-all<ret>' -docstring 'Diff'
map global tree-git q ':nop<ret>' -docstring 'Quit popup'

# Mappings for user mode commit (Commit actions popup)
map global commit c ':kiki-git-commit<ret>' -docstring 'Commit'
map global commit a ':kiki-git-commit-all<ret>' -docstring 'Commit all (-a)'
map global commit A ':kiki-git-commit-amend<ret>' -docstring 'Amend'
map global commit N ':kiki-git-commit-amend-no-edit<ret>' -docstring 'Amend no-edit'
map global commit q ':nop<ret>' -docstring 'Quit'
