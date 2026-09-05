# Kiki Core Helpers & Dispatchers

# Modeline tag helper
define-command -override -hidden -params 1 \
    kiki-set-modeline %{
        try %{ set-option window modelinefmt "%val{bufname} %val{cursor_line}:%val{cursor_char_column} {{context_info}} %{cyan}[kiki:%arg{1}]%{default} {{mode_info}} - %val{client}@[%val{session}]" }
    }

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
    kiki-select %{
        execute-keys "<esc>xs\$ .+<ret>"
        execute-keys "s(?<=\$ ).+"
        execute-keys '<ret>H'
    }

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

# Path dispatcher: handles explicit args, active selection, URI select, or line fallback
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
        # 3. No selection: try kiki-uri-select or whole line
        printf 'evaluate-commands %%{
            try %%{
                kiki-uri-select
                %s %%val{selection}
            } catch %%{
                execute-keys "<esc>x"
                %s %%val{selection}
            }
        }\n' "$action" "$action"
    }}
