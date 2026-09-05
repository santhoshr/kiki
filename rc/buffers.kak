# Kiki Buffer Lifecycle & Management

# Set buffer type for .kiki files
hook -group kiki global BufOpenFile .*\.kiki$ %{
    set-option buffer kiki_buffer_type file
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

# Close kiki file buffers
define-command -override -docstring "kiki-close-file-buffers: close all kiki file buffers" \
    kiki-close-file-buffers %{
        kiki-close-buffers-matching file
    }
