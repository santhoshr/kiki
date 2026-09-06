# Kiki Command Execution (inline, scratch, fifo, background, shell)

# Execute command and return inline below current line
define-command -override -params .. \
    -docstring "kiki-inline [<arguments>]: execute bash command and insert output below current line" \
    kiki-inline %{
        kiki-cmd-dispatch kiki-inline-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-inline-do %{ evaluate-commands %sh{
        cmd="$1"
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

# Execute command and return in scratch buffer
define-command -override -params .. \
    -docstring "kiki-scratch [<arguments>]: execute bash command and return output in scratch buffer" \
    kiki-scratch %{
        kiki-cmd-dispatch kiki-scratch-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-scratch-do %{ evaluate-commands %sh{
        cmd="$1"
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
        printf 'kiki-set-modeline scratch\n'
        printf 'execute-keys -draft %%{<percent>d!cat "%s"<ret>}\n' "$tmp_out"
        printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_out"
    }}

# Execute bash command and pipe output to a new fifo buffer
define-command -override -params .. \
    -docstring "kiki-fifo [<arguments>]: execute bash command and print output in a new fifo buffer" \
    kiki-fifo %{
        kiki-cmd-dispatch kiki-fifo-do %arg{@}
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
            kiki-set-modeline fifo
            hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r $(dirname ${output}) } }
        }"
    }}

# Background execution
define-command -override -params .. \
    -docstring "kiki-background [<arguments>]: execute bash command in the background" \
    kiki-background %{
        kiki-cmd-dispatch kiki-background-do %arg{@}
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

# Terminal shell execution
define-command -override -params .. \
    -docstring "kiki-shell [<arguments>]: execute bash command in terminal shell with current directory" \
    kiki-shell %{
        kiki-cmd-dispatch kiki-shell-do %arg{@}
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

        printf 'kiki-spawn-terminal "%s"\n' "$tmp_script"
    }}
