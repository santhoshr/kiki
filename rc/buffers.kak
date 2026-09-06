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
    map buffer normal <c-o> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map buffer normal <tab> ':kiki-tree-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map buffer normal <c-l> ':kiki-tree-parent<ret>' -docstring 'Move to parent folder'
    map buffer normal r ':kiki-tree-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map buffer normal * ':kiki-tree-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map buffer normal <minus> ':kiki-tree-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map buffer normal . ':kiki-tree-toggle-hidden<ret>' -docstring 'Toggle hidden files'
    map buffer normal D ':kiki-tree-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
}

hook -group kiki global WinSetOption filetype=kiki %{
    kiki-set-modeline kiki
    map window normal <ret> ':kiki-smart-enter<ret>' -docstring 'Execute command on command line, or expand/collapse on tree line'
    map window normal <c-o> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map window normal <tab> ':kiki-tree-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map window normal <c-l> ':kiki-tree-parent<ret>' -docstring 'Move to parent folder'
    map window normal r ':kiki-tree-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map window normal * ':kiki-tree-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map window normal <minus> ':kiki-tree-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map window normal . ':kiki-tree-toggle-hidden<ret>' -docstring 'Toggle hidden files'
    map window normal D ':kiki-tree-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
}

# Smart Enter dispatcher for kiki buffers:
# If line starts with '$ ' (or configured prefix): execute inline
# If line starts with '+ ' or '- ' or is a directory path: expand/collapse tree in-place
# Otherwise: perform default Kakoune Enter behavior
define-command -override -hidden \
    kiki-smart-enter %{ evaluate-commands %sh{
        prefix="$kak_opt_kiki_prefix"
        line_content="$kak_selection"
        # Check if selection / current line is a command or tree node
        printf 'evaluate-commands -draft %%{
            execute-keys "<esc>x"
            evaluate-commands %%sh{
                trimmed=$(printf "%%s\\n" "$kak_selection" | sed -e "s/^[[:space:]]*//")
                if [ -n "$kak_opt_kiki_prefix" ] && [ "${trimmed#"$kak_opt_kiki_prefix"}" != "$trimmed" ]; then
                    printf "kiki-inline\\n"
                elif printf "%%s\\n" "$trimmed" | grep -Eq "^[+-] "; then
                    printf "kiki-tree-open\\n"
                elif printf "%%s\\n" "$trimmed" | grep -Eq "^(~|/|\./).*/[[:space:]]*$"; then
                    printf "kiki-tree-open\\n"
                else
                    printf "execute-keys <ret>\\n"
                fi
            }
        }\n'
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
