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
        if [ -n "$kak_opt_kiki_prefix" ]; then
            cmd="${cmd#"$kak_opt_kiki_prefix"}"
        fi
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
        if [ -n "$kak_opt_kiki_prefix" ]; then
            cmd="${cmd#"$kak_opt_kiki_prefix"}"
        fi
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
        printf 'set-option buffer filetype kiki\n'
        printf 'set-option buffer kiki_buffer_type kiki-buffer\n'
        printf 'kiki-set-modeline kiki-buffer\n'
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
        if [ -n "$kak_opt_kiki_prefix" ]; then
            cmd="${cmd#"$kak_opt_kiki_prefix"}"
        fi
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
            set-option buffer filetype kiki
            set-option buffer kiki_buffer_type kiki-buffer
            kiki-set-modeline kiki-buffer
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
        if [ -n "$kak_opt_kiki_prefix" ]; then
            cmd="${cmd#"$kak_opt_kiki_prefix"}"
        fi
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
        if [ -n "$kak_opt_kiki_prefix" ]; then
            cmd="${cmd#"$kak_opt_kiki_prefix"}"
        fi
        cmd="${cmd#\$ }"
        cmd="${cmd#\$}"
        cmd=$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        user_shell=""
        if [ -n "$kak_opt_kiki_shell" ] && command -v "$kak_opt_kiki_shell" >/dev/null 2>&1; then
            user_shell="$kak_opt_kiki_shell"
        fi

        # Inspect ancestor processes of Kakoune client/server
        if [ -z "$user_shell" ]; then
            target_pid="${kak_client_pid:-$$}"
            while [ "$target_pid" -gt 1 ] 2>/dev/null; do
                if [ -f "/proc/$target_pid/comm" ]; then
                    comm=$(cat "/proc/$target_pid/comm" 2>/dev/null)
                    case "$comm" in
                        *fish*|*zsh*|*bash*|*nu*|*elvish*|*tcsh*|*csh*|*ksh*|*dash*|*yash*|*ion*|*xonsh*)
                            if [ -L "/proc/$target_pid/exe" ]; then
                                exe_path=$(readlink -f "/proc/$target_pid/exe" 2>/dev/null)
                                [ -x "$exe_path" ] && user_shell="$exe_path" && break
                            fi
                            if command -v "$comm" >/dev/null 2>&1; then
                                user_shell=$(command -v "$comm")
                                break
                            fi
                            ;;
                    esac
                elif command -v ps >/dev/null 2>&1; then
                    comm=$(ps -p "$target_pid" -o comm= 2>/dev/null)
                    case "$comm" in
                        *fish*|*zsh*|*bash*|*nu*|*elvish*|*tcsh*|*csh*|*ksh*|*dash*|*yash*|*ion*|*xonsh*)
                            if command -v "$comm" >/dev/null 2>&1; then
                                user_shell=$(command -v "$comm")
                                break
                            fi
                            ;;
                    esac
                fi
                if [ -f "/proc/$target_pid/status" ]; then
                    target_pid=$(awk '/PPid:/ {print $2}' "/proc/$target_pid/status" 2>/dev/null)
                elif command -v ps >/dev/null 2>&1; then
                    target_pid=$(ps -p "$target_pid" -o ppid= 2>/dev/null | tr -d ' ')
                else
                    break
                fi
            done
        fi

        # Check environment variable $SHELL
        if [ -z "$user_shell" ] && [ -n "$SHELL" ] && [ -x "$SHELL" ]; then
            user_shell="$SHELL"
        fi

        # Check system user database
        if [ -z "$user_shell" ]; then
            db_shell=""
            if command -v getent >/dev/null 2>&1 && [ -n "$USER" ]; then
                db_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
            elif [ -f /etc/passwd ] && [ -n "$USER" ]; then
                db_shell=$(awk -F: -v u="$USER" '$1==u {print $7}' /etc/passwd 2>/dev/null)
            elif command -v dscl >/dev/null 2>&1 && [ -n "$USER" ]; then
                db_shell=$(dscl . -read /Users/"$USER" UserShell 2>/dev/null | awk '{print $2}')
            fi
            if [ -n "$db_shell" ] && [ -x "$db_shell" ]; then
                user_shell="$db_shell"
            fi
        fi

        # Fallback to available common shells or sh
        if [ -z "$user_shell" ]; then
            for sh_candidate in zsh fish bash sh; do
                if command -v "$sh_candidate" >/dev/null 2>&1; then
                    user_shell=$(command -v "$sh_candidate")
                    break
                fi
            done
        fi
        [ -z "$user_shell" ] && user_shell="/bin/sh"

        tmp_script=$(mktemp "${TMPDIR:-/tmp}"/kiki-shell.XXXXXXXX)
        chmod +x "$tmp_script"

        if [ -z "$cmd" ]; then
            cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
cd "$PWD" || exit 1
exec "$user_shell"
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
