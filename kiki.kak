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

# Pipe to fifo.
define-command -override -params .. \
    -docstring "kiki-fifo [<arguments>]: execute bash command to fifo
Executes a bash command and prints the output in a new fifo buffer" \
    kiki-fifo %{ evaluate-commands %sh{
        output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-make.XXXXXXXX)/fifo
        mkfifo ${output}
        ( eval "$@" > ${output} 2>&1 ) > /dev/null 2>&1 < /dev/null &

        # Create unique buffer name with command and timestamp
        cmd_name=$(printf '%s' "$1" | tr '/' '-' | tr ' ' '-')
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
    kiki-background %{ evaluate-commands %sh{
        ( eval "$@" ) > /dev/null 2>&1 < /dev/null &
        pid=$!
        escaped_cmd=$(printf '%s' "$*" | sed "s/'/''/g")
        printf "echo -debug 'KIKI: Background command started [PID %s]: %s'\n" "$pid" "$escaped_cmd"
        printf "echo 'kiki: started background job [PID %s]: %s'\n" "$pid" "$escaped_cmd"
}}

# Selection after prefix.
define-command -override -docstring "kiki-select: select all text after kiki" \
    kiki-select %{
        execute-keys "<esc>xs\$ .+<ret>"
        execute-keys "s(?<=\$ ).+"
        execute-keys '<ret>H'
}

# Select URI.
define-command -override -docstring "kiki-uri-select: select a uri on the current line" \
    kiki-uri-select %{
        execute-keys "<esc>xs(~/|\./|/)[^\s]+\b<ret>"
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
        for buffer in $kak_buflist; do
            printf 'evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    if [ -n "$kak_opt_kiki_buffer_type" ]; then
                        printf "delete-buffer %s" "%s"
                    fi
                }
            }\n' "$buffer" "$buffer"
        done
    }}

# Close fifo buffers.
define-command -override -docstring "kiki-close-fifo-buffers: close all kiki fifo buffers" \
    kiki-close-fifo-buffers %{ evaluate-commands %sh{
        for buffer in $kak_buflist; do
            printf 'evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    if [ "$kak_opt_kiki_buffer_type" = "fifo" ]; then
                        printf "delete-buffer %s" "%s"
                    fi
                }
            }\n' "$buffer" "$buffer"
        done
    }}

# Close topics buffers.
define-command -override -docstring "kiki-close-topics-buffers: close all kiki topics buffers" \
    kiki-close-topics-buffers %{ evaluate-commands %sh{
        for buffer in $kak_buflist; do
            printf 'evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    if [ "$kak_opt_kiki_buffer_type" = "topics" ]; then
                        printf "delete-buffer %s" "%s"
                    fi
                }
            }\n' "$buffer" "$buffer"
        done
    }}

# Close kiki file buffers.
define-command -override -docstring "kiki-close-file-buffers: close all kiki file buffers" \
    kiki-close-file-buffers %{ evaluate-commands %sh{
        for buffer in $kak_buflist; do
            printf 'evaluate-commands -buffer "%s" %%{
                evaluate-commands %%sh{
                    if [ "$kak_opt_kiki_buffer_type" = "file" ]; then
                        printf "delete-buffer %s" "%s"
                    fi
                }
            }\n' "$buffer" "$buffer"
        done
    }}

##
# Shortcuts
# ---------

# Prefix shortcuts.
map global kiki c "<esc>o%opt{kiki_prefix}<esc>:comment-line<ret><esc>k<a-j>A" -docstring 'Create a new command on the current line.'
map global kiki C "<esc>I%opt{kiki_prefix}<esc>" -docstring 'Prefix the current line with kiki_prefix'

# Command execution and manipulation.
map global kiki y ':kiki-select<ret>y' -docstring 'Select and yank after tab.'
map global kiki i ':kiki-select<ret>yo<esc>!<c-r>"<ret>' -docstring 'Execute and return inline.'
map global kiki s ':kiki-select<ret>y<esc>:e -scratch *kiki-scratch*<ret>:set-option buffer kiki_buffer_type scratch<ret>!<c-r>"<ret>xH!<c-r>.<ret>' -docstring 'Execute and return in scratch buffer.'
map global kiki f ':kiki-select<ret>yA<esc>:kiki-fifo <c-r>"<ret>' -docstring 'Execute and pipe output to fifo.'
map global kiki b ':kiki-select<ret>yA<esc>:kiki-background <c-r>"<ret>' -docstring 'Execute in the background.'

# File system navigation.
map global kiki Y ':kiki-uri-select<ret>y' -docstring 'Select and yank URI.'
map global kiki l ':kiki-uri-select<ret>yA<ret><esc>!ls -alh <c-r>"<ret>' -docstring 'ls -al: current path.'
map global kiki e ':kiki-uri-select<ret>yA<ret><esc>:e <c-r>"<ret>' -docstring ':e on the current path.'

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
