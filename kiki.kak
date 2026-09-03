# Kiki
#   Alexander Maricich 2019

##
# User modes
# ----------
try %{ declare-user-mode kiki }
try %{ declare-user-mode kiki-delete }

##
# Options
# -------
declare-option str kiki_prefix "$ "
declare-option -docstring "Directory containing kiki topic files" str kiki_topics "~/.config/kak/kiki/"
declare-option str kiki_buffer_type ""

# Set buffer type for .kiki files
hook -group kiki global BufOpenFile .*\.kiki$ %{
    set-option buffer kiki_buffer_type file
}

##
# Commands
# --------

# Sudo authentication callback.
define-command -override -hidden -params 2 \
    kiki-sudo-auth-and-run %{ evaluate-commands %sh{
        action="$1"
        cmd="$2"
        printf '%s\n' "$kak_text" | sudo -S -v -p "" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            printf '%s %%{%s}\n' "$action" "$cmd"
        else
            printf 'echo -markup "{Error}kiki: incorrect sudo password"\n'
        fi
    }}

# Sudo check and password prompt helper.
define-command -override -hidden -params 2 \
    kiki-check-sudo %{ evaluate-commands %sh{
        action="$1"
        cmd="$2"
        # Check if command contains sudo
        if printf '%s\n' "$cmd" | grep -Eq '(^|[;&|[:space:]])sudo([[:space:]]|$)'; then
            if ! sudo -n true >/dev/null 2>&1; then
                printf 'prompt -password "Password:" %%{ kiki-sudo-auth-and-run %%{%s} %%{%s} }\n' "$action" "$cmd"
                exit 0
            fi
        fi
        printf '%s %%{%s}\n' "$action" "$cmd"
    }}

# Execute command and return inline below current line.
define-command -override -params .. \
    -docstring "kiki-inline [<arguments>]: execute bash command and insert output below current line" \
    kiki-inline %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-check-sudo kiki-inline-do %%{%s}\n' "$*"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-check-sudo kiki-inline-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: extract command after prefix on current line
            printf 'try %%{
                kiki-select
                kiki-check-sudo kiki-inline-do %%val{selection}
            } catch %%{
                evaluate-commands %%{
                    execute-keys "<esc>x"
                    kiki-check-sudo kiki-inline-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-inline-do %{ evaluate-commands %sh{
        cmd="$1"
        # Strip leading/trailing whitespace and optional $ prefix
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$cmd" ]; then
            printf 'echo -markup "{Error}kiki-inline: no command specified"\n'
            exit 0
        fi

        tmp_out=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-inline.XXXXXXXX)
        ( eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null

        if [ -s "$tmp_out" ]; then
            start_line="$kak_cursor_line"
            first_line=$(( start_line + 1 ))
            num_lines=$(wc -l < "$tmp_out")
            [ "$num_lines" -eq 0 ] && num_lines=1
            last_line=$(( first_line + num_lines - 1 ))

            printf 'execute-keys %%{o<esc>!cat %s<ret>}\n' "$tmp_out"
            printf 'select %s.1,%s.99999999\n' "$first_line" "$last_line"
        fi
        printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_out"
    }}


# Execute command and return in scratch buffer.
define-command -override -params .. \
    -docstring "kiki-scratch [<arguments>]: execute bash command and return output in scratch buffer" \
    kiki-scratch %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-check-sudo kiki-scratch-do %%{%s}\n' "$*"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-check-sudo kiki-scratch-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: extract command after prefix on current line
            printf 'try %%{
                kiki-select
                kiki-check-sudo kiki-scratch-do %%val{selection}
            } catch %%{
                evaluate-commands %%{
                    execute-keys "<esc>x"
                    kiki-check-sudo kiki-scratch-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-scratch-do %{ evaluate-commands %sh{
        cmd="$1"
        # Strip leading/trailing whitespace and optional $ prefix
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$cmd" ]; then
            printf 'echo -markup "{Error}kiki-scratch: no command specified"\n'
            exit 0
        fi

        tmp_out=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-scratch.XXXXXXXX)
        ( eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null

        printf 'edit -scratch *kiki-scratch*\n'
        printf 'set-option buffer filetype bash\n'
        printf 'set-option buffer kiki_buffer_type scratch\n'
        printf 'try %%{ set-option window modelinefmt "%%val{bufname} %%val{cursor_line}:%%val{cursor_char_column} {{context_info}} %%{cyan}[kiki:scratch]%%{default} {{mode_info}} - %%val{client}@[%%val{session}]" %%}\n'
        printf 'execute-keys -draft %%{<percent>d!cat "%s"<ret>}\n' "$tmp_out"
        printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_out"
    }}


# Pipe to fifo.
define-command -override -params .. \
    -docstring "kiki-fifo [<arguments>]: execute bash command to fifo
Executes a bash command and prints the output in a new fifo buffer" \
    kiki-fifo %{
        evaluate-commands %sh{
            if [ $# -ge 1 ]; then
                printf 'kiki-check-sudo kiki-fifo-do %%{%s}\n' "$*"
                exit 0
            fi
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-check-sudo kiki-fifo-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            printf 'try %%{
                kiki-select
                kiki-check-sudo kiki-fifo-do %%val{selection}
            } catch %%{
                evaluate-commands %%{
                    execute-keys "<esc>x"
                    kiki-check-sudo kiki-fifo-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-fifo-do %{ evaluate-commands %sh{
        cmd="$1"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$cmd" ]; then
            printf 'echo -markup "{Error}kiki-fifo: no command specified"\n'
            exit 0
        fi

        output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-make.XXXXXXXX)/fifo
        mkfifo "${output}"
        ( eval "$cmd" > "${output}" 2>&1 ) > /dev/null 2>&1 < /dev/null &

        cmd_name=$(printf '%s' "$cmd" | awk '{print $1}' | tr '/' '-' | tr ' ' '-')
        timestamp=$(date +%H%M%S)
        buffer_name="*kiki-fifo-${cmd_name}-${timestamp}*"

        printf %s\\n "evaluate-commands -try-client '$kak_opt_toolsclient' %{
            edit! -fifo ${output} -scroll ${buffer_name}
            set-option buffer filetype bash
            set-option buffer kiki_buffer_type fifo
            try %{ set-option window modelinefmt \"%val{bufname} %val{cursor_line}:%val{cursor_char_column} {{context_info}} %{cyan}[kiki:fifo]%{default} {{mode_info}} - %val{client}@[%val{session}]\" }
            hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r $(dirname ${output}) } }
        }"
    }}


# Background execution.
define-command -override -params .. \
    -docstring "kiki-background [<arguments>]: execute bash command in the background" \
    kiki-background %{
        evaluate-commands %sh{
            if [ $# -ge 1 ]; then
                printf 'kiki-check-sudo kiki-background-do %%{%s}\n' "$*"
                exit 0
            fi
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-check-sudo kiki-background-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            printf 'try %%{
                kiki-select
                kiki-check-sudo kiki-background-do %%val{selection}
            } catch %%{
                evaluate-commands %%{
                    execute-keys "<esc>x"
                    kiki-check-sudo kiki-background-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-background-do %{ evaluate-commands %sh{
        cmd="$1"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$cmd" ]; then
            printf 'echo -markup "{Error}kiki-background: no command specified"\n'
            exit 0
        fi

        ( eval "$cmd" ) > /dev/null 2>&1 < /dev/null &
        pid=$!
        escaped_cmd=$(printf '%s' "$cmd" | sed "s/'/''/g")
        printf "echo -debug 'KIKI: Background command started [PID %s]: %s'\n" "$pid" "$escaped_cmd"
        printf "echo 'kiki: started background job [PID %s]: %s'\n" "$pid" "$escaped_cmd"
    }}


# Terminal shell execution.
define-command -override -params .. \
    -docstring "kiki-shell [<arguments>]: execute bash command in terminal shell with current directory" \
    kiki-shell %{
        evaluate-commands %sh{
            if [ $# -ge 1 ]; then
                printf 'kiki-check-sudo kiki-shell-do %%{%s}\n' "$*"
                exit 0
            fi
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-check-sudo kiki-shell-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            printf 'try %%{
                kiki-select
                kiki-check-sudo kiki-shell-do %%val{selection}
            } catch %%{
                evaluate-commands %%{
                    execute-keys "<esc>x"
                    kiki-check-sudo kiki-shell-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-shell-do %{ evaluate-commands %sh{
        cmd="$1"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        tmp_script=$(mktemp "${TMPDIR:-/tmp}"/kiki-shell.XXXXXXXX)
        chmod +x "$tmp_script"

        if [ -z "$cmd" ]; then
            cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
cd "$PWD" || exit 1
exec "\${SHELL:-sh}"
EOF
        else
            cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
cd "$PWD" || exit 1
$cmd
printf "\n[Process exited. Press Enter to continue]\n"
read -r _ </dev/tty
EOF
        fi

        printf 'terminal "%s"\n' "$tmp_script"
    }}

# Selection after prefix.
define-command -override -docstring "kiki-select: select all text after kiki" \
    kiki-select %{
        execute-keys "<esc>xs\$ .+<ret>"
        execute-keys "s(?<=\$ ).+"
        execute-keys '<ret>H'
}

# Select URI / path on line.
define-command -override -docstring "kiki-uri-select: select a uri/path on the current line" \
    kiki-uri-select %{
        execute-keys "<esc>xs(~/[^\s:]*|/[^\s:]+|\./[^\s:]+|[a-zA-Z0-9_.-]+/[^\s:]+|[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_-]+)(:[0-9]+)*\b<ret>"
}

# Open topic file.
define-command -override -params 0..1 \
    -docstring "kiki-topic [<name>]: open a topic file with the given name" \
    kiki-topic %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-topic-do %%{%s}\n' "$1"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-topic-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: select line and pass to kiki-topic-do
            printf 'evaluate-commands %%{
                execute-keys "<esc>x"
                kiki-topic-do %%val{selection}
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-topic-do %{ evaluate-commands %sh{
        raw="$1"
        topic_raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*\$[[:space:]]*//' -e 's/^[[:space:]]*//' | awk '{print $1}')
        topic_name=$(basename "$topic_raw" .kiki)
        if [ -n "$topic_name" ] && [ "$topic_name" != "$" ]; then
            printf 'execute-keys %%{;}\n'
            printf 'edit "%s%s.kiki"\n' "$kak_opt_kiki_topics" "$topic_name"
        else
            printf 'execute-keys %%{;}\n'
            printf 'echo -markup "{Error}kiki-topic: no topic name found on line"\n'
        fi
    }}


# Change directory to path.
define-command -override -params 0..1 \
    -docstring "kiki-cd [<path>]: change directory to path from argument, selected text, or line with prefix/URI" \
    kiki-cd %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-cd-do %%{%s}\n' "$1"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-cd-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: select line and pass to kiki-cd-do
            printf 'evaluate-commands %%{
                execute-keys "<esc>x"
                kiki-cd-do %%val{selection}
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-cd-do %{ evaluate-commands %sh{
        raw="$1"
        # Strip leading/trailing whitespace and optional $ prefix
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # Expand ~
        case "$raw" in
            "~"/*) path="${HOME}/${raw#"~"/}" ;;
            "~") path="${HOME}" ;;
            *) path="$raw" ;;
        esac

        if [ -z "$path" ]; then
            printf 'echo -markup "{Error}kiki-cd: no path found on line"\n'
            exit 0
        fi

        printf 'execute-keys %%{;}\n'

        if [ -d "$path" ]; then
            printf 'change-directory %%{%s}\n' "$path"
            printf 'echo "kiki: changed directory to %s"\n' "$path"
        elif [ -f "$path" ]; then
            dir=$(dirname "$path")
            printf 'change-directory %%{%s}\n' "$dir"
            printf 'echo "kiki: changed directory to %s"\n' "$dir"
        else
            printf 'change-directory %%{%s}\n' "$path"
        fi
    }}

# Edit file at path.
define-command -override -params 0..1 \
    -docstring "kiki-edit [<path>]: open file from argument, selected text, or WORD under cursor" \
    kiki-edit %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-edit-do %%{%s}\n' "$1"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-edit-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: select current WORD (<a-i><a-w>) under cursor
            printf 'evaluate-commands %%{
                execute-keys "<a-i><a-w>"
                kiki-edit-do %%val{selection}
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-edit-do %{ evaluate-commands %sh{
        raw="$1"
        # Strip leading/trailing whitespace and optional $ prefix
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Strip quotes, parens, backticks
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
        # Strip trailing colon or grep output suffix (e.g. "file:123: match...")
        raw=$(printf '%s\n' "$raw" | sed -e 's/:[[:space:]].*$//' -e 's/:$//')

        line=""
        col=""
        path=""

        # Extract file:line:col:text or file:line:text or file:line
        part1=$(printf '%s\n' "$raw" | cut -d: -f1)
        part2=$(printf '%s\n' "$raw" | cut -d: -f2)
        part3=$(printf '%s\n' "$raw" | cut -d: -f3)

        if [ -n "$part1" ] && [ -n "$part2" ] && [ "$part2" -eq "$part2" ] 2>/dev/null; then
            path="$part1"
            line="$part2"
            if [ -n "$part3" ] && [ "$part3" -eq "$part3" ] 2>/dev/null; then
                col="$part3"
            fi
        else
            path="$raw"
        fi

        # Expand ~
        case "$path" in
            "~"/*) path="${HOME}/${path#"~"/}" ;;
            "~") path="${HOME}" ;;
        esac

        # If path does not exist directly, check if it is a topic file in kiki_topics
        if [ ! -e "$path" ] && [ -n "$kak_opt_kiki_topics" ]; then
            topics_dir=$(eval echo "$kak_opt_kiki_topics")
            case "$topics_dir" in
                "~"/*) topics_dir="${HOME}/${topics_dir#"~"/}" ;;
                "~") topics_dir="${HOME}" ;;
            esac
            topics_dir="${topics_dir%/}/"
            if [ -f "${topics_dir}${path}.kiki" ]; then
                path="${topics_dir}${path}.kiki"
            elif [ -f "${topics_dir}${path}" ]; then
                path="${topics_dir}${path}"
            fi
        fi

        if [ -z "$path" ]; then
            printf 'echo -markup "{Error}kiki-edit: no file path found on line"\n'
            exit 0
        fi

        printf 'execute-keys %%{;}\n'

        if [ -n "$line" ] && [ -n "$col" ]; then
            printf 'edit %%{%s} %s %s\n' "$path" "$line" "$col"
        elif [ -n "$line" ]; then
            printf 'edit %%{%s} %s\n' "$path" "$line"
        else
            printf 'edit %%{%s}\n' "$path"
        fi
    }}

# List path contents.
define-command -override -params 0..1 \
    -docstring "kiki-ls [<path>]: ls -alh on argument, selection, or URI on current line" \
    kiki-ls %{
        evaluate-commands %sh{
            # 1. Explicit argument provided
            if [ $# -ge 1 ]; then
                printf 'kiki-ls-do %%{%s}\n' "$1"
                exit 0
            fi
            # 2. Active multi-character selection
            trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ "${#trimmed_sel}" -gt 1 ]; then
                printf 'kiki-ls-do %%{%s}\n' "$trimmed_sel"
                exit 0
            fi
            # 3. No selection: try kiki-uri-select or select line and pass to kiki-ls-do
            printf 'evaluate-commands %%{
                try %%{
                    kiki-uri-select
                    kiki-ls-do %%val{selection}
                } catch %%{
                    execute-keys "<esc>x"
                    kiki-ls-do %%val{selection}
                }
            }\n'
        }
    }

define-command -override -hidden -params 1 \
    kiki-ls-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Strip trailing :line:col
        raw=$(printf '%s\n' "$raw" | sed -e 's/:[0-9]\+:[0-9]\+$//' -e 's/:[0-9]\+$//' -e 's/:$//')

        # Expand ~
        case "$raw" in
            "~"/*) path="${HOME}/${raw#"~"/}" ;;
            "~") path="${HOME}" ;;
            *) path="$raw" ;;
        esac

        if [ -z "$path" ]; then
            printf 'echo -markup "{Error}kiki-ls: no path found on line"\n'
            exit 0
        fi

        escaped_path=$(printf '%s' "$path" | sed 's/"/\\"/g')
        printf 'execute-keys %%{;o<esc>!ls -alh "%s"<ret>}\n' "$escaped_path"
    }}

# List available topic files.
define-command -override -docstring "kiki-list-topics: list all available topic files" \
    kiki-list-topics %{ evaluate-commands %sh{
        topics_dir=$(eval echo "$kak_opt_kiki_topics")
        if [ -d "$topics_dir" ]; then
            timestamp=$(date +%H%M%S)
            buffer_name="*kiki-topics-${timestamp}*"
            printf 'edit -scratch %s\n' "$buffer_name"
            printf 'set-option buffer kiki_buffer_type topics\n'
            printf 'try %%{ set-option window modelinefmt "%%val{bufname} %%val{cursor_line}:%%val{cursor_char_column} {{context_info}} %%{cyan}[kiki:topics]%%{default} {{mode_info}} - %%val{client}@[%%val{session}]" %%}\n'
            printf 'execute-keys "i"\n'
            printf 'execute-keys "Available kiki topics:\n\n"\n'
            for file in "$topics_dir"*.kiki; do
                if [ -f "$file" ]; then
                    basename=$(basename "$file" .kiki)
                    printf 'execute-keys "%s%s\n"\n' "$kak_opt_kiki_prefix" "$basename"
                fi
            done
            printf 'execute-keys "<esc>"\n'
        else
            printf 'echo "Topics directory does not exist: %s"\n' "$topics_dir"
        fi
    }}

# Close all kiki buffers.
define-command -override -docstring "kiki-close-all-buffers: close all kiki-managed buffers" \
    kiki-close-all-buffers %{ evaluate-commands %sh{
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    [ -n "$kak_opt_kiki_buffer_type" ] && printf "delete-buffer\n"
                }
            } }\n' "$buffer"
        done
    }}

# Close fifo buffers.
define-command -override -docstring "kiki-close-fifo-buffers: close all kiki fifo buffers" \
    kiki-close-fifo-buffers %{ evaluate-commands %sh{
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    [ "$kak_opt_kiki_buffer_type" = "fifo" ] && printf "delete-buffer\n"
                }
            } }\n' "$buffer"
        done
    }}

# Close topics buffers.
define-command -override -docstring "kiki-close-topics-buffers: close all kiki topics buffers" \
    kiki-close-topics-buffers %{ evaluate-commands %sh{
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    [ "$kak_opt_kiki_buffer_type" = "topics" ] && printf "delete-buffer\n"
                }
            } }\n' "$buffer"
        done
    }}

# Close kiki file buffers.
define-command -override -docstring "kiki-close-file-buffers: close all kiki file buffers" \
    kiki-close-file-buffers %{ evaluate-commands %sh{
        eval "set -- $kak_quoted_buflist"
        for buffer do
            printf 'try %%{ evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    [ "$kak_opt_kiki_buffer_type" = "file" ] && printf "delete-buffer\n"
                }
            } }\n' "$buffer"
        done
    }}

##
# Shortcuts
# ---------

# Prefix shortcuts.
map global kiki c "i%opt{kiki_prefix}<esc>" -docstring 'Insert kiki_prefix at cursor position.'
map global kiki C "<esc>I%opt{kiki_prefix}<esc>" -docstring 'Prefix the current line with kiki_prefix'
map global kiki <a-c> "<esc>o%opt{kiki_prefix}<esc>:comment-line<ret><esc>k<a-j>A" -docstring 'Create a new command on the current line.'

# Command execution and manipulation.
map global kiki y ':kiki-select<ret>y' -docstring 'Select and yank after tab.'
map global kiki i ':kiki-inline<ret>' -docstring 'Execute and return inline.'
map global kiki s ':kiki-scratch<ret>' -docstring 'Execute and return in scratch buffer.'
map global kiki f ':kiki-fifo<ret>' -docstring 'Execute and pipe output to fifo.'
map global kiki b ':kiki-background<ret>' -docstring 'Execute in the background.'
map global kiki '!' ':kiki-shell<ret>' -docstring 'Execute in terminal shell.'
map global kiki o ':kiki-shell<ret>' -docstring 'Execute in terminal shell.'

# File system navigation.
map global kiki Y ':kiki-uri-select<ret>y' -docstring 'Select and yank URI.'
map global kiki l ':kiki-ls<ret>' -docstring 'ls -al on path.'
map global kiki e ':kiki-edit<ret>' -docstring 'Open file at path.'

# Topics.
map global kiki t ':kiki-topic<ret>' -docstring ':e topic file with name.'
map global kiki T ':kiki-list-topics<ret>' -docstring 'List available topic files.'

# Quick actions.
map global kiki p ':kiki-cd<ret>' -docstring 'Change directory to path.'

# Scratchpad.
map global kiki , ':evaluate-commands %sh{ topics_dir=$(eval echo "$kak_opt_kiki_topics"); topics_dir=${topics_dir%/}; printf "edit %s/scratchpad.kiki" "$topics_dir"; }<ret>' -docstring 'Open scratchpad.'

# Delete menu.
map global kiki d ':enter-user-mode kiki-delete<ret>' -docstring 'Delete/close kiki buffers menu.'

# Delete submenu mappings.
map global kiki-delete a ':kiki-close-all-buffers<ret>' -docstring 'Close all kiki buffers.'
map global kiki-delete f ':kiki-close-fifo-buffers<ret>' -docstring 'Close fifo buffers.'
map global kiki-delete t ':kiki-close-topics-buffers<ret>' -docstring 'Close topics buffers.'
map global kiki-delete k ':kiki-close-file-buffers<ret>' -docstring 'Close kiki file buffers.'

##
# Highlighters
# ------------

try %{ add-highlighter -override global/kiki_arrow regex ^>[^\n]+ 0:green }
try %{ add-highlighter -override global/kiki_dollar regex "\$ " 0:default+rb }
try %{ add-highlighter -override global/kiki_cmd regex "(?<=\$ )[^\n]+" 0:cyan }
# try %{ add-highlighter -override global/kiki_dash regex ^[\ ]+-[^\n]+ 0:red }
