# Kiki Buffer Lifecycle & Management

# Set buffer type for .kiki files
hook -group kiki global BufOpenFile .*\.kiki$ %{
    set-option buffer kiki_buffer_type file
    set-option buffer filetype kiki
}

hook -group kiki global BufCreate \*kiki-scratchpad.*\* %{
    set-option buffer kiki_buffer_type scratchpad
    set-option buffer filetype kiki
}

hook -group kiki global BufSetOption filetype=kiki %{
    map buffer normal <ret> ':kiki-smart-enter<ret>' -docstring 'Execute command on command line, or expand/collapse on tree line'
    map buffer normal <c-o> ':kiki-smart-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map buffer normal <tab> ':kiki-smart-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map buffer normal <c-l> ':kiki-smart-parent<ret>' -docstring 'Move to parent folder'
    map buffer normal r ':kiki-smart-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map buffer normal * ':kiki-smart-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map buffer normal <minus> ':kiki-smart-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map buffer normal . ':kiki-smart-dot<ret>' -docstring 'Toggle hidden files'
    map buffer normal D ':kiki-smart-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
}

hook -group kiki global WinSetOption filetype=kiki %{
    kiki-set-modeline kiki
    map window normal <ret> ':kiki-smart-enter<ret>' -docstring 'Execute command on command line, or expand/collapse on tree line'
    map window normal <c-o> ':kiki-smart-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map window normal <tab> ':kiki-smart-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map window normal <c-l> ':kiki-smart-parent<ret>' -docstring 'Move to parent folder'
    map window normal r ':kiki-smart-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map window normal * ':kiki-smart-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map window normal <minus> ':kiki-smart-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map window normal . ':kiki-smart-dot<ret>' -docstring 'Toggle hidden files'
    map window normal D ':kiki-smart-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
}

# Smart line dispatcher for kiki buffers:
define-command -override -hidden \
    kiki-smart-enter %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                target_cmd="kiki-inline"
            elif printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]"; then
                target_cmd="kiki-tree-open"
            elif printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-open"
            else
                target_cmd="execute-keys <ret>"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-tree-open %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-open"
            else
                target_cmd="execute-keys <c-o>"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-step-into %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-step-into"
            else
                target_cmd="execute-keys <tab>"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-parent %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-parent"
            else
                target_cmd="execute-keys <c-l>"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-refresh %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-refresh"
            else
                target_cmd="execute-keys r"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-dot %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-toggle-hidden"
            else
                target_cmd="execute-keys ."
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-expand-recursive %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-expand-recursive"
            else
                target_cmd="execute-keys *"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-narrow %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-narrow"
            else
                target_cmd="execute-keys <minus>"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

define-command -override -hidden \
    kiki-smart-drop-to-shell %{ evaluate-commands -draft %{
        execute-keys "<esc>x"
        evaluate-commands %sh{
            trimmed=$(printf "%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
            if printf "%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || printf "%s\n" "$trimmed" | grep -Eq "^(~|/|\.|\.\.)"; then
                target_cmd="kiki-tree-drop-to-shell"
            else
                target_cmd="execute-keys D"
            fi
            printf 'evaluate-commands -client %%val{client} %s\n' "$target_cmd"
        }
    }}

# Open disposable quick scratchpad (*kiki-scratchpad-<timestamp>*)
define-command -override -docstring "kiki-scratchpad: open a disposable scratchpad buffer supporting all kiki commands" \
    kiki-scratchpad %{
        evaluate-commands %sh{
            timestamp=$(date +%s%N | cut -b1-13)
            bufname="*kiki-scratchpad-${timestamp}*"
            printf 'edit -scratch %s\n' "$bufname"
            printf 'set-option buffer kiki_buffer_type scratchpad\n'
            printf 'set-option buffer filetype kiki\n'
            printf 'kiki-set-modeline kiki\n'
        }
    }

# Helper to close kiki buffers by matching buffer type
define-command -override -hidden -params 0..1 \
    kiki-close-buffers-matching %{ evaluate-commands %sh{
        match_type="$1"
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    if [ -z "%s" ] && [ -n "$kak_opt_kiki_buffer_type" ]; then
                        printf "delete-buffer\n"
                    elif [ "$kak_opt_kiki_buffer_type" = "%s" ]; then
                        printf "delete-buffer\n"
                    fi
                }
            } }\n' "$buffer" "$match_type" "$match_type"
        done
    }}

# Close all kiki buffers
define-command -override -docstring "kiki-close-all-buffers: close all kiki-managed buffers" \
    kiki-close-all-buffers %{
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

# Close kiki file buffers
define-command -override -docstring "kiki-close-file-buffers: close all kiki file buffers" \
    kiki-close-file-buffers %{
        kiki-close-buffers-matching file
    }
