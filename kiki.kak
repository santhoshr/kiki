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
declare-option -docstring "Buffer category, set to kiki-buffer for all kiki buffers" str kiki_buffer_type ""
declare-option -docstring "Custom interactive shell for kiki drop-to-shell (defaults to auto-detected user shell)" str kiki_shell ""

##
# Load Modules
# ------------
evaluate-commands %sh{
    kiki_dir=$(dirname "$kak_source")
    for module in "$kiki_dir"/rc/*.kak; do
        [ -f "$module" ] && printf 'source "%s"\n' "$module"
    done
}

##
# Shortcuts
# ---------

# Prefix shortcuts
map global kiki c "i%opt{kiki_prefix}<esc>" -docstring 'Insert kiki_prefix at cursor position.'
map global kiki C "<esc>I%opt{kiki_prefix}<esc>" -docstring 'Prefix the current line with kiki_prefix.'
map global kiki <a-c> "<esc>o%opt{kiki_prefix}<esc>:comment-line<ret><esc>k<a-j>A" -docstring 'Create a new command on the current line.'

# Command execution and manipulation
map global kiki y ':kiki-select<ret>y' -docstring 'Select and yank after prefix.'
map global kiki i ':kiki-inline<ret>' -docstring 'Execute and return inline.'
map global kiki s ':kiki-scratch<ret>' -docstring 'Execute and return in scratch buffer.'
map global kiki f ':kiki-fifo<ret>' -docstring 'Execute and pipe output to fifo.'
map global kiki b ':kiki-background<ret>' -docstring 'Execute in the background.'
map global kiki '!' ':kiki-shell<ret>' -docstring 'Execute in terminal shell.'

# File system navigation
map global kiki Y ':kiki-uri-select<ret>y' -docstring 'Select and yank URI.'
map global kiki l ':kiki-ls<ret>' -docstring 'ls -al on path.'
map global kiki e ':kiki-edit<ret>' -docstring 'Open file at path.'
map global kiki o ':kiki-file-tree<ret>' -docstring 'Open file tree for directory.'

# Topics
map global kiki t ':kiki-topic<ret>' -docstring ':e topic file with name.'
map global kiki T ':kiki-list-topics<ret>' -docstring 'List available topic files.'

# Quick actions
map global kiki p ':kiki-cd<ret>' -docstring 'Change directory to path.'
map global kiki D ':kiki-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in selected directory.'

# Scratchpad
map global kiki q ':kiki-scratchpad<ret>' -docstring 'Open disposable quick scratchpad.'
map global kiki , ':evaluate-commands %sh{ topics_dir=$(eval echo "$kak_opt_kiki_topics"); topics_dir=${topics_dir%/}; printf "edit %s/scratchpad.kiki" "$topics_dir"; }<ret>' -docstring 'Open scratchpad.kiki file.'

# Delete menu
map global kiki d ':enter-user-mode kiki-delete<ret>' -docstring 'Delete/close kiki buffers menu.'

# Delete submenu mappings
map global kiki-delete a ':kiki-close-all-buffers<ret>' -docstring 'Close all kiki buffers.'
map global kiki-delete f ':kiki-close-fifo-buffers<ret>' -docstring 'Close fifo buffers.'
map global kiki-delete t ':kiki-close-topics-buffers<ret>' -docstring 'Close topics buffers.'
map global kiki-delete r ':kiki-close-tree-buffers<ret>' -docstring 'Close file tree buffers.'
map global kiki-delete s ':kiki-close-scratchpad-buffers<ret>' -docstring 'Close scratchpad buffers.'
map global kiki-delete k ':kiki-close-file-buffers<ret>' -docstring 'Close kiki file buffers.'
