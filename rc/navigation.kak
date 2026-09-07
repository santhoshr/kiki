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

        tmp_script=$(mktemp "${TMPDIR:-/tmp}"/kiki-drop-shell.XXXXXXXX)
        chmod +x "$tmp_script"
        cat << EOF > "$tmp_script"
#!/bin/sh
trap 'rm -f "\$0"' EXIT
cd "$target_dir" || exit 1
exec "\${SHELL:-sh}"
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
        topics_dir=$(eval echo "$kak_opt_kiki_topics")
        case "$topics_dir" in
            "~"/*) topics_dir="${HOME}/${topics_dir#"~"/}" ;;
            "~") topics_dir="${HOME}" ;;
        esac
        if [ -d "$topics_dir" ]; then
            timestamp=$(date +%H%M%S)
            buffer_name="*kiki-topics-${timestamp}*"
            printf 'edit -scratch %s\n' "$buffer_name"
            printf 'set-option buffer kiki_buffer_type topics\n'
            printf 'kiki-set-modeline topics\n'
            printf 'execute-keys "i"\n'
            printf 'execute-keys "Available kiki topics:\n\n"\n'
            for file in "$topics_dir"/*.kiki; do
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
