# Set unified kiki-buffer type and kiki filetype for all kiki files and scratch buffers
hook -group kiki global BufOpenFile .*\.kiki$ %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
}

hook -group kiki global BufOpenFile .*\.kikitree$ %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
}

hook -group kiki global BufCreate \*kiki-.*\* %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
}

hook -group kiki global BufSetOption filetype=kiki %{
    map buffer normal <ret> ':kiki-smart-enter<ret>' -docstring 'Execute command in FIFO, open file/folder, or toggle tree'
    map buffer normal <c-o> ':kiki-smart-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map buffer normal O ':kiki-smart-open<ret>' -docstring 'Open topic if topic list, file tree if path, or fifo if command'
    map buffer normal <tab> ':kiki-smart-step-into<ret>' -docstring 'Execute command inline, open file/folder, step into tree, or rotate git file'
    map buffer normal <s-tab> ':kiki-smart-step-back<ret>' -docstring 'Step back in tree or rotate previous git file'
    map buffer normal p ':kiki-smart-preview<ret>' -docstring 'Open or replace buffer view in preview client'
    map buffer normal P ':kiki-smart-cd<ret>' -docstring 'Change directory to folder path or parent of file path'
    map buffer normal <c-l> ':kiki-smart-parent<ret>' -docstring 'Move to parent folder'
    map buffer normal r ':kiki-smart-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map buffer normal * ':kiki-smart-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map buffer normal <minus> ':kiki-smart-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map buffer normal . ':kiki-smart-dot<ret>' -docstring 'Toggle hidden files'
    map buffer normal D ':kiki-smart-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
    map buffer normal <a-c> ':kiki-smart-new-command<ret>' -docstring 'Insert kiki prefix into current or next empty line'
    map buffer insert <a-c> '<esc>:kiki-smart-new-command<ret>' -docstring 'Insert kiki prefix into current or next empty line'
    map buffer normal q ':kiki-smart-close<ret>' -docstring 'Close kiki buffer'
}

hook -group kiki global WinSetOption filetype=kiki %{
    kiki-set-modeline kiki-buffer
    map window normal <ret> ':kiki-smart-enter<ret>' -docstring 'Execute command in FIFO, open file/folder, or toggle tree'
    map window normal <c-o> ':kiki-smart-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map window normal O ':kiki-smart-open<ret>' -docstring 'Open topic if topic list, file tree if path, or fifo if command'
    map window normal <tab> ':kiki-smart-step-into<ret>' -docstring 'Execute command inline, open file/folder, step into tree, or rotate git file'
    map window normal <s-tab> ':kiki-smart-step-back<ret>' -docstring 'Step back in tree or rotate previous git file'
    map window normal p ':kiki-smart-preview<ret>' -docstring 'Open or replace buffer view in preview client'
    map window normal P ':kiki-smart-cd<ret>' -docstring 'Change directory to folder path or parent of file path'
    map window normal <c-l> ':kiki-smart-parent<ret>' -docstring 'Move to parent folder'
    map window normal r ':kiki-smart-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map window normal * ':kiki-smart-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map window normal <minus> ':kiki-smart-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map window normal . ':kiki-smart-dot<ret>' -docstring 'Toggle hidden files'
    map window normal D ':kiki-smart-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
    map window normal <a-c> ':kiki-smart-new-command<ret>' -docstring 'Insert kiki prefix into current or next empty line'
    map window insert <a-c> '<esc>:kiki-smart-new-command<ret>' -docstring 'Insert kiki prefix into current or next empty line'
    map window normal q ':kiki-smart-close<ret>' -docstring 'Close kiki buffer'
}

# Smart line dispatcher for kiki buffers:
define-command -override -hidden \
    kiki-smart-enter %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Topic list buffer (*kiki-topics-*)
            case "$kak_bufname" in
                \*kiki-topics-*)
                    if [ -n "$trimmed" ] && [ "$trimmed" != "Available kiki topics:" ]; then
                        printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                        exit 0
                    fi
                    ;;
            esac

            # 2. Topic header line (> topic) or explicit <name>.kiki
            if printf "%s\n" "$trimmed" | grep -Eq "^>[[:space:]]*[a-zA-Z0-9_.-]+"; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            if printf "%s\n" "$trimmed" | grep -Eq '^[a-zA-Z0-9_.-]+\.kiki$'; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            # 3. Prompt lines ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ]; then
                    printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                elif [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-edit }\n' "$eval_cmd"
                else
                    printf '%s %%{ kiki-fifo }\n' "$eval_cmd"
                fi
                exit 0
            fi

            # 4. Git status line (files, headers, hints, clean tree lines)
            case "$kak_bufname" in
                \*kiki-fifo-git*|\*kiki-fifo-*git*)
                    printf '%s %%{ kiki-git-line-action %%{%s} }\n' "$eval_cmd" "$trimmed"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq '^(modified:|new file:|deleted:|renamed:|both modified:)[[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^[MADRC?U ][MADRC?U ][[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|\(use "git|\(use git|## )'; then
                printf '%s %%{ kiki-git-line-action %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            # 5. Tree node (+ dir/ or - file) or filesystem path
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-open }\n' "$eval_cmd"
                exit 0
            elif printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                printf '%s %%{ kiki-tree-open }\n' "$eval_cmd"
                exit 0
            fi

            # 6. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            if [ -d "$uri_exp" ]; then
                printf '%s %%{ kiki-tree-open }\n' "$eval_cmd"
                exit 0
            elif [ -f "$uri_exp" ]; then
                printf '%s %%{ kiki-edit }\n' "$eval_cmd"
                exit 0
            fi

            # 7. Fallback: native Kakoune ret key
            printf '%s %%{ execute-keys <ret> }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-open %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Topic list buffer (*kiki-topics-*) or topic header line (> topic) or explicit <name>.kiki
            case "$kak_bufname" in
                \*kiki-topics-*)
                    if [ -n "$trimmed" ] && [ "$trimmed" != "Available kiki topics:" ]; then
                        printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                        exit 0
                    fi
                    ;;
            esac

            if printf "%s\n" "$trimmed" | grep -Eq "^>[[:space:]]*[a-zA-Z0-9_.-]+"; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            if printf "%s\n" "$trimmed" | grep -Eq '^[a-zA-Z0-9_.-]+\.kiki$'; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            # 2. Command prefix line ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                # Check if stripped line is an existing file or directory path
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ]; then
                    printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                elif [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-edit }\n' "$eval_cmd"
                else
                    printf '%s %%{ kiki-fifo }\n' "$eval_cmd"
                fi
                exit 0
            fi

            # 3. File or Folder / Tree node (+ dir/ or - file) or filesystem path
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                exit 0
            elif printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                exit 0
            fi

            # 4. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            if [ -d "$uri_exp" ] || [ -f "$uri_exp" ]; then
                printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                exit 0
            fi

            # 5. Fallback: native Kakoune O key
            printf '%s %%{ execute-keys O }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-tree-open %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-open"
            else
                target_cmd="execute-keys <c-o>"
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-step-into %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Topic list buffer (*kiki-topics-*)
            case "$kak_bufname" in
                \*kiki-topics-*)
                    if [ -n "$trimmed" ] && [ "$trimmed" != "Available kiki topics:" ]; then
                        printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                        exit 0
                    fi
                    ;;
            esac

            # 2. Topic header line (> topic) or explicit <name>.kiki
            if printf "%s\n" "$trimmed" | grep -Eq "^>[[:space:]]*[a-zA-Z0-9_.-]+"; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            if printf "%s\n" "$trimmed" | grep -Eq '^[a-zA-Z0-9_.-]+\.kiki$'; then
                printf '%s %%{ kiki-topic-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            # 3. Prompt lines ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ]; then
                    printf '%s %%{ kiki-file-tree }\n' "$eval_cmd"
                elif [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-edit }\n' "$eval_cmd"
                else
                    printf '%s %%{ kiki-inline }\n' "$eval_cmd"
                fi
                exit 0
            fi

            # 4. Git status buffer or git status lines -> rotate forward to next file
            case "$kak_bufname" in
                \*kiki-fifo-git*|\*kiki-fifo-*git*)
                    printf '%s %%{ kiki-git-rotate-file 1 }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq '^(modified:|new file:|deleted:|renamed:|both modified:)[[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^[MADRC?U ][MADRC?U ][[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|\(use "git|\(use git|## )'; then
                printf '%s %%{ kiki-git-rotate-file 1 }\n' "$eval_cmd"
                exit 0
            fi

            # 5. Tree node (+ dir/ or - file) or filesystem path
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-step-into }\n' "$eval_cmd"
                exit 0
            elif printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                printf '%s %%{ kiki-tree-step-into }\n' "$eval_cmd"
                exit 0
            fi

            # 6. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            if [ -d "$uri_exp" ]; then
                printf '%s %%{ kiki-tree-step-into }\n' "$eval_cmd"
                exit 0
            elif [ -f "$uri_exp" ]; then
                printf '%s %%{ kiki-edit }\n' "$eval_cmd"
                exit 0
            fi

            # 7. Fallback: native Kakoune tab key
            printf '%s %%{ execute-keys <tab> }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-step-back %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Git status buffer or git status lines -> rotate backward to previous file
            case "$kak_bufname" in
                \*kiki-fifo-git*|\*kiki-fifo-*git*)
                    printf '%s %%{ kiki-git-rotate-file -1 }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq '^(modified:|new file:|deleted:|renamed:|both modified:)[[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^[MADRC?U ][MADRC?U ][[:space:]]+' \
               || printf "%s\n" "$trimmed" | grep -Eq '^(On branch|Your branch|Changes to be committed:|Changes not staged|Untracked files:|Unmerged paths:|HEAD detached|rebase in progress|interactive rebase|no changes added|nothing to commit|nothing added to commit|\(use "git|\(use git|## )'; then
                printf '%s %%{ kiki-git-rotate-file -1 }\n' "$eval_cmd"
                exit 0
            fi

            # 2. Tree buffer or tree node lines -> step back / parent
            case "$kak_bufname" in
                \*kiki-file-tree\*|*.kikitree)
                    printf '%s %%{ kiki-tree-parent }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-parent }\n' "$eval_cmd"
                exit 0
            fi

            # 3. Fallback: native Kakoune s-tab key
            printf '%s %%{ execute-keys <s-tab> }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-preview %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Topic list buffer (*kiki-topics-*)
            case "$kak_bufname" in
                \*kiki-topics-*)
                    if [ -n "$trimmed" ] && [ "$trimmed" != "Available kiki topics:" ]; then
                        printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                        exit 0
                    fi
                    ;;
            esac

            # 2. Topic header line (> topic) or explicit <name>.kiki
            if printf "%s\n" "$trimmed" | grep -Eq "^>[[:space:]]*[a-zA-Z0-9_.-]+"; then
                printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            if printf "%s\n" "$trimmed" | grep -Eq '^[a-zA-Z0-9_.-]+\.kiki$'; then
                printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$trimmed"
                exit 0
            fi

            # 3. Tree buffer (*kiki-file-tree* / *.kikitree) or tree node lines (+ dir/ or - file)
            case "$kak_bufname" in
                \*kiki-file-tree\*|*.kikitree)
                    printf '%s %%{ kiki-tree-resolve-path kiki-preview-do }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-resolve-path kiki-preview-do }\n' "$eval_cmd"
                exit 0
            fi

            # 4. Prompt lines ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ] || [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                    exit 0
                fi
            fi

            # 5. Plain filesystem path on line (~/..., /..., ./..., ../...)
            if printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                p_clean=$(printf "%s\n" "$trimmed" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                exit 0
            fi

            # 6. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}' | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
            uri_path_only=$(printf "%s\n" "$uri" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            case "$uri_path_only" in
                "~"/*) uri_path_exp="${HOME}/${uri_path_only#"~"/}" ;;
                "~") uri_path_exp="${HOME}" ;;
                *) uri_exp="$uri_path_only" ;;
            esac
            if [ -d "$uri_exp" ] || [ -d "$uri_path_exp" ] || [ -f "$uri_exp" ] || [ -f "$uri_path_exp" ]; then
                printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "$uri"
                exit 0
            fi

            # 7. Check if it matches a topic name in topic directory
            if [ -n "$trimmed" ] && [ -n "$kak_opt_kiki_topics" ]; then
                topics_dir=$(eval echo "$kak_opt_kiki_topics")
                case "$topics_dir" in
                    "~"/*) topics_dir="${HOME}/${topics_dir#"~"/}" ;;
                    "~") topics_dir="${HOME}" ;;
                esac
                topics_dir="${topics_dir%/}/"
                topic_name=$(printf "%s\n" "$trimmed" | awk '{print $1}' | sed -e 's/\.kiki$//')
                if [ -f "${topics_dir}${topic_name}.kiki" ]; then
                    printf '%s %%{ kiki-preview-do %%{%s} }\n' "$eval_cmd" "${topics_dir}${topic_name}.kiki"
                    exit 0
                fi
            fi

            # 8. Fallback: native Kakoune p key (paste after)
            printf '%s %%{ execute-keys p }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-cd %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Tree buffer (*kiki-file-tree* / *.kikitree) or tree node lines (+ dir/ or - file)
            case "$kak_bufname" in
                \*kiki-file-tree\*|*.kikitree)
                    printf '%s %%{ kiki-tree-resolve-path kiki-cd-do }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-resolve-path kiki-cd-do }\n' "$eval_cmd"
                exit 0
            fi

            # 2. Prompt lines ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ] || [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-cd-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                    exit 0
                fi
            fi

            # 3. Plain filesystem path on line (~/..., /..., ./..., ../...)
            if printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                p_clean=$(printf "%s\n" "$trimmed" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                printf '%s %%{ kiki-cd-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                exit 0
            fi

            # 4. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}' | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
            uri_path_only=$(printf "%s\n" "$uri" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            case "$uri_path_only" in
                "~"/*) uri_path_exp="${HOME}/${uri_path_only#"~"/}" ;;
                "~") uri_path_exp="${HOME}" ;;
                *) uri_path_exp="$uri_path_only" ;;
            esac
            if [ -d "$uri_exp" ] || [ -d "$uri_path_exp" ] || [ -f "$uri_exp" ] || [ -f "$uri_path_exp" ]; then
                printf '%s %%{ kiki-cd-do %%{%s} }\n' "$eval_cmd" "$uri"
                exit 0
            fi

            # 5. Fallback: native Kakoune P key
            printf '%s %%{ execute-keys P }\n' "$eval_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-parent %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-parent"
            else
                target_cmd="execute-keys <c-l>"
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-refresh %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-refresh"
            else
                target_cmd="execute-keys r"
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-dot %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-toggle-hidden"
            else
                target_cmd="execute-keys ."
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-expand-recursive %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-expand-recursive"
            else
                target_cmd="execute-keys *"
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-narrow %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-narrow"
            else
                target_cmd="execute-keys <minus>"
            fi
            printf '%s %%{ %s }\n' "$eval_cmd" "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-drop-to-shell %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            # 1. Tree buffer (*kiki-file-tree* / *.kikitree) or tree node lines (+ dir/ or - file)
            case "$kak_bufname" in
                \*kiki-file-tree\*|*.kikitree)
                    printf '%s %%{ kiki-tree-drop-to-shell }\n' "$eval_cmd"
                    exit 0
                    ;;
            esac
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                printf '%s %%{ kiki-tree-drop-to-shell }\n' "$eval_cmd"
                exit 0
            fi

            # 2. Prompt lines ($ ...)
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                stripped="${trimmed#"$kak_opt_kiki_prefix"}"
            elif printf "%s\n" "$trimmed" | grep -Eq '^\$[[:space:]]'; then
                stripped="${trimmed#\$ }"
            else
                stripped=""
            fi

            if [ -n "$stripped" ]; then
                p_check=$(printf "%s\n" "$stripped" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                p_clean=$(printf "%s\n" "$p_check" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                p_path_only=$(printf "%s\n" "$p_clean" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
                case "$p_clean" in
                    "~"/*) p_exp="${HOME}/${p_clean#"~"/}" ;;
                    "~") p_exp="${HOME}" ;;
                    *) p_exp="$p_clean" ;;
                esac
                case "$p_path_only" in
                    "~"/*) p_path_exp="${HOME}/${p_path_only#"~"/}" ;;
                    "~") p_path_exp="${HOME}" ;;
                    *) p_path_exp="$p_path_only" ;;
                esac

                if [ -d "$p_exp" ] || [ -d "$p_path_exp" ] || [ -f "$p_exp" ] || [ -f "$p_path_exp" ]; then
                    printf '%s %%{ kiki-drop-to-shell-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                else
                    printf '%s %%{ kiki-shell-do %%{%s} }\n' "$eval_cmd" "$stripped"
                fi
                exit 0
            fi

            # 3. Plain filesystem path on line (~/..., /..., ./..., ../...)
            if printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                p_clean=$(printf "%s\n" "$trimmed" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
                printf '%s %%{ kiki-drop-to-shell-do %%{%s} }\n' "$eval_cmd" "$p_clean"
                exit 0
            fi

            # 4. Check if current word/URI is an existing path
            uri=$(printf "%s\n" "$trimmed" | awk '{print $1}' | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
            uri_path_only=$(printf "%s\n" "$uri" | sed -e 's/:[0-9]\+:[0-9]\+.*$//' -e 's/:[0-9]\+.*$//' -e 's/:$//')
            case "$uri" in
                "~"/*) uri_exp="${HOME}/${uri#"~"/}" ;;
                "~") uri_exp="${HOME}" ;;
                *) uri_exp="$uri" ;;
            esac
            case "$uri_path_only" in
                "~"/*) uri_path_exp="${HOME}/${uri_path_only#"~"/}" ;;
                "~") uri_path_exp="${HOME}" ;;
                *) uri_exp="$uri_path_only" ;;
            esac
            if [ -d "$uri_exp" ] || [ -d "$uri_path_exp" ] || [ -f "$uri_exp" ] || [ -f "$uri_path_exp" ]; then
                printf '%s %%{ kiki-drop-to-shell-do %%{%s} }\n' "$eval_cmd" "$uri"
                exit 0
            fi

            # 5. Fallback: run shell in current $PWD
            printf '%s %%{ kiki-shell }\n' "$eval_cmd"
        }
    }}

# Smart close: for scratch/tree buffers, delete without prompt; for files, standard q
define-command -override -hidden \
    kiki-smart-close %{ evaluate-commands %sh{
        case "$kak_bufname" in
            \*kiki-*) printf 'delete-buffer\n' ;;
            *.kikitree) printf 'delete-buffer\n' ;;
            *) printf 'execute-keys q\n' ;;
        esac
    }}

# Open disposable quick scratchpad (*kiki-scratchpad-<timestamp>*)
define-command -override -docstring "kiki-scratchpad: open a disposable scratchpad buffer supporting all kiki commands" \
    kiki-scratchpad %{
        evaluate-commands %sh{
            timestamp=$(date +%s%N | cut -b1-13)
            bufname="*kiki-scratchpad-${timestamp}*"
            printf 'edit -scratch %s\n' "$bufname"
            printf 'set-option buffer kiki_buffer_type kiki-buffer\n'
            printf 'set-option buffer filetype kiki\n'
            printf 'kiki-set-modeline kiki-buffer\n'
        }
    }

# Helper to close kiki buffers by matching buffer pattern or type
define-command -override -hidden -params 0..1 \
    kiki-close-buffers-matching %{ evaluate-commands %sh{
        match_type="$1"
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    b_name="$kak_bufname"
                    is_kiki_type=0
                    if [ "$kak_opt_kiki_buffer_type" = "kiki-buffer" ] || [ -n "$kak_opt_kiki_buffer_type" ]; then
                        is_kiki_type=1
                    fi
                    is_preview=0
                    if [ "$kak_opt_kiki_is_preview" = "true" ]; then
                        is_preview=1
                    fi

                    case "%s" in
                        preview)
                            if [ "$is_preview" -eq 1 ]; then
                                printf "delete-buffer\n"
                            else
                                case "$b_name" in
                                    \*kiki-preview\*|*kiki-preview*) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        fifo)
                            if [ "$is_kiki_type" -eq 1 ]; then
                                case "$b_name" in
                                    \*kiki-fifo-*) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        topics)
                            if [ "$is_kiki_type" -eq 1 ]; then
                                case "$b_name" in
                                    \*kiki-topics-*) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        tree)
                            if [ "$is_kiki_type" -eq 1 ]; then
                                case "$b_name" in
                                    \*kiki-file-tree\*|*.kikitree) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        scratchpad|scratch)
                            if [ "$is_kiki_type" -eq 1 ]; then
                                case "$b_name" in
                                    \*kiki-scratchpad-*|*scratchpad.kiki|\*kiki-scratch\*) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        file)
                            if [ "$is_kiki_type" -eq 1 ]; then
                                case "$b_name" in
                                    *.kiki) printf "delete-buffer\n" ;;
                                esac
                            fi
                            ;;
                        *)
                            if [ "$is_kiki_type" -eq 1 ] || [ "$is_preview" -eq 1 ]; then
                                printf "delete-buffer\n"
                            fi
                            ;;
                    esac
                }
            } }\n' "$buffer" "$match_type"
        done
    }}

# Close all kiki buffers
define-command -override -docstring "kiki-close-all-buffers: close all kiki-managed buffers" \
    kiki-close-all-buffers %{
        evaluate-commands %sh{
            for c in $kak_client_list; do
                if [ "$c" = "preview" ]; then
                    printf 'try %%{ evaluate-commands -client preview %%{ edit -scratch *scratch* } }\n'
                    break
                fi
            done
        }
        kiki-close-buffers-matching
    }

# Close fifo buffers
define-command -override -docstring "kiki-close-fifo-buffers: close all kiki fifo buffers" \
    kiki-close-fifo-buffers %{
        kiki-close-buffers-matching fifo
    }

# Close topics buffers
define-command -override -docstring "kiki-close-topics-buffers: close all kiki topics buffers" \
    kiki-close-topics-buffers %{
        kiki-close-buffers-matching topics
    }

# Close file tree buffers
define-command -override -docstring "kiki-close-tree-buffers: close all kiki file tree buffers" \
    kiki-close-tree-buffers %{
        kiki-close-buffers-matching tree
    }

# Close scratchpad buffers
define-command -override -docstring "kiki-close-scratchpad-buffers: close all kiki scratchpad buffers" \
    kiki-close-scratchpad-buffers %{
        kiki-close-buffers-matching scratchpad
    }

# Close scratch buffers
define-command -override -docstring "kiki-close-scratch-buffers: close all kiki scratch buffers" \
    kiki-close-scratch-buffers %{
        kiki-close-buffers-matching scratch
    }

# Close preview buffers
define-command -override -docstring "kiki-close-preview-buffers: close all kiki preview buffers" \
    kiki-close-preview-buffers %{
        evaluate-commands %sh{
            for c in $kak_client_list; do
                if [ "$c" = "preview" ]; then
                    printf 'try %%{ evaluate-commands -client preview %%{ edit -scratch *scratch* } }\n'
                    break
                fi
            done
        }
        kiki-close-buffers-matching preview
    }

# Close kiki file buffers
define-command -override -docstring "kiki-close-file-buffers: close all kiki file buffers" \
    kiki-close-file-buffers %{
        kiki-close-buffers-matching file
    }

# Insert prefix on current line (if empty) or next available empty line below, and enter insert mode
define-command -override -docstring "kiki-smart-new-command: insert kiki_prefix on empty line or next available empty line" \
    kiki-smart-new-command %{ evaluate-commands -draft -save-regs '"a' %{
        set-register a %val{cursor_line}
        execute-keys '<percent>'
        evaluate-commands %sh{
            cur_line="$kak_reg_a"
            prefix="$kak_opt_kiki_prefix"
            [ -z "$prefix" ] && prefix='$ '
            eval_cmd="evaluate-commands"
            [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

            target_line=$(printf '%s\n' "$kak_selection" | awk -v cur="$cur_line" '
                NR == cur && /^[[:space:]]*$/ { print NR; exit }
                NR > cur && /^[[:space:]]*$/ { print NR; exit }
            ')

            if [ -n "$target_line" ]; then
                printf "%s %%{ select %s.1,%s.1; try %%{ execute-keys '<esc>xs\h+<ret>d' }; execute-keys 'i%s' }\n" "$eval_cmd" "$target_line" "$target_line" "$prefix"
            else
                printf "%s %%{ select %s.1,%s.1; execute-keys 'o%s' }\n" "$eval_cmd" "$cur_line" "$prefix"
            fi
        }
    }}
