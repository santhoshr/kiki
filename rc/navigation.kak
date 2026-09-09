# Kiki Filesystem & Topics Navigation

# Open topic file
define-command -override -params 0..1 \
    -docstring "kiki-topic [<name>]: open a topic file with the given name" \
    kiki-topic %{
        kiki-path-dispatch kiki-topic-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-topic-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw="${raw#> }"
        raw="${raw#>}"
        topic_raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | awk '{print $1}')
        topic_name=$(basename "$topic_raw" .kiki)
        if [ -n "$topic_name" ] && [ "$topic_name" != "$" ] && [ "$topic_name" != ">" ]; then
            topics_dir="$kak_opt_kiki_topics"
            case "$topics_dir" in
                "~"/*) topics_dir="${HOME}/${topics_dir#"~"/}" ;;
                "~") topics_dir="${HOME}" ;;
            esac
            topics_dir="${topics_dir%/}/"
            mkdir -p "$topics_dir"
            printf 'execute-keys %%{;}\n'
            printf 'edit %%{%s%s.kiki}\n' "$topics_dir" "$topic_name"
        else
            printf 'execute-keys %%{;}\n'
            printf 'echo -markup "{Error}kiki-topic: no topic name found on line"\n'
        fi
    }}

# Change directory to path
define-command -override -params 0..1 \
    -docstring "kiki-cd [<path>]: change directory to path from argument, selected text, or line with prefix/URI" \
    kiki-cd %{
        kiki-path-dispatch kiki-cd-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-cd-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
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

# Drop to shell (suspend Kakoune and change directory to selected / target path)
define-command -override -params 0..1 \
    -docstring "kiki-drop-to-shell [<path>]: suspend Kakoune and drop to shell with current/selected directory" \
    kiki-drop-to-shell %{
        kiki-path-dispatch kiki-drop-to-shell-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-drop-to-shell-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
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
            path="$PWD"
        fi

        target_dir="$path"
        if [ -f "$target_dir" ]; then
            target_dir=$(dirname "$target_dir")
        fi

        if [ ! -d "$target_dir" ]; then
            target_dir="$PWD"
        fi

        printf 'echo -debug "kiki-drop-to-shell: opening shell in %s (raw input: %s)"\n' "$target_dir" "$1"
        printf 'change-directory %%{%s}\n' "$target_dir"
        printf 'echo "kiki: opened shell in %s"\n' "$target_dir"

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

        tmp_script=$(mktemp "${TMPDIR:-/tmp}"/kiki-drop-shell.XXXXXXXX)
        chmod +x "$tmp_script"
        cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
cd "$target_dir" || exit 1
exec "$user_shell"
EOF
        printf 'kiki-spawn-terminal "%s"\n' "$tmp_script"
    }}

# Edit file at path
define-command -override -params 0..1 \
    -docstring "kiki-edit [<path>]: open file from argument, selected text, or path under cursor" \
    kiki-edit %{
        kiki-path-dispatch kiki-edit-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-edit-do %{ evaluate-commands %sh{
        raw="$1"
        # Strip leading/trailing whitespace and optional prefix
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
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

        if [ -d "$path" ]; then
            printf 'kiki-file-tree %%{%s}\n' "$path"
        elif [ -n "$line" ] && [ -n "$col" ]; then
            printf 'edit %%{%s} %s %s\n' "$path" "$line" "$col"
        elif [ -n "$line" ]; then
            printf 'edit %%{%s} %s\n' "$path" "$line"
        else
            printf 'edit %%{%s}\n' "$path"
        fi
    }}

# Preview file at path in connected preview client (or spawn new client)
define-command -override -params 0..1 \
    -docstring "kiki-preview [<path>]: open or update buffer in preview client" \
    kiki-preview %{
        kiki-path-dispatch kiki-preview-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-preview-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
        raw=$(printf '%s\n' "$raw" | sed -e 's/:[[:space:]].*$//' -e 's/:$//')

        line=""
        col=""
        path=""

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

        case "$path" in
            "~"/*) path="${HOME}/${path#"~"/}" ;;
            "~") path="${HOME}" ;;
        esac

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
            printf 'echo -markup "{Error}kiki-preview: no file path found on line"\n'
            exit 0
        fi

        if [ -d "$path" ]; then
            target_cmd="kiki-file-tree %{$path}"
        elif [ -n "$line" ] && [ -n "$col" ]; then
            target_cmd="edit %{$path} $line $col"
        elif [ -n "$line" ]; then
            target_cmd="edit %{$path} $line"
        else
            target_cmd="edit %{$path}"
        fi

        target_client=""
        for c in $kak_client_list; do
            if [ "$c" = "preview" ]; then
                target_client="preview"
                break
            elif [ -n "$kak_opt_toolsclient" ] && [ "$c" = "$kak_opt_toolsclient" ]; then
                target_client="$kak_opt_toolsclient"
            fi
        done

        if [ -n "$target_client" ]; then
            printf 'evaluate-commands -client "%s" %%{ %s; set-option buffer kiki_is_preview true }\n' "$target_client" "$target_cmd"
            printf 'echo "kiki: updated preview client [%s] with %s"\n' "$target_client" "$path"
        else
            tmp_script=$(mktemp "${TMPDIR:-/tmp}"/kiki-preview-client.XXXXXXXX)
            chmod +x "$tmp_script"
            escaped_target=$(printf '%s' "$target_cmd" | sed 's/"/\\"/g')
            cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
exec kak -c "$kak_session" -e "rename-client preview; $escaped_target; set-option buffer kiki_is_preview true"
EOF
            printf 'kiki-spawn-terminal "%s"\n' "$tmp_script"
            printf 'echo "kiki: launched preview client for %s"\n' "$path"
        fi
    }}

# List path contents
define-command -override -params 0..1 \
    -docstring "kiki-ls [<path>]: ls -alh on argument, selection, or URI on current line" \
    kiki-ls %{
        kiki-path-dispatch kiki-ls-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-ls-do %{ evaluate-commands %sh{
        raw="$1"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
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

# List available topic files
define-command -override -docstring "kiki-list-topics: list all available topic files" \
    kiki-list-topics %{ evaluate-commands %sh{
        topics_dir="$kak_opt_kiki_topics"
        case "$topics_dir" in
            "~"/*) topics_dir="${HOME}/${topics_dir#"~"/}" ;;
            "~") topics_dir="${HOME}" ;;
        esac
        topics_dir="${topics_dir%/}"
        if [ -d "$topics_dir" ]; then
            timestamp=$(date +%H%M%S)
            buffer_name="*kiki-topics-${timestamp}*"
            tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-topics.XXXXXXXX)
            {
                printf "Available kiki topics:\n\n"
                for file in "$topics_dir"/*.kiki; do
                    if [ -f "$file" ]; then
                        bname=$(basename "$file" .kiki)
                        printf "%s%s\n" "$kak_opt_kiki_prefix" "$bname"
                    fi
                done
            } > "$tmp_file"
            printf 'edit -scratch %%{%s}\n' "$buffer_name"
            printf 'set-option buffer filetype kiki\n'
            printf 'set-option buffer kiki_buffer_type kiki-buffer\n'
            printf 'kiki-set-modeline kiki-buffer\n'
            printf 'execute-keys %%{<percent>|cat "%s"<ret>}\n' "$tmp_file"
            printf 'select 1.1,1.1\n'
            printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_file"
        else
            printf 'echo -markup "{Error}Topics directory does not exist: %s"\n' "$topics_dir"
        fi
    }}

# Open URL from line, prompt for multiple, or search buffer
define-command -override -params 0..1 \
    -docstring "kiki-open-url [<url>]: open URL from argument, line, prompt for multiple, or search buffer" \
    kiki-open-url %{
        evaluate-commands -save-regs 'lu' %{
            execute-keys -draft 'x"ly'
            execute-keys -draft '%"uy'
            evaluate-commands %sh{
                url_regex="https?://[a-zA-Z0-9./?=_%:&+#~()-]+"
                browser="xdg-open"
                if command -v xdg-open >/dev/null 2>&1; then
                    browser="xdg-open"
                elif command -v open >/dev/null 2>&1; then
                    browser="open"
                elif [ -n "$BROWSER" ]; then
                    browser="$BROWSER"
                fi

                generate_prompt() {
                    title="$1"
                    urls="$2"
                    escaped_urls=$(printf '%s' "$urls" | sed "s/'/''/g")
                    printf "prompt -menu -shell-script-candidates %%{ printf '%%s\n' '%s' } \"%s\" %%{\n" "$escaped_urls" "$title"
                    printf '    nop %%sh{ ( %s "$kak_text" ) >/dev/null 2>&1 < /dev/null & }\n' "$browser"
                    printf '    echo -markup "{green}kiki: opened URL:{default} %%val{text}"\n'
                    printf '}\n'
                }

                if [ $# -ge 1 ] && [ -n "$1" ]; then
                    target_urls="$1"
                    url_count=1
                else
                    target_urls=$(printf "%s\n" "$kak_reg_l" | grep -oE "$url_regex" | sort -u || true)
                    url_count=$(printf "%s\n" "$target_urls" | grep -c . || true)
                fi

                if [ "$url_count" -eq 1 ]; then
                    printf 'nop %%sh{ ( %s "%s" ) >/dev/null 2>&1 < /dev/null & }\n' "$browser" "$target_urls"
                    printf 'echo -markup "{green}kiki: opened URL:{default} %s"\n' "$target_urls"
                elif [ "$url_count" -gt 1 ]; then
                    lines_selected=$(printf "%s" "$kak_reg_l" | grep -c "^" || true)
                    if [ "$lines_selected" -gt 1 ]; then
                        source_label="selection"
                    else
                        source_label="line"
                    fi
                    generate_prompt "Open URL (from $source_label):" "$target_urls"
                else
                    all_urls=$(printf "%s\n" "$kak_reg_u" | grep -oE "$url_regex" | sort -u || true)
                    if [ -z "$all_urls" ]; then
                        printf 'echo -markup "{Error}kiki: no URLs found in buffer"\n'
                        exit 0
                    fi
                    generate_prompt "Open URL (from buffer):" "$all_urls"
                fi
            }
        }
    }

define-command -override -docstring "open-url: alias for kiki-open-url" \
    open-url %{ kiki-open-url %arg{@} }
