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

        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-in-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-inline-replace-do "%s" "%s"\n' "$cmd" "$tmp_buf"
    }}

define-command -override -hidden -params 2 \
    kiki-inline-replace-do %{ evaluate-commands %sh{
        cmd="$1"
        tmp_buf="$2"
        cur_line="${kak_cursor_line:-1}"
        pfx="${kak_opt_kiki_prefix:-\$ }"
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        tmp_out=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-inline-out.XXXXXXXX)
        ( eval "$cmd" ) > "$tmp_out" 2>&1 < /dev/null

        out_updated=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-inline-buf.XXXXXXXX)

        res=$(python3 - "$tmp_buf" "$cur_line" "$pfx" "$tmp_out" "$out_updated" << 'PYEOF'
import sys

buf_file = sys.argv[1]
try: cur_line = int(sys.argv[2])
except: cur_line = 1
pfx = sys.argv[3]
out_file = sys.argv[4]
new_buf_file = sys.argv[5]

try:
    with open(buf_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [l.rstrip('\r\n') for l in f]
except:
    sys.exit(1)

try:
    with open(out_file, 'r', encoding='utf-8', errors='replace') as f:
        cmd_output = [l.rstrip('\r\n') for l in f]
    # Strip trailing empty lines from command output to keep formatting neat
    while cmd_output and cmd_output[-1] == '':
        cmd_output.pop()
except:
    cmd_output = []

cur_idx = cur_line - 1
if cur_idx < 0 or cur_idx >= len(lines):
    sys.exit(1)

# Find existing output of this command line.
# Output lines continue until hitting any structural boundary:
# - Blank line
# - Next command line (starts with pfx or '$ ' or '>')
# - Comment line (starts with '#')
# - Tree node line (starts with '+ ' or '- ')
start_idx = cur_idx + 1
end_idx = start_idx
while end_idx < len(lines):
    line = lines[end_idx]
    s = line.lstrip()
    if not s or s.startswith(pfx) or s.startswith('$ ') or s.startswith('>') or s.startswith('#') or s.startswith('+ ') or s.startswith('- '):
        break
    end_idx += 1

new_lines = lines[:start_idx] + cmd_output + lines[end_idx:]

with open(new_buf_file, 'w', encoding='utf-8') as f:
    for l in new_lines:
        f.write(l + '\n')

insert_start = start_idx + 1
insert_end = start_idx + len(cmd_output)
print(f"{new_buf_file}|{insert_start}|{insert_end}|{len(cmd_output)}")
PYEOF
)
        rc=$?
        [ -n "$tmp_buf" ] && rm -f -- "$tmp_buf" 2>/dev/null || true
        [ -n "$tmp_out" ] && rm -f -- "$tmp_out" 2>/dev/null || true

        if [ $rc -ne 0 ] || [ -z "$res" ]; then
            [ -n "$out_updated" ] && rm -f -- "$out_updated" 2>/dev/null || true
            exit 0
        fi

        buf_updated=$(printf '%s\n' "$res" | cut -d'|' -f1)
        ins_start=$(printf '%s\n' "$res" | cut -d'|' -f2)
        ins_end=$(printf '%s\n' "$res" | cut -d'|' -f3)
        out_count=$(printf '%s\n' "$res" | cut -d'|' -f4)

        if [ -n "$buf_updated" ] && [ -f "$buf_updated" ]; then
            if [ "$out_count" -gt 0 ] 2>/dev/null; then
                printf '%s %%{ execute-keys %%{<percent>|cat "%s"<ret>}; select %s.1,%s.99999999; try %%{ ansi-render-selection }; select %s.1,%s.1; nop %%sh{ rm -f -- "%s" 2>/dev/null } }\n' \
                    "$eval_cmd" "$buf_updated" "$ins_start" "$ins_end" "$cur_line" "$cur_line" "$buf_updated"
            else
                printf '%s %%{ execute-keys %%{<percent>|cat "%s"<ret>}; select %s.1,%s.1; nop %%sh{ rm -f -- "%s" 2>/dev/null } }\n' \
                    "$eval_cmd" "$buf_updated" "$cur_line" "$cur_line" "$buf_updated"
            fi
        fi
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
        printf 'try %%{ ansi-render }\n'
        printf 'nop %%sh{ rm -f -- "%s" 2>/dev/null }\n' "$tmp_out"
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
            edit! -fifo %{$output} -scroll %{$buffer_name}
            set-option buffer filetype kiki
            set-option buffer kiki_buffer_type kiki-buffer
            kiki-set-modeline kiki-buffer
            hook -always -once buffer BufCloseFifo .* %{
                nop %sh{ rm -r -- \"$(dirname -- \"$output\")\" }
                try %{ ansi-render }
            }
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
