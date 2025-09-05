# Kiki
#   Alexander Maricich 2019

declare-user-mode kiki

##
# Options
# -------

declare-option str kiki_prefix "$ "
declare-option str kiki_scratch "~/.config/kak/kiki/scratchpad.kiki"
declare-option str kiki_topics "~/.config/kak/kiki/"
declare-option str kiki_buffer_type ""

##
# Commands
# --------

# Pipe to fifo.
define-command -params .. \
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
            hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r $(dirname ${output}) } }
        }"
}}

# Background execution.
define-command -params .. \
    -docstring "kiki-background [<arguments>]: execute bash command in the background" \
    kiki-background %{ evaluate-commands %sh{
        ( eval "$@" > ${output} 2>&1 ) > /dev/null 2>&1 < /dev/null
}}

# Selection after prefix.
define-command -docstring "kiki-select: select all text after kiki" \
    kiki-select %{
        execute-keys "<esc>xs\$ .+<ret>"
        execute-keys "s(?<=\$ ).+"
        execute-keys '<ret>H'
}

# Select URI.
define-command -docstring "kiki-uri-select: select a uri on the current line" \
    kiki-uri-select %{
        execute-keys "<esc>xs(~/|\./|/)[^\s]+\b<ret>"
}

# Open topic file.
define-command -docstring "kiki-topic: open a topic file with the given name" \
    kiki-topic %{
        execute-keys "<esc>xs\$ \S+<ret>s\S+<ret>"
        evaluate-commands %sh{
            # Get only the first word after the prefix and extract basename if it's a path
            topic_name=$(basename "$kak_selection")
            printf 'edit "%s%s.kiki"' "$kak_opt_kiki_topics" "$topic_name"
        }
    }


# Change directory to path.
define-command -docstring "kiki-cd: change directory to path from selected text after prefix" \
    kiki-cd %{
        kiki-select
        evaluate-commands %sh{
            # Expand ~ and relative paths
            path=$(eval echo "$kak_selection")
            printf 'change-directory "%s"' "$path"
        }
    }

# List available topic files.
define-command -docstring "kiki-list-topics: list all available topic files" \
    kiki-list-topics %{ evaluate-commands %sh{
        topics_dir=$(eval echo "$kak_opt_kiki_topics")
        if [ -d "$topics_dir" ]; then
            timestamp=$(date +%H%M%S)
            buffer_name="*kiki-topics-${timestamp}*"
            printf 'edit -scratch %s\n' "$buffer_name"
            printf 'set-option buffer kiki_buffer_type topics\n'
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
map global kiki , ":e %opt{kiki_scratch}<ret>" -docstring 'Open scratchpad.'

##
# Highlighters
# ------------

add-highlighter global/ regex ^>[^\n]+ 0:green
add-highlighter global/ regex "\$ " 0:default+rb
add-highlighter global/ regex "(?<=\$ )[^\n]+" 0:cyan
# add-highlighter global/ regex ^[\ ]+-[^\n]+ 0:red

