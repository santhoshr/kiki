# Kiki Core Helpers & Dispatchers

# Modeline tag helper
define-command -override -hidden -params 1 \
    kiki-set-modeline %{
        try %{ set-option window modelinefmt "%val{bufname} %val{cursor_line}:%val{cursor_char_column} {{context_info}} %{cyan}[kiki:%arg{1}]%{default} {{mode_info}} - %val{client}@[%val{session}]" }
    }

# Spawn terminal matching the current active terminal emulator
define-command -override -hidden -params 1 \
    kiki-spawn-terminal %{ evaluate-commands %sh{
        script_path="$1"
        term_bin=""

        # 1. Inspect ancestor processes of Kakoune client/server
        target_pid="${kak_client_pid:-$$}"
        while [ "$target_pid" -gt 1 ] 2>/dev/null; do
            if [ -f "/proc/$target_pid/comm" ]; then
                comm=$(cat "/proc/$target_pid/comm" 2>/dev/null)
                case "$comm" in
                    *ghostty*) term_bin="ghostty" ; break ;;
                    *alacritty*) term_bin="alacritty" ; break ;;
                    *kitty*) term_bin="kitty" ; break ;;
                    *wezterm*) term_bin="wezterm" ; break ;;
                    *foot*) term_bin="foot" ; break ;;
                    *st*) term_bin="st" ; break ;;
                    *xterm*) term_bin="xterm" ; break ;;
                esac
            fi
            target_pid=$(awk '/PPid:/ {print $2}' "/proc/$target_pid/status" 2>/dev/null)
        done

        # 2. Inspect environment variables if process walk didn't match
        if [ -z "$term_bin" ]; then
            if [ -n "$GHOSTTY_RESOURCES_DIR" ] || [ "$TERM" = "xterm-ghostty" ]; then
                term_bin="ghostty"
            elif [ -n "$KITTY_PID" ] || [ -n "$KITTY_WINDOW_ID" ] || [ "$TERM" = "xterm-kitty" ]; then
                term_bin="kitty"
            elif [ -n "$ALACRITTY_LOG" ] || [ -n "$ALACRITTY_WINDOW_ID" ] || [ "$TERM" = "alacritty" ]; then
                term_bin="alacritty"
            elif [ -n "$WEZTERM_PANE" ]; then
                term_bin="wezterm"
            elif [ -n "$FOOT_SERVER_PATH" ] || [ "$TERM" = "foot" ]; then
                term_bin="foot"
            fi
        fi

        # 3. Launch with detected terminal binary or fall back to Kakoune's terminal command
        if [ "$term_bin" = "ghostty" ] && command -v ghostty >/dev/null 2>&1; then
            ( ghostty -e "$script_path" ) >/dev/null 2>&1 < /dev/null &
        elif [ "$term_bin" = "kitty" ] && command -v kitty >/dev/null 2>&1; then
            ( kitty "$script_path" ) >/dev/null 2>&1 < /dev/null &
        elif [ "$term_bin" = "alacritty" ] && command -v alacritty >/dev/null 2>&1; then
            ( alacritty -e "$script_path" ) >/dev/null 2>&1 < /dev/null &
        elif [ "$term_bin" = "wezterm" ] && command -v wezterm >/dev/null 2>&1; then
            ( wezterm start -- "$script_path" ) >/dev/null 2>&1 < /dev/null &
        elif [ "$term_bin" = "foot" ] && command -v foot >/dev/null 2>&1; then
            ( foot "$script_path" ) >/dev/null 2>&1 < /dev/null &
        else
            printf 'terminal "%s"\n' "$script_path"
        fi
    }}

# Sudo authentication callback
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

# Sudo check and password prompt helper
define-command -override -hidden -params 2 \
    kiki-check-sudo %{ evaluate-commands %sh{
        action="$1"
        cmd="$2"
        if printf '%s\n' "$cmd" | grep -Eq '(^|[;&|[:space:]])sudo([[:space:]]|$)'; then
            if ! sudo -n true >/dev/null 2>&1; then
                printf 'prompt -password "Password:" %%{ kiki-sudo-auth-and-run %%{%s} %%{%s} }\n' "$action" "$cmd"
                exit 0
            fi
        fi
        printf '%s %%{%s}\n' "$action" "$cmd"
    }}

# Selection after prefix
define-command -override -docstring "kiki-select: select all text after kiki prefix on current line" \
    kiki-select %{ evaluate-commands %sh{
        prefix="$kak_opt_kiki_prefix"
        [ -z "$prefix" ] && prefix='$ '
        escaped_prefix=$(printf '%s' "$prefix" | sed 's/[][\/.^$*+?(){}|]/\\&/g')
        printf 'execute-keys "<esc>xs%s.+<ret>"\n' "$escaped_prefix"
        printf 'execute-keys "s(?<=%s).+"\n' "$escaped_prefix"
        printf "execute-keys '<ret>H'\n"
    }}

# Select URI / path on line
define-command -override -docstring "kiki-uri-select: select a uri/path on the current line" \
    kiki-uri-select %{
        execute-keys "<esc>xs(~/[^\s:]*|/[^\s:]+|\./[^\s:]+|[a-zA-Z0-9_.-]+/[^\s:]+|[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_-]+)(:[0-9]+)*\b<ret>"
    }

# Command dispatcher: handles explicit args, active selection, or prefix line fallback with sudo check
define-command -override -hidden -params 1.. \
    kiki-cmd-dispatch %{ evaluate-commands %sh{
        action="$1"
        shift
        # 1. Explicit argument provided
        if [ $# -ge 1 ]; then
            printf 'kiki-check-sudo "%s" %%{%s}\n' "$action" "$*"
            exit 0
        fi
        # 2. Active multi-character selection
        trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ "${#trimmed_sel}" -gt 1 ]; then
            printf 'kiki-check-sudo "%s" %%{%s}\n' "$action" "$trimmed_sel"
            exit 0
        fi
        # 3. No selection: extract command after prefix on current line
        printf 'try %%{
            kiki-select
            kiki-check-sudo "%s" %%val{selection}
        } catch %%{
            evaluate-commands %%{
                execute-keys "<esc>x"
                kiki-check-sudo "%s" %%val{selection}
            }
        }\n' "$action" "$action"
    }}

# Path dispatcher: handles explicit args, active selection, tree line resolution, URI select, or line fallback
define-command -override -hidden -params 1.. \
    kiki-path-dispatch %{ evaluate-commands %sh{
        action="$1"
        shift
        # 1. Explicit argument provided
        if [ $# -ge 1 ]; then
            printf '%s %%{%s}\n' "$action" "$1"
            exit 0
        fi
        # 2. Active multi-character selection
        trimmed_sel=$(printf '%s\n' "$kak_selection" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ "${#trimmed_sel}" -gt 1 ]; then
            printf '%s %%{%s}\n' "$action" "$trimmed_sel"
            exit 0
        fi
        # 3. If in a tree buffer or on a tree node line, resolve full tree path
        # Check current line without affecting selection in draft
        printf 'evaluate-commands -draft %%{
            execute-keys "<esc>x"
            evaluate-commands %%sh{
                trimmed=$(printf "%%s\n" "$kak_selection" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
                if printf "%%s\n" "$trimmed" | grep -Eq "^[+-][[:space:]]" || [ "$kak_bufname" = "*kiki-file-tree*" ]; then
                    printf "evaluate-commands -client %%%%val{client} kiki-tree-resolve-path %%s\n" "%s"
                else
                    printf "evaluate-commands -client %%%%val{client} %%%%{
                        try %%%%{
                            kiki-uri-select
                            %s %%%%val{selection}
                        } catch %%%%{
                            execute-keys %%%%{<esc>x}
                            %s %%%%val{selection}
                        }
                    }\n"
                fi
            }
        }\n' "$action" "$action" "$action"
    }}
