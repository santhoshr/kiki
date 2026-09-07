# Kiki File Tree Navigation & Manipulation

declare-option -docstring "Show hidden/dot files in kiki-file-tree" bool kiki_tree_show_hidden false

# Set buffer type and local hooks/keys for kiki-file-tree scratch buffers and tree files
hook -group kiki global BufCreate \*kiki-file-tree\* %{
    set-option buffer kiki_buffer_type tree
    set-option buffer filetype kiki-tree
}

hook -group kiki global BufOpenFile .*\.kikitree$ %{
    set-option buffer kiki_buffer_type tree
    set-option buffer filetype kiki-tree
}

hook -group kiki global BufSetOption filetype=kiki-tree %{
    set-option buffer kiki_buffer_type tree
    map buffer normal <ret> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map buffer normal <c-o> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map buffer normal <tab> ':kiki-tree-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map buffer normal <c-l> ':kiki-tree-parent<ret>' -docstring 'Move to parent folder'
    map buffer normal r ':kiki-tree-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map buffer normal * ':kiki-tree-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map buffer normal <minus> ':kiki-tree-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map buffer normal . ':kiki-tree-toggle-hidden<ret>' -docstring 'Toggle hidden files'
    map buffer normal D ':kiki-tree-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
    map buffer normal q ':delete-buffer<ret>' -docstring 'Close tree view'
}

hook -group kiki global WinSetOption filetype=kiki-tree %{
    kiki-set-modeline tree
    map window normal <ret> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map window normal <c-o> ':kiki-tree-open<ret>' -docstring 'Toggle directory expand/collapse or open file'
    map window normal <tab> ':kiki-tree-step-into<ret>' -docstring 'Step into folder path and load subfolder or open file'
    map window normal <c-l> ':kiki-tree-parent<ret>' -docstring 'Move to parent folder'
    map window normal r ':kiki-tree-refresh<ret>' -docstring 'Refresh directory under cursor in-place'
    map window normal * ':kiki-tree-expand-recursive<ret>' -docstring 'Expand directory recursively'
    map window normal <minus> ':kiki-tree-narrow<ret>' -docstring 'Trim unselected subtrees/siblings'
    map window normal . ':kiki-tree-toggle-hidden<ret>' -docstring 'Toggle hidden files'
    map window normal D ':kiki-tree-drop-to-shell<ret>' -docstring 'Suspend Kakoune and drop to shell in directory under cursor'
    map window normal q ':delete-buffer<ret>' -docstring 'Close tree view'
}

# Main command to open file tree
define-command -override -params 0..1 \
    -docstring "kiki-file-tree [<dir>]: open interactive file tree for directory" \
    kiki-file-tree %{
        kiki-path-dispatch kiki-file-tree-do %arg{@}
    }

define-command -override -hidden -params 1 \
    kiki-file-tree-do %{ evaluate-commands %sh{
        raw="$1"
        # Strip leading/trailing whitespace and optional $ prefix
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        raw="${raw#\$ }"
        raw="${raw#\$}"
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Strip trailing colon / line numbers
        raw=$(printf '%s\n' "$raw" | sed -e 's/:[0-9]\+:[0-9]\+$//' -e 's/:[0-9]\+$//' -e 's/:$//')

        if [ -z "$raw" ]; then
            target_dir="$PWD"
        else
            case "$raw" in
                "~"/*) target_dir="${HOME}/${raw#"~"/}" ;;
                "~") target_dir="${HOME}" ;;
                *) target_dir="$raw" ;;
            esac
            if [ -f "$target_dir" ]; then
                target_dir=$(dirname "$target_dir")
            fi
        fi

        target_dir=$(cd "$target_dir" 2>/dev/null && pwd)
        if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
            target_dir="$PWD"
        fi

        bufname="*kiki-file-tree*"
        printf 'edit -scratch %s\n' "$bufname"
        printf 'set-option buffer kiki_buffer_type tree\n'
        printf 'set-option buffer filetype kiki-tree\n'

        tmp_content=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree.XXXXXXXX)
        target_dir_clean="${target_dir%/}/"
        printf '%s\n' "- $target_dir_clean" > "$tmp_content"

        show_hidden="$kak_opt_kiki_tree_show_hidden"
        if [ "$show_hidden" = "true" ]; then
            find "$target_dir" -mindepth 1 -maxdepth 1 ! -name "." ! -name ".." 2>/dev/null | sort -f | while IFS= read -r e; do
                if [ -d "$e" ]; then
                    printf '  + %s/\n' "${e##*/}" >> "$tmp_content"
                fi
            done
            find "$target_dir" -mindepth 1 -maxdepth 1 ! -name "." ! -name ".." 2>/dev/null | sort -f | while IFS= read -r e; do
                if [ ! -d "$e" ]; then
                    printf '  - %s\n' "${e##*/}" >> "$tmp_content"
                fi
            done
        else
            find "$target_dir" -mindepth 1 -maxdepth 1 ! -name ".*" 2>/dev/null | sort -f | while IFS= read -r e; do
                if [ -d "$e" ]; then
                    printf '  + %s/\n' "${e##*/}" >> "$tmp_content"
                fi
            done
            find "$target_dir" -mindepth 1 -maxdepth 1 ! -name ".*" 2>/dev/null | sort -f | while IFS= read -r e; do
                if [ ! -d "$e" ]; then
                    printf '  - %s\n' "${e##*/}" >> "$tmp_content"
                fi
            done
        fi

        printf 'execute-keys %%{<percent>|cat "%s"<ret>}\n' "$tmp_content"
        printf 'select 1.1,1.1\n'
        printf 'nop %%sh{ rm -f "%s" }\n' "$tmp_content"
    }}

# Open/toggle tree item at cursor (supports root nodes, subdirectories, files, and arbitrary new paths)
define-command -override -hidden \
    kiki-tree-open %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-open-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-open-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            t_line = lines[cur]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (clean_t == "" || t_line ~ /^[ \t]*#/) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            full_p = resolve_full_path(lines, cur)

            check_d = "test -d \"" full_p "\" && echo 'DIR' || (test -f \"" full_p "\" && echo 'FILE' || echo 'NONE')"
            check_d | getline node_type
            close(check_d)

            # If node does not end with / and is not an existing directory, open it as a file
            if (node_type != "DIR" && t_line !~ /\/[ \t]*$/) {
                printf "edit %%{%s}\n", full_p
                system("rm -f \"" tmp_file "\"")
                exit
            }

            has_children = (cur < total && get_indent(lines[cur + 1]) > t_indent)
            is_expanded = 0

            if (t_line ~ /^[ \t]*- /) {
                is_expanded = 1
            } else if (t_line ~ /^[ \t]*\+ /) {
                is_expanded = 0
            } else if (has_children) {
                is_expanded = 1
            } else {
                is_expanded = 0
            }

            out_tmp = tmp_file ".out"

            if (is_expanded) {
                # Collapse
                end_idx = cur + 1
                while (end_idx <= total && get_indent(lines[end_idx]) > t_indent && lines[end_idx] !~ /^[ \t]*#/) {
                    end_idx++
                }

                for (i = 1; i < cur; i++) print lines[i] > out_tmp

                collapsed_prefix = ""
                for (sp = 1; sp <= t_indent; sp++) collapsed_prefix = collapsed_prefix " "
                collapsed_prefix = collapsed_prefix "+ "

                disp_name = clean_t
                if (disp_name !~ /\/$/) disp_name = disp_name "/"
                print collapsed_prefix disp_name > out_tmp

                for (i = end_idx; i <= total; i++) print lines[i] > out_tmp
                close(out_tmp)

                printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
                printf "select %s.1,%s.1\n", cur, cur
                printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
            } else {
                # Expand in-place
                for (i = 1; i < cur; i++) print lines[i] > out_tmp

                expanded_prefix = ""
                for (sp = 1; sp <= t_indent; sp++) expanded_prefix = expanded_prefix " "
                expanded_prefix = expanded_prefix "- "

                disp_name = (t_indent == 0) ? full_p : clean_t
                if (disp_name !~ /\/$/) disp_name = disp_name "/"
                print expanded_prefix disp_name > out_tmp

                child_indent = ""
                for (sp = 1; sp <= (t_indent + 2); sp++) child_indent = child_indent " "

                if (hidden == "true") {
                    cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                    cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                } else {
                    cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".*\" 2>/dev/null | sort -f"
                    cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".*\" 2>/dev/null | sort -f"
                }

                d_count = 0
                while ((cmd_d | getline e) > 0) {
                    base = e
                    sub(/^.*\//, "", base)
                    d_count++
                    d_list[d_count] = base
                }
                close(cmd_d)

                f_count = 0
                while ((cmd_f | getline e) > 0) {
                    base = e
                    sub(/^.*\//, "", base)
                    f_count++
                    f_list[f_count] = base
                }
                close(cmd_f)

                for (d = 1; d <= d_count; d++) print child_indent "+ " d_list[d] "/" > out_tmp
                for (f = 1; f <= f_count; f++) print child_indent "- " f_list[f] > out_tmp

                for (i = cur + 1; i <= total; i++) print lines[i] > out_tmp
                close(out_tmp)

                printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
                printf "select %s.1,%s.1\n", cur, cur
                printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
            }
        }'
    }}

# Step-into subfolder path on <tab> (promotes directory to full path and expands subfolder; or opens file)
define-command -override -hidden \
    kiki-tree-step-into %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-step-into-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-step-into-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            t_line = lines[cur]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (clean_t == "" || t_line ~ /^[ \t]*#/) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            full_p = resolve_full_path(lines, cur)

            check_d = "test -d \"" full_p "\" && echo 'DIR' || (test -f \"" full_p "\" && echo 'FILE' || echo 'NONE')"
            check_d | getline node_type
            close(check_d)

            # If node does not end with / and is not an existing directory, open it as a file
            if (node_type != "DIR" && t_line !~ /\/[ \t]*$/) {
                printf "edit %%{%s}\n", full_p
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # For directory: promote line to full path "- <full_p>/" and replace parent tree
            sub(/\/$/, "", full_p)
            full_p_display = full_p "/"

            # Find the root header of this tree branch
            root_idx = cur
            if (t_indent > 0) {
                for (i = cur - 1; i >= 1; i--) {
                    if (get_indent(lines[i]) == 0 && lines[i] !~ /^[ \t]*#/) {
                        root_idx = i
                        break
                    }
                }
            }

            # Find the end of this root tree branch
            tree_end_idx = root_idx + 1
            while (tree_end_idx <= total && get_indent(lines[tree_end_idx]) > 0 && lines[tree_end_idx] !~ /^[ \t]*#/) {
                tree_end_idx++
            }

            out_tmp = tmp_file ".out"
            for (i = 1; i < root_idx; i++) print lines[i] > out_tmp

            # Replace root tree with new promoted root header
            print "- " full_p_display > out_tmp

            if (hidden == "true") {
                cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
            } else {
                cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".*\" 2>/dev/null | sort -f"
                cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".*\" 2>/dev/null | sort -f"
            }

            d_count = 0
            while ((cmd_d | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                d_count++
                d_list[d_count] = base
            }
            close(cmd_d)

            f_count = 0
            while ((cmd_f | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                f_count++
                f_list[f_count] = base
            }
            close(cmd_f)

            for (d = 1; d <= d_count; d++) print "  + " d_list[d] "/" > out_tmp
            for (f = 1; f <= f_count; f++) print "  - " f_list[f] > out_tmp

            for (i = tree_end_idx; i <= total; i++) print lines[i] > out_tmp
            close(out_tmp)

            printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
            printf "select %s.1,%s.1\n", root_idx, root_idx
            printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
        }'
    }}

# In-place refresh of directory node under cursor (preserves all user edits, notes, and other roots)
define-command -override -hidden \
    kiki-tree-refresh %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-refresh-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-refresh-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Find closest directory at or above current line
            target_idx = cur
            while (target_idx >= 1 && lines[target_idx] ~ /^[ \t]*#/ && get_indent(lines[target_idx]) > 0) {
                target_idx--
            }

            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            # If on file, walk up to its parent directory
            if (t_line !~ /\/[ \t]*$/ && target_idx > 1) {
                for (i = target_idx - 1; i >= 1; i--) {
                    if (get_indent(lines[i]) < t_indent && lines[i] ~ /\/[ \t]*$/) {
                        target_idx = i
                        t_line = lines[target_idx]
                        t_indent = get_indent(t_line)
                        clean_t = get_clean_name(t_line)
                        break
                    }
                }
            }

            full_p = resolve_full_path(lines, target_idx)

            # Check if directory exists
            check_d = "test -d \"" full_p "\" && echo 1 || echo 0"
            check_d | getline is_dir
            close(check_d)

            if (!is_dir) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # If node is currently collapsed, do nothing or expand it
            is_collapsed = (t_line ~ /^[ \t]*\+ /)
            if (is_collapsed) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Find child lines to replace
            end_idx = target_idx + 1
            while (end_idx <= total && get_indent(lines[end_idx]) > t_indent && lines[end_idx] !~ /^[ \t]*#/) {
                end_idx++
            }

            out_tmp = tmp_file ".out"
            for (i = 1; i <= target_idx; i++) print lines[i] > out_tmp

            child_indent = ""
            for (sp = 1; sp <= (t_indent + 2); sp++) child_indent = child_indent " "

            if (hidden == "true") {
                cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
            } else {
                cmd_d = "find \"" full_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".*\" 2>/dev/null | sort -f"
                cmd_f = "find \"" full_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".*\" 2>/dev/null | sort -f"
            }

            d_count = 0
            while ((cmd_d | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                d_count++
                d_list[d_count] = base
            }
            close(cmd_d)

            f_count = 0
            while ((cmd_f | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                f_count++
                f_list[f_count] = base
            }
            close(cmd_f)

            for (d = 1; d <= d_count; d++) print child_indent "+ " d_list[d] "/" > out_tmp
            for (f = 1; f <= f_count; f++) print child_indent "- " f_list[f] > out_tmp

            for (i = end_idx; i <= total; i++) print lines[i] > out_tmp
            close(out_tmp)

            printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
            printf "select %s.1,%s.1\n", cur, cur
            printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
        }'
    }}

# Toggle hidden files (updates setting and refreshes current node in-place)
define-command -override -hidden \
    kiki-tree-toggle-hidden %{ evaluate-commands %sh{
        if [ "$kak_opt_kiki_tree_show_hidden" = "true" ]; then
            printf 'set-option buffer kiki_tree_show_hidden false\n'
            printf 'echo "kiki-file-tree: hiding dotfiles"\n'
        else
            printf 'set-option buffer kiki_tree_show_hidden true\n'
            printf 'echo "kiki-file-tree: showing dotfiles"\n'
        fi
        printf 'kiki-tree-refresh\n'
    }}

# Recursively expand directory at cursor (or root node)
define-command -override -hidden \
    kiki-tree-expand-recursive %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-expand-recursive-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-expand-recursive-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        function expand_dir_rec(dir_path, ind_level,    cmd_d, cmd_f, e, base, d_cnt, f_cnt, d_arr, f_arr, d_i, f_i, child_indent, sp) {
            child_indent = ""
            for (sp = 1; sp <= ind_level; sp++) child_indent = child_indent " "

            if (hidden == "true") {
                cmd_d = "find \"" dir_path "\" -mindepth 1 -maxdepth 1 -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                cmd_f = "find \"" dir_path "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
            } else {
                cmd_d = "find \"" dir_path "\" -mindepth 1 -maxdepth 1 -type d ! -name \".*\" 2>/dev/null | sort -f"
                cmd_f = "find \"" dir_path "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".*\" 2>/dev/null | sort -f"
            }

            d_cnt = 0
            while ((cmd_d | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                d_cnt++
                d_arr[d_cnt] = base
            }
            close(cmd_d)

            f_cnt = 0
            while ((cmd_f | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                f_cnt++
                f_arr[f_cnt] = base
            }
            close(cmd_f)

            for (d_i = 1; d_i <= d_cnt; d_i++) {
                print child_indent "- " d_arr[d_i] "/" > out_tmp
                expand_dir_rec(dir_path "/" d_arr[d_i], ind_level + 2)
            }
            for (f_i = 1; f_i <= f_cnt; f_i++) {
                print child_indent "- " f_arr[f_i] > out_tmp
            }
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Find target directory at or above current line if on comment/file
            target_idx = cur
            while (target_idx >= 1 && lines[target_idx] ~ /^[ \t]*#/ && get_indent(lines[target_idx]) > 0) {
                target_idx--
            }

            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            # If on file, walk up to its parent directory
            if (t_line !~ /\/[ \t]*$/ && target_idx > 1) {
                for (i = target_idx - 1; i >= 1; i--) {
                    if (get_indent(lines[i]) < t_indent && lines[i] ~ /\/[ \t]*$/) {
                        target_idx = i
                        t_line = lines[target_idx]
                        t_indent = get_indent(t_line)
                        clean_t = get_clean_name(t_line)
                        break
                    }
                }
            }

            full_p = resolve_full_path(lines, target_idx)

            # Check if directory exists
            check_d = "test -d \"" full_p "\" && echo 1 || echo 0"
            check_d | getline is_dir
            close(check_d)

            if (!is_dir) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Find existing child lines to replace
            end_idx = target_idx + 1
            while (end_idx <= total && get_indent(lines[end_idx]) > t_indent && lines[end_idx] !~ /^[ \t]*#/) {
                end_idx++
            }

            out_tmp = tmp_file ".out"
            for (i = 1; i < target_idx; i++) print lines[i] > out_tmp

            # Output expanded target directory header
            expanded_prefix = ""
            for (sp = 1; sp <= t_indent; sp++) expanded_prefix = expanded_prefix " "
            expanded_prefix = expanded_prefix "- "

            disp_name = clean_t
            if (disp_name !~ /\/$/) disp_name = disp_name "/"
            print expanded_prefix disp_name > out_tmp

            # Recursively populate subfolders and files
            expand_dir_rec(full_p, t_indent + 2)

            for (i = end_idx; i <= total; i++) print lines[i] > out_tmp
            close(out_tmp)

            printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
            printf "select %s.1,%s.1\n", target_idx, target_idx
            printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
        }'
    }}

# Move to parent folder on <c-l> (replaces current tree branch with parent directory)
define-command -override -hidden \
    kiki-tree-parent %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-parent-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-parent-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Find root header of this tree branch
            root_idx = cur
            t_indent = get_indent(lines[cur])
            if (t_indent > 0) {
                for (i = cur - 1; i >= 1; i--) {
                    if (get_indent(lines[i]) == 0 && lines[i] !~ /^[ \t]*#/) {
                        root_idx = i
                        break
                    }
                }
            }

            root_line = lines[root_idx]
            clean_root = get_clean_name(root_line)
            if (clean_root == "" || root_line ~ /^[ \t]*#/) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            full_p = expand_path(clean_root)
            sub(/\/$/, "", full_p)

            # Compute parent path using shell dirname
            cmd_parent = "dirname \"" full_p "\""
            cmd_parent | getline parent_p
            close(cmd_parent)

            if (parent_p == "" || parent_p == full_p) {
                printf "echo \"kiki-file-tree: already at root directory: %s\"\n", full_p
                system("rm -f \"" tmp_file "\"")
                exit
            }

            sub(/\/$/, "", parent_p)
            parent_p_display = parent_p "/"

            tree_end_idx = root_idx + 1
            while (tree_end_idx <= total && get_indent(lines[tree_end_idx]) > 0 && lines[tree_end_idx] !~ /^[ \t]*#/) {
                tree_end_idx++
            }

            out_tmp = tmp_file ".out"
            for (i = 1; i < root_idx; i++) print lines[i] > out_tmp

            print "- " parent_p_display > out_tmp

            if (hidden == "true") {
                cmd_d = "find \"" parent_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
                cmd_f = "find \"" parent_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".\" ! -name \"..\" 2>/dev/null | sort -f"
            } else {
                cmd_d = "find \"" parent_p "\" -mindepth 1 -maxdepth 1 -type d ! -name \".*\" 2>/dev/null | sort -f"
                cmd_f = "find \"" parent_p "\" -mindepth 1 -maxdepth 1 ! -type d ! -name \".*\" 2>/dev/null | sort -f"
            }

            d_count = 0
            while ((cmd_d | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                d_count++
                d_list[d_count] = base
            }
            close(cmd_d)

            f_count = 0
            while ((cmd_f | getline e) > 0) {
                base = e
                sub(/^.*\//, "", base)
                f_count++
                f_list[f_count] = base
            }
            close(cmd_f)

            for (d = 1; d <= d_count; d++) print "  + " d_list[d] "/" > out_tmp
            for (f = 1; f <= f_count; f++) print "  - " f_list[f] > out_tmp

            for (i = tree_end_idx; i <= total; i++) print lines[i] > out_tmp
            close(out_tmp)

            printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
            printf "select %s.1,%s.1\n", root_idx, root_idx
            printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
        }'
    }}

# Multi-selection level narrowing (-)
# 1st step: remove subtrees without selections
# 2nd step: remove siblings without selections
define-command -override -hidden \
    kiki-tree-narrow %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-narrow-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-narrow-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        selections_desc="$kak_selections_desc"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v sel_desc="$selections_desc" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
                indents[total] = get_indent(line)
            }
            close(tmp_file)

            if (total == 0) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            # Parse selected lines from selections_desc (handles spaces and colons: "1.1,1.5 4.1,4.10" or "1.1,1.5:4.1,4.10")
            n_sels = split(sel_desc, sel_chunks, /[ :]+/)
            has_explicit_sel = 0
            for (s = 1; s <= n_sels; s++) {
                if (sel_chunks[s] == "") continue
                split(sel_chunks[s], coords, ",")
                split(coords[1], start_c, ".")
                split(coords[2], end_c, ".")
                sl = start_c[1] + 0
                el = end_c[1] + 0
                if (sl > el) { tmp_l = sl; sl = el; el = tmp_l }
                for (l = sl; l <= el; l++) {
                    if (l >= 1 && l <= total) {
                        is_selected[l] = 1
                        has_explicit_sel = 1
                    }
                }
            }

            if (!has_explicit_sel && cur >= 1 && cur <= total) {
                is_selected[cur] = 1
            }

            # Find root and parent index for each line in the buffer
            # Indent 0 lines that are not comments represent tree roots
            curr_root = 0
            for (i = 1; i <= total; i++) {
                parent[i] = 0
                root_of[i] = 0
                if (lines[i] ~ /^[ ]*#/) continue

                if (indents[i] == 0) {
                    curr_root = i
                    root_of[i] = i
                } else {
                    root_of[i] = curr_root
                    for (j = i - 1; j >= 1; j--) {
                        if (indents[j] < indents[i] && lines[j] !~ /^[ ]*#/) {
                            parent[i] = j
                            break
                        }
                    }
                }
            }

            # Find which roots contain active selections
            for (i = 1; i <= total; i++) {
                if (is_selected[i] && root_of[i] > 0) {
                    root_has_sel[root_of[i]] = 1
                }
            }

            # If a directory node is selected (e.g. from filtering with %<a-s><a-k>),
            # treat all its nested children as selected/kept
            for (i = 1; i <= total; i++) {
                if (is_selected[i] && lines[i] ~ /\/$/) {
                    for (j = i + 1; j <= total && indents[j] > indents[i]; j++) {
                        if (lines[j] !~ /^[ ]*#/) {
                            is_selected[j] = 1
                        }
                    }
                }
            }

            # Calculate has_sel for each node and propagate upwards to parents
            for (i = 1; i <= total; i++) {
                has_sel[i] = (is_selected[i] ? 1 : 0)
            }
            for (i = total; i >= 1; i--) {
                p = parent[i]
                if (p > 0 && has_sel[i]) has_sel[p] = 1
            }

            # Step 1 check within selected roots:
            # Unselected subtrees (folders with no selections) or unselected direct children under the root
            has_step1_removals = 0
            for (i = 1; i <= total; i++) {
                r = root_of[i]
                if (r > 0 && root_has_sel[r] && indents[i] > 0 && !has_sel[i]) {
                    p = parent[i]
                    if (lines[i] ~ /\/$/ || (p > 0 && lines[p] ~ /\/$/ && indents[p] == 0)) {
                        has_step1_removals = 1
                        break
                    }
                }
            }

            out_tmp = tmp_file ".out"

            # Determine the target root to keep/narrow:
            # If multiple roots have selections, pick the first selected root or cursor root
            target_root = 0
            if (cur >= 1 && cur <= total && root_of[cur] > 0 && root_has_sel[root_of[cur]]) {
                target_root = root_of[cur]
            } else {
                for (i = 1; i <= total; i++) {
                    if (root_has_sel[i]) {
                        target_root = i
                        break
                    }
                }
            }
            if (target_root == 0 && cur >= 1 && cur <= total) {
                target_root = root_of[cur]
            }

            if (has_step1_removals) {
                # Stage 1: Remove unselected subtrees (folders with no selections) and unselected direct children
                # Only within target_root
                for (i = 1; i <= total; i++) {
                    if (root_of[i] == target_root && indents[i] > 0 && !has_sel[i]) {
                        p = parent[i]
                        if (lines[i] ~ /\/$/ || (p > 0 && lines[p] ~ /\/$/ && indents[p] == 0)) {
                            remove_stage1[i] = 1
                        }
                    }
                }
                for (i = 1; i <= total; i++) {
                    p = parent[i]
                    if (p > 0 && remove_stage1[p]) remove_stage1[i] = 1
                }

                out_count = 0
                for (i = 1; i <= total; i++) {
                    # Preserve all lines outside target_root; narrow only lines inside target_root
                    if (root_of[i] != target_root) {
                        out_count++
                        out_lines[out_count] = lines[i]
                        if (is_selected[i]) new_sel[out_count] = 1
                    } else if (!remove_stage1[i]) {
                        out_count++
                        out_lines[out_count] = lines[i]
                        if (is_selected[i]) new_sel[out_count] = 1
                    }
                }
            } else {
                # Stage 2: Remove unselected inner siblings within the selected directories of target_root
                for (i = 1; i <= total; i++) {
                    if (root_of[i] == target_root && is_selected[i]) {
                        keep[i] = 1
                        # Mark all ancestors
                        p = parent[i]
                        while (p > 0) {
                            keep[p] = 1
                            p = parent[p]
                        }
                        # If selected item is an expanded directory, keep all its descendants
                        if (lines[i] ~ /^[ ]*- / && lines[i] ~ /\/$/) {
                            for (j = i + 1; j <= total && indents[j] > indents[i]; j++) {
                                keep[j] = 1
                            }
                        }
                    }
                }

                out_count = 0
                for (i = 1; i <= total; i++) {
                    # Preserve all lines outside target_root; narrow only lines inside target_root
                    if (root_of[i] != target_root) {
                        out_count++
                        out_lines[out_count] = lines[i]
                        if (is_selected[i]) new_sel[out_count] = 1
                    } else if (lines[i] ~ /^[ ]*#/ || keep[i]) {
                        out_count++
                        out_lines[out_count] = lines[i]
                        if (is_selected[i]) new_sel[out_count] = 1
                    }
                }
            }

            for (i = 1; i <= out_count; i++) {
                print out_lines[i] > out_tmp
            }
            close(out_tmp)

            # Build selection desc for Kakoune to restore selections on active items
            new_sel_desc = ""
            for (i = 1; i <= out_count; i++) {
                if (new_sel[i]) {
                    chunk = i ".1," i ".1"
                    if (new_sel_desc == "") new_sel_desc = chunk
                    else new_sel_desc = new_sel_desc " " chunk
                }
            }
            if (new_sel_desc == "") new_sel_desc = "1.1,1.1"

            printf "execute-keys %%{<percent>|cat \"%s\"<ret>}\n", out_tmp
            printf "select %s\n", new_sel_desc
            printf "nop %%sh{ rm -f \"%s\" \"%s\" }\n", tmp_file, out_tmp
        }'
    }}

# Drop to shell from tree (suspends Kakoune in the directory under the cursor)
define-command -override -hidden \
    kiki-tree-drop-to-shell %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-drop-to-shell-do "%s"\n' "$tmp_file"
    }}

define-command -override -hidden -params 1 \
    kiki-tree-drop-to-shell-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur="$kak_cursor_line"
        home_dir="$HOME"

        awk -v cur="$cur" -v tmp_file="$tmp_file" -v home="$home_dir" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            target_idx = cur
            while (target_idx >= 1 && lines[target_idx] ~ /^[ \t]*#/ && get_indent(lines[target_idx]) > 0) {
                target_idx--
            }

            t_line = lines[target_idx]
            t_indent = get_indent(t_line)

            if (t_line !~ /\/[ \t]*$/ && target_idx > 1) {
                for (i = target_idx - 1; i >= 1; i--) {
                    if (get_indent(lines[i]) < t_indent && lines[i] ~ /\/[ \t]*$/) {
                        target_idx = i
                        break
                    }
                }
            }

            full_p = resolve_full_path(lines, target_idx)
            system("rm -f \"" tmp_file "\"")

            printf "kiki-drop-to-shell %%{%s}\n", full_p
        }'
    }}

# Resolve path helper for tree nodes (used by kiki-edit, kiki-cd, kiki-drop-to-shell, kiki-path-dispatch)
define-command -override -hidden -params 1 \
    -docstring "kiki-tree-resolve-path <callback-cmd>: resolve the full hierarchical path under cursor in tree and call <callback-cmd> <resolved-path>" \
    kiki-tree-resolve-path %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-resolve-path-do "%s" %%{%s}\n' "$tmp_file" "$1"
    }}

define-command -override -hidden -params 2 \
    kiki-tree-resolve-path-do %{ evaluate-commands %sh{
        tmp_file="$1"
        callback="$2"
        cur="$kak_cursor_line"
        home_dir="$HOME"

        awk -v cur="$cur" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" -v cb="$callback" '
        function expand_tabs(str, tabstop,    res, len, i, c, col, sp, k) {
            if (!tabstop) tabstop = 4
            res = ""
            col = 0
            len = length(str)
            for (i = 1; i <= len; i++) {
                c = substr(str, i, 1)
                if (c == "\t") {
                    sp = tabstop - (col % tabstop)
                    for (k = 1; k <= sp; k++) res = res " "
                    col += sp
                } else {
                    res = res c
                    col += 1
                }
            }
            return res
        }
        function get_indent(str,    s, ind, len, i, rest) {
            s = expand_tabs(str, 4)
            ind = 0
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) == " ") ind += 1
                else break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- )/) {
                rest = substr(rest, 3)
                while (substr(rest, 1, 1) == " ") {
                    ind += 1
                    rest = substr(rest, 2)
                }
            }
            return ind
        }
        function get_clean_name(str,    s, len, i, rest) {
            s = expand_tabs(str, 4)
            len = length(s)
            for (i = 1; i <= len; i++) {
                if (substr(s, i, 1) != " ") break
            }
            rest = substr(s, i)
            while (rest ~ /^(\+ |- | )/) {
                if (rest ~ /^ /) rest = substr(rest, 2)
                else if (rest ~ /^(\+ |- )/) rest = substr(rest, 3)
            }
            if (rest != "/") sub(/\/$/, "", rest)
            return rest
        }
        function expand_path(path,    p, full_real) {
            if (path ~ /^~\//) p = home "/" substr(path, 3);
            else if (path == "~") p = home;
            else if (path !~ /^\//) p = pwd "/" path;
            else p = path;
            cmd_real = "cd \"" p "\" 2>/dev/null && pwd || (cd \"$(dirname \"" p "\")\" 2>/dev/null && echo \"$(pwd)/$(basename \"" p "\")\" || echo \"" p "\")";
            cmd_real | getline full_real;
            close(cmd_real);
            return (full_real != "") ? full_real : p;
        }

        function resolve_full_path(lines, target_idx,    t_line, t_indent, clean_t, path_count, path_arr, req_indent, i, ind, root_path, full_p) {
            t_line = lines[target_idx]
            t_indent = get_indent(t_line)
            clean_t = get_clean_name(t_line)

            if (t_indent == 0) return expand_path(clean_t)

            path_count = 1
            path_arr[path_count] = clean_t
            req_indent = t_indent
            for (i = target_idx - 1; i >= 1; i--) {
                ind = get_indent(lines[i])
                if (ind < req_indent && lines[i] !~ /^[ \t]*#/) {
                    if (ind > 0 && lines[i] !~ /\/[ \t]*$/) continue
                    path_count++
                    path_arr[path_count] = get_clean_name(lines[i])
                    req_indent = ind
                    if (ind == 0) break
                }
            }
            root_path = expand_path(path_arr[path_count])
            full_p = root_path
            for (i = path_count - 1; i >= 1; i--) {
                full_p = (full_p == "/") ? "/" path_arr[i] : (full_p "/" path_arr[i])
            }
            return full_p
        }

        BEGIN {
            total = 0
            while ((getline line < tmp_file) > 0) {
                total++
                lines[total] = line
            }
            close(tmp_file)

            if (cur < 1 || cur > total) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            t_line = lines[cur]
            clean_t = get_clean_name(t_line)

            if (clean_t == "" || t_line ~ /^[ \t]*#/) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            full_p = resolve_full_path(lines, cur)
            system("rm -f \"" tmp_file "\"")

            printf "%s %%{%s}\n", cb, full_p
        }'
    }}

# Close tree buffers
define-command -override -docstring "kiki-close-tree-buffers: close all file tree buffers" \
    kiki-close-tree-buffers %{
        kiki-close-buffers-matching tree
    }
