# Kiki File Tree Navigation & Manipulation

declare-option -docstring "Show hidden/dot files in kiki-file-tree" bool kiki_tree_show_hidden false
declare-option -hidden bool kiki_tree_git_overlay false
declare-option -hidden line-specs kiki_tree_git_flags
declare-option -hidden range-specs kiki_tree_git_ranges
declare-option -hidden str-list kiki_tree_overlay_roots

# Set buffer type and local hooks/keys for kiki-file-tree scratch buffers and tree files
hook -group kiki global BufCreate \*kiki-file-tree\* %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
    map buffer normal v ':kiki-tree-git-overlay<ret>' -docstring 'Toggle git status overlay (highlight + flag)'
    map buffer normal f ':kiki-tree-filter-git<ret>' -docstring 'Filter to git-related files (expand subfolders)'
    map buffer normal g ':kiki-smart-git-popup<ret>' -docstring 'Open git action popup on file or directory'
}

hook -group kiki global BufOpenFile .*\.kikitree$ %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
}

hook -group kiki global BufSetOption filetype=kiki-tree %{
    set-option buffer kiki_buffer_type kiki-buffer
    set-option buffer filetype kiki
}

hook -group kiki global WinSetOption filetype=kiki-tree %{
    kiki-set-modeline kiki-buffer
    map window normal v ':kiki-tree-git-overlay<ret>' -docstring 'Toggle git status overlay (highlight + flag)'
    map window normal f ':kiki-tree-filter-git<ret>' -docstring 'Filter to git-related files (expand subfolders)'
    map window normal g ':kiki-smart-git-popup<ret>' -docstring 'Open git action popup on file or directory'
}

hook -group kiki-tree-overlay global WinSetOption filetype=kiki %{
    evaluate-commands %sh{
        case "$kak_bufname" in
            \*kiki-file-tree\*)
                printf 'map window normal v :kiki-tree-git-overlay<ret> -docstring "Toggle git status overlay (highlight + flag)"\n'
                printf 'map window normal f :kiki-tree-filter-git<ret> -docstring "Filter to git-related files (expand subfolders)"\n'
                printf 'map window normal g :kiki-smart-git-popup<ret> -docstring "Open git action popup on file or directory"\n'
                ;;
        esac
    }
}

# Automatically open kiki-file-tree when kakoune attempts to :edit a directory
hook -group kiki-tree-trap global RuntimeError '.*: is a directory' %{
    evaluate-commands %sh{
        raw="$kak_hook_param"
        path=$(printf '%s\n' "$raw" | sed -n -e "s/.*'edit':[[:space:]]*\(.*\):[[:space:]]*is a directory/\1/p" -e "s/.*:[[:space:]]*\(.*\):[[:space:]]*is a directory/\1/p" | head -n 1)
        path=$(printf '%s\n' "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^[\\\"'\''\`(<]*//' -e 's/[\\\"'\''\`)>]*$//')
        case "$path" in
            "~"/*) path="${HOME}/${path#"~"/}" ;;
            "~") path="${HOME}" ;;
        esac
        if [ -n "$path" ] && [ -d "$path" ]; then
            printf 'kiki-file-tree %%{%s}\n' "$path"
        fi
    }
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
        # Strip leading/trailing whitespace and optional prefix
        raw=$(printf '%s\n' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -n "$kak_opt_kiki_prefix" ]; then
            raw="${raw#"$kak_opt_kiki_prefix"}"
        fi
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
        printf 'set-option buffer kiki_buffer_type kiki-buffer\n'
        printf 'set-option buffer filetype kiki\n'
        printf 'kiki-set-modeline kiki-buffer\n'

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
        printf 'nop %%sh{ rm -f -- "%s" 2>/dev/null }\n' "$tmp_content"
    }}

# Open/toggle tree item at cursor (supports root nodes, subdirectories, files, and arbitrary new paths)
define-command -override -hidden -params 0..1 \
    kiki-tree-open %{ evaluate-commands %sh{
        mode="${1:-auto}"
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-open-do "%s" "%s"\n' "$tmp_file" "$mode"
    }}

define-command -override -hidden \
    kiki-tree-expand %{
        kiki-tree-open expand
    }

define-command -override -hidden \
    kiki-tree-collapse %{
        kiki-tree-open collapse
    }

define-command -override -hidden \
    kiki-tree-toggle %{
        kiki-tree-open toggle
    }

define-command -override -hidden -params 1..2 \
    kiki-tree-open-do %{ evaluate-commands %sh{
        tmp_file="$1"
        action_mode="${2:-auto}"
        cur="$kak_cursor_line"
        hidden="$kak_opt_kiki_tree_show_hidden"
        home_dir="$HOME"

        awk -v cur="$cur" -v hidden="$hidden" -v tmp_file="$tmp_file" -v home="$home_dir" -v pwd="$PWD" -v action_mode="$action_mode" '
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


            if (action_mode == "expand" && is_expanded) {
                system("rm -f \"" tmp_file "\"")
                exit
            }
            if (action_mode == "collapse" && !is_expanded) {
                system("rm -f \"" tmp_file "\"")
                exit
            }

            should_collapse = 0
            if (action_mode == "collapse") should_collapse = 1
            else if (action_mode == "expand") should_collapse = 0
            else should_collapse = is_expanded

            out_tmp = tmp_file ".out"

            if (should_collapse) {
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
                printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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
                printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
            }
        }'
        if [ -f "${tmp_file}.out" ] && [ "$kak_opt_kiki_tree_git_overlay" = "true" ]; then
            printf 'kiki-tree-git-overlay-refresh\n'
        fi
    }}

# Filter file tree to git-related files (confined to active tree branch around cursor)
define-command -override -docstring "kiki-tree-filter-git: filter tree to git-related files with subfolder expansion" \
    kiki-tree-filter-git %{ evaluate-commands %sh{
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-filter-git-do "%s" "%s"\n' "$tmp_file" "$kak_cursor_line"
    }}

define-command -override -hidden -params 1..2 \
    kiki-tree-filter-git-do %{ evaluate-commands %sh{
        tmp_file="$1"
        cur_line="${2:-1}"
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        out_filtered=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-filtered.XXXXXXXX)

        res=$(python3 - "$tmp_file" "$cur_line" "$HOME" "$PWD" "$out_filtered" << 'PYEOF'
import os, sys, subprocess
tmp_file = sys.argv[1]
try: cur_line = int(sys.argv[2])
except: cur_line = 1
home = sys.argv[3]
pwd = sys.argv[4]
out_file = sys.argv[5]

try:
    with open(tmp_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [l.rstrip('\r\n') for l in f]
except:
    sys.exit(1)

def get_indent(s):
    exp = s.replace("\t", "    ")
    ind = 0
    for ch in exp:
        if ch == " ": ind += 1
        else: break
    return ind

def is_tree_line(s):
    if not s.strip() or s.lstrip().startswith('#'):
        return False
    return s.lstrip().startswith('+ ') or s.lstrip().startswith('- ')

def find_tree_bounds(lines_arr, cur):
    cur_idx = cur - 1
    if cur_idx < 0 or cur_idx >= len(lines_arr):
        return 0, len(lines_arr)
    root_idx = cur_idx
    if is_tree_line(lines_arr[root_idx]):
        if get_indent(lines_arr[root_idx]) > 0:
            for i in range(cur_idx - 1, -1, -1):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    else:
        for i in range(cur_idx - 1, -1, -1):
            if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                root_idx = i
                break
        else:
            for i in range(cur_idx, len(lines_arr)):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    if not is_tree_line(lines_arr[root_idx]) or get_indent(lines_arr[root_idx]) != 0:
        return 0, len(lines_arr)
    tree_end = root_idx + 1
    while tree_end < len(lines_arr) and is_tree_line(lines_arr[tree_end]) and get_indent(lines_arr[tree_end]) > 0:
        tree_end += 1
    return root_idx, tree_end

def expand_path(p, home, pwd):
    if p.startswith("~/"): return home + p[1:]
    if p == "~": return home
    if p.startswith("/"): return p
    if p in (".", "./"): return pwd
    if p.startswith("./"): return pwd + "/" + p[2:]
    return pwd + "/" + p

def get_clean_name(s):
    t = s.lstrip()
    if t.startswith("+ "): t = t[2:].lstrip()
    elif t.startswith("- "): t = t[2:].lstrip()
    t = t.rstrip()
    if t.endswith("/") and len(t) > 1: t = t.rstrip("/")
    if t.startswith("/"): return t
    if "/" in t: t = t.split("/")[-1]
    return t

def norm(p):
    try: return os.path.realpath(p)
    except: return os.path.normpath(p)

tree_start, tree_end = find_tree_bounds(lines, cur_line)
if tree_start >= tree_end:
    sys.exit(1)

root_line = lines[tree_start]
clean_root = get_clean_name(root_line)
full_root = expand_path(clean_root, home, pwd)
norm_root = norm(full_root)

# Resolve git repository for this tree root only
try:
    top = subprocess.check_output(['git', '-C', norm_root, 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
except:
    sys.exit(2)

try:
    git_out = subprocess.check_output(['git', '-C', top, 'status', '--porcelain'], stderr=subprocess.DEVNULL).decode('utf-8')
except:
    sys.exit(2)

git_files = []
for s in git_out.splitlines():
    if len(s) < 4: continue
    f = s[3:].strip()
    if ' -> ' in f: f = f.split(' -> ')[-1]
    abs_f = norm(os.path.join(top, f))
    if abs_f == norm_root or abs_f.startswith(norm_root.rstrip('/') + '/'):
        git_files.append(abs_f)

if not git_files:
    sys.exit(3)

def build_tree(file_list, root):
    root_node = {}
    root_stripped = root.rstrip("/")
    for f in sorted(file_list):
        rel = f[len(root_stripped)+1:] if f.startswith(root_stripped + "/") else os.path.basename(f)
        parts = [p for p in rel.split("/") if p]
        cur = root_node
        for part in parts:
            if part not in cur:
                cur[part] = {}
            cur = cur[part]
    return root_node

def emit_tree(node, indent, out_list):
    dirs = sorted(k for k, v in node.items() if v)
    files = sorted(k for k, v in node.items() if not v)
    for d in dirs:
        out_list.append(f"{indent}+ {d}/")
        emit_tree(node[d], indent + "  ", out_list)
    for f in files:
        out_list.append(f"{indent}- {f}")

filtered_slice = [f"- {full_root.rstrip('/')}/"]
root_node = build_tree(git_files, norm_root)
emit_tree(root_node, "  ", filtered_slice)

# Splice filtered slice into lines, preserving everything outside this tree branch
new_lines = lines[:tree_start] + filtered_slice + lines[tree_end:]

with open(out_file, 'w', encoding='utf-8') as out:
    for l in new_lines:
        out.write(l + "\n")

print(out_file)
print(str(tree_start + 1))
PYEOF
)
        rc=$?
        if [ $rc -ne 0 ]; then
            [ -n "$tmp_file" ] && rm -f -- "$tmp_file" 2>/dev/null || true
            [ -n "$out_filtered" ] && rm -f -- "$out_filtered" 2>/dev/null || true
            if [ $rc -eq 3 ]; then
                printf '%s %%{ echo -markup "{yellow}kiki-tree: no git files in current tree" }\n' "$eval_cmd"
            else
                printf '%s %%{ echo -markup "{yellow}kiki-tree: not a git tree" }\n' "$eval_cmd"
            fi
            exit 0
        fi

        filtered_file=$(printf '%s\n' "$res" | head -n 1)
        new_line=$(printf '%s\n' "$res" | tail -n 1)
        [ -z "$new_line" ] && new_line=1

        printf '%s %%{ execute-keys %%{<percent>|cat "%s"<ret>}; select %s.1,%s.1; nop %%sh{ rm -f -- "%s" "%s" 2>/dev/null } }\n' "$eval_cmd" "$filtered_file" "$new_line" "$new_line" "$tmp_file" "$out_filtered"
        # refresh gutter if overlay is on (new buffer content)
        if [ "$kak_opt_kiki_tree_git_overlay" = "true" ]; then
            printf '%s %%{ kiki-tree-git-overlay-refresh }\n' "$eval_cmd"
        fi
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
            printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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

            if (cur < 1 || cur > total || lines[cur] ~ /^[ \t]*$/) {
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
            printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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
            printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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
            printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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
            printf "nop %%sh{ rm -f -- \"%s\" \"%s\" 2>/dev/null }\n", tmp_file, out_tmp
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

# Rotate among modified/changed files in the file tree (direction 1 = next, -1 = prev)
define-command -override -hidden -params 1 \
    kiki-tree-rotate-modified-file %{ evaluate-commands %sh{
        dir="$1"
        tmp_file=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        printf 'write -force "%s"\n' "$tmp_file"
        printf 'kiki-tree-rotate-modified-file-do "%s" "%s"\n' "$dir" "$tmp_file"
    }}

define-command -override -hidden -params 2 \
    kiki-tree-rotate-modified-file-do %{ evaluate-commands %sh{
        dir="$1"
        tmp_file="$2"
        cur="$kak_cursor_line"
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        # 1. Collect roots and find git repo status
        status_dump=$(mktemp "${TMPDIR:-/tmp}"/kiki-git-status.XXXXXXXX)
        while IFS= read -r line; do
            case "$line" in
                "- "*|"+ "*)
                    r="${line#[+-] }"
                    r="${r%/}"
                    case "$r" in
                        "~"/*) r="${HOME}/${r#"~"/}" ;;
                        "~") r="${HOME}" ;;
                        /*) ;;
                        "."|"./") r="${PWD}" ;;
                        *) r="${PWD}/${r#./}" ;;
                    esac
                    [ -d "$r" ] && top=$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)
                    if [ -n "$top" ]; then
                        git -C "$top" status --porcelain 2>/dev/null | while IFS= read -r s; do
                            f=$(printf '%s\n' "$s" | cut -c4- | sed -e 's/.*-> //')
                            printf '%s/%s\n' "$top" "$f"
                        done >> "$status_dump"
                    fi
                    ;;
            esac
        done < "$tmp_file"

        # If no roots matched in tree lines, check buffer repo or PWD
        if [ ! -s "$status_dump" ]; then
            top=""
            [ -n "$kak_opt_kiki_tree_git_repo" ] && [ -d "$kak_opt_kiki_tree_git_repo" ] && top="$kak_opt_kiki_tree_git_repo"
            [ -z "$top" ] && top=$(git rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$top" ]; then
                git -C "$top" status --porcelain 2>/dev/null | while IFS= read -r s; do
                    f=$(printf '%s\n' "$s" | cut -c4- | sed -e 's/.*-> //')
                    printf '%s/%s\n' "$top" "$f"
                done >> "$status_dump"
            fi
        fi

        # Script extracts modified files, picks next target according to direction,
        # and expands any collapsed parent directories along the path so the target file is visible.
        out_tree=$(mktemp "${TMPDIR:-/tmp}"/kiki-tree-buf.XXXXXXXX)
        hidden="${kak_opt_kiki_tree_show_hidden:-false}"

        res=$(python3 - "$cur" "$dir" "$tmp_file" "$status_dump" "$out_tree" "$hidden" "$HOME" "$PWD" << 'EOF'
import sys, os

cur = int(sys.argv[1])
direction = int(sys.argv[2])
tmp_file = sys.argv[3]
status_file = sys.argv[4]
out_tree = sys.argv[5]
hidden = (sys.argv[6].lower() == 'true')
home = sys.argv[7]
pwd = sys.argv[8]

def clean_exit(res_str):
    for f in (tmp_file, status_file):
        try:
            os.remove(f)
        except OSError:
            pass
    print(res_str)
    sys.exit(0)

try:
    with open(tmp_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [line.rstrip('\r\n') for line in f]
except Exception:
    clean_exit('0||')

try:
    with open(status_file, 'r', encoding='utf-8', errors='replace') as f:
        status_lines = [line.rstrip('\r\n') for line in f if line.strip()]
except Exception:
    status_lines = []

if not lines:
    clean_exit('0||')

def expand_tabs(s, tabstop=4):
    res = []
    col = 0
    for c in s:
        if c == '\t':
            sp = tabstop - (col % tabstop)
            res.append(' ' * sp)
            col += sp
        else:
            res.append(c)
            col += 1
    return ''.join(res)

def get_indent(s):
    s = expand_tabs(s)
    ind = len(s) - len(s.lstrip(' '))
    rest = s.lstrip(' ')
    while rest.startswith('+ ') or rest.startswith('- '):
        rest = rest[2:]
        spaces = len(rest) - len(rest.lstrip(' '))
        ind += spaces
        rest = rest.lstrip(' ')
    return ind

def get_clean_name(s):
    s = expand_tabs(s).strip()
    while s.startswith('+ ') or s.startswith('- ') or s.startswith(' '):
        if s.startswith(' '):
            s = s[1:]
        elif s.startswith('+ ') or s.startswith('- '):
            s = s[2:]
    if s != '/' and s.endswith('/'):
        s = s[:-1]
    return s

def expand_path(p):
    if p.startswith('~/'):
        p = os.path.join(home, p[2:])
    elif p == '~':
        p = home
    elif p in ('.', './'):
        p = pwd
    elif p.startswith('./'):
        p = os.path.join(pwd, p[2:])
    elif not p.startswith('/'):
        p = os.path.join(pwd, p)
    try:
        return os.path.realpath(p)
    except Exception:
        return p

def resolve_full_path(lines_arr, idx):
    line = lines_arr[idx]
    ind = get_indent(line)
    clean = get_clean_name(line)
    if ind == 0:
        return expand_path(clean)
    path_arr = [clean]
    req_ind = ind
    for i in range(idx - 1, -1, -1):
        l = lines_arr[i]
        if not l.strip() or l.lstrip().startswith('#'):
            continue
        curr_ind = get_indent(l)
        if curr_ind < req_ind:
            if curr_ind > 0 and not l.strip().endswith('/'):
                continue
            path_arr.append(get_clean_name(l))
            req_ind = curr_ind
            if curr_ind == 0:
                break
    root = expand_path(path_arr[-1])
    full = root
    for comp in reversed(path_arr[:-1]):
        full = os.path.join(full, comp)
    return full

def expand_directory_node(lines_arr, node_idx):
    t_line = lines_arr[node_idx]
    t_ind = get_indent(t_line)
    clean_t = get_clean_name(t_line)
    full_p = resolve_full_path(lines_arr, node_idx)

    sp_str = ' ' * t_ind
    disp_name = full_p if t_ind == 0 else clean_t
    if not disp_name.endswith('/'):
        disp_name += '/'
    lines_arr[node_idx] = f'{sp_str}- {disp_name}'

    try:
        entries = sorted(os.listdir(full_p), key=lambda x: x.lower())
    except Exception:
        entries = []
    dirs = []
    files = []
    for e in entries:
        if not hidden and e.startswith('.'):
            continue
        ep = os.path.join(full_p, e)
        if os.path.isdir(ep):
            dirs.append(e)
        else:
            files.append(e)
    child_ind_str = ' ' * (t_ind + 2)
    child_lines = []
    for d in dirs:
        child_lines.append(f'{child_ind_str}+ {d}/')
    for f in files:
        child_lines.append(f'{child_ind_str}- {f}')

    lines_arr[node_idx+1:node_idx+1] = child_lines

def reveal_target_path(lines_arr, target_path):
    target_path = expand_path(target_path)
    while True:
        found_target_idx = None
        for i, l in enumerate(lines_arr):
            if l.strip() and not l.lstrip().startswith('#') and not l.strip().endswith('/'):
                if resolve_full_path(lines_arr, i) == target_path:
                    found_target_idx = i
                    break
        if found_target_idx is not None:
            return found_target_idx

        best_dir_idx = None
        best_dir_path = ''
        for i, l in enumerate(lines_arr):
            if l.strip() and not l.lstrip().startswith('#') and (l.strip().endswith('/') or get_indent(l) == 0):
                dpath = resolve_full_path(lines_arr, i)
                if not dpath.endswith('/'):
                    dpath += '/'
                if target_path.startswith(dpath):
                    if len(dpath) > len(best_dir_path):
                        best_dir_path = dpath
                        best_dir_idx = i

        if best_dir_idx is None:
            return None

        l = lines_arr[best_dir_idx]
        if l.lstrip().startswith('+ '):
            expand_directory_node(lines_arr, best_dir_idx)
        else:
            return None

def get_visible_line_for_path(lines_arr, target_path):
    target_path = expand_path(target_path)
    # 1. Exact file match
    for i, l in enumerate(lines_arr):
        if l.strip() and not l.lstrip().startswith('#') and not l.strip().endswith('/'):
            if resolve_full_path(lines_arr, i) == target_path:
                return i + 1, False
    # 2. Collapsed ancestor match
    best_idx = None
    best_path = ''
    for i, l in enumerate(lines_arr):
        if l.strip() and not l.lstrip().startswith('#') and (l.strip().endswith('/') or get_indent(l) == 0):
            dpath = resolve_full_path(lines_arr, i)
            if not dpath.endswith('/'):
                dpath += '/'
            if target_path.startswith(dpath):
                if len(dpath) > len(best_path):
                    best_path = dpath
                    best_idx = i
    if best_idx is not None:
        return best_idx + 1, True
    return 0, False

def is_tree_line(s):
    if not s.strip() or s.lstrip().startswith('#'):
        return False
    return s.lstrip().startswith('+ ') or s.lstrip().startswith('- ')

def find_tree_bounds(lines_arr, cur_line):
    cur_idx = cur_line - 1
    if cur_idx < 0 or cur_idx >= len(lines_arr):
        return 0, len(lines_arr)
    root_idx = cur_idx
    if is_tree_line(lines_arr[root_idx]):
        if get_indent(lines_arr[root_idx]) > 0:
            for i in range(cur_idx - 1, -1, -1):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    else:
        for i in range(cur_idx - 1, -1, -1):
            if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                root_idx = i
                break
        else:
            for i in range(cur_idx, len(lines_arr)):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    if not is_tree_line(lines_arr[root_idx]) or get_indent(lines_arr[root_idx]) != 0:
        return 0, len(lines_arr)
    tree_end = root_idx + 1
    while tree_end < len(lines_arr) and is_tree_line(lines_arr[tree_end]) and get_indent(lines_arr[tree_end]) > 0:
        tree_end += 1
    return root_idx, tree_end

# Confine rotation to the file tree branch around the cursor
tree_start, tree_end = find_tree_bounds(lines, cur)
tree_slice = lines[tree_start:tree_end]

if not tree_slice:
    clean_exit('0||')

# Normalize status files list
norm_status = []
for p in status_lines:
    ep = expand_path(p)
    if ep not in norm_status:
        norm_status.append(ep)

# Build sorted modified entries strictly within this file tree branch
mod_entries = []
for p in norm_status:
    ln, is_collapsed = get_visible_line_for_path(tree_slice, p)
    if ln > 0:
        buf_ln = tree_start + ln
        mod_entries.append((buf_ln, p, is_collapsed))

if not mod_entries:
    clean_exit('0||')

mod_entries.sort(key=lambda x: (x[0], x[1]))

cur_idx = None
for idx, (ln, p, _) in enumerate(mod_entries):
    if ln == cur:
        cur_idx = idx
        break

if direction > 0:
    if cur_idx is not None:
        next_idx = (cur_idx + 1) % len(mod_entries)
    else:
        next_idx = 0
        for idx, (ln, p, _) in enumerate(mod_entries):
            if ln > cur:
                next_idx = idx
                break
else:
    if cur_idx is not None:
        next_idx = (cur_idx - 1) % len(mod_entries)
    else:
        next_idx = len(mod_entries) - 1
        for idx in range(len(mod_entries) - 1, -1, -1):
            if mod_entries[idx][0] < cur:
                next_idx = idx
                break

chosen_target = mod_entries[next_idx][1]
orig_len = len(tree_slice)
final_slice_idx = reveal_target_path(tree_slice, chosen_target)

if final_slice_idx is None:
    clean_exit('0||')

target_line = tree_start + final_slice_idx + 1
tree_updated_file = ''

if len(tree_slice) != orig_len:
    lines = lines[:tree_start] + tree_slice + lines[tree_end:]
    try:
        with open(out_tree, 'w', encoding='utf-8') as f:
            for line in lines:
                f.write(line + '\n')
        tree_updated_file = out_tree
    except Exception:
        tree_updated_file = ''

clean_exit(f"{target_line}|{chosen_target}|{tree_updated_file}")
EOF
)

        target_line=$(printf '%s\n' "$res" | cut -d'|' -f1)
        target_path=$(printf '%s\n' "$res" | cut -d'|' -f2)
        out_updated=$(printf '%s\n' "$res" | cut -d'|' -f3)

        if [ "$target_line" -gt 0 ] 2>/dev/null && [ -n "$target_path" ]; then
            if [ -n "$out_updated" ] && [ -f "$out_updated" ]; then
                printf '%s %%{ execute-keys %%{<percent>|cat "%s"<ret>}; select %s.1,%s.1; kiki-tree-git-action %%{%s}; nop %%sh{ rm -f -- "%s" 2>/dev/null } }\n' "$eval_cmd" "$out_updated" "$target_line" "$target_line" "$target_path" "$out_updated"
            else
                [ -f "$out_tree" ] && rm -f "$out_tree"
                printf '%s %%{ select %s.1,%s.1; kiki-tree-git-action %%{%s} }\n' "$eval_cmd" "$target_line" "$target_line" "$target_path"
            fi
        else
            [ -f "$out_tree" ] && rm -f "$out_tree"
            printf '%s %%{ echo -markup "{yellow}[kiki-tree]{default} No modified files in file tree" }\n' "$eval_cmd"
        fi
    }}

# Toggle git status overlay (highlight + flag) on v key in file tree, scoped to current tree
define-command -override -docstring "kiki-tree-git-overlay: toggle git status highlight and flag overlay in file tree" \
    kiki-tree-git-overlay %{ evaluate-commands %sh{
        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-tree-git-overlay-do "%s" "%s" toggle %%opt{kiki_tree_overlay_roots}\n' "$tmp_buf" "$kak_cursor_line"
    }}

define-command -override -hidden -params 3.. \
    kiki-tree-git-overlay-do %{ evaluate-commands %sh{
        tmp_buf="$1"
        cur_line="${2:-1}"
        mode="$3"
        shift 3
        eval_cmd="evaluate-commands"
        [ -n "$kak_client" ] && eval_cmd="evaluate-commands -client %val{client}"

        res=$(python3 - "$tmp_buf" "$cur_line" "$mode" "$HOME" "$PWD" "$@" << 'PYEOF'
import os, sys, subprocess, shlex

tmp_file = sys.argv[1]
try: cur_line = int(sys.argv[2])
except: cur_line = 1
mode = sys.argv[3]
home = sys.argv[4]
pwd = sys.argv[5]
active_roots = sys.argv[6:]

try:
    with open(tmp_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [l.rstrip('\r\n') for l in f]
except:
    sys.exit(1)

def get_clean_name(s):
    t = s.lstrip()
    if t.startswith("+ "): t = t[2:].lstrip()
    elif t.startswith("- "): t = t[2:].lstrip()
    t = t.rstrip()
    if t.endswith("/") and len(t) > 1: t = t.rstrip("/")
    if t.startswith("/"): return t
    if "/" in t: t = t.split("/")[-1]
    return t

def get_indent(s):
    exp = s.replace("\t", "    ")
    ind = 0
    for ch in exp:
        if ch == " ": ind += 1
        else: break
    return ind

def is_tree_line(s):
    if not s.strip() or s.lstrip().startswith('#'):
        return False
    return s.lstrip().startswith('+ ') or s.lstrip().startswith('- ')

def find_tree_bounds(lines_arr, cur):
    cur_idx = cur - 1
    if cur_idx < 0 or cur_idx >= len(lines_arr):
        return 0, 0
    root_idx = cur_idx
    if is_tree_line(lines_arr[root_idx]):
        if get_indent(lines_arr[root_idx]) > 0:
            for i in range(cur_idx - 1, -1, -1):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    else:
        for i in range(cur_idx - 1, -1, -1):
            if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                root_idx = i
                break
        else:
            for i in range(cur_idx, len(lines_arr)):
                if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
                    root_idx = i
                    break
    if not is_tree_line(lines_arr[root_idx]) or get_indent(lines_arr[root_idx]) != 0:
        return 0, 0
    tree_end = root_idx + 1
    while tree_end < len(lines_arr) and is_tree_line(lines_arr[tree_end]) and get_indent(lines_arr[tree_end]) > 0:
        tree_end += 1
    return root_idx, tree_end

def find_all_trees(lines_arr):
    trees = []
    i = 0
    while i < len(lines_arr):
        if is_tree_line(lines_arr[i]) and get_indent(lines_arr[i]) == 0:
            start = i
            end = i + 1
            while end < len(lines_arr) and is_tree_line(lines_arr[end]) and get_indent(lines_arr[end]) > 0:
                end += 1
            trees.append((start, end))
            i = end
        else:
            i += 1
    return trees

def expand_path_py(p, home, pwd):
    if p.startswith("~/"): return home + p[1:]
    if p == "~": return home
    if p.startswith("/"): return p
    if p in (".", "./"): return pwd
    if p.startswith("./"): return pwd + "/" + p[2:]
    return pwd + "/" + p

def norm(p):
    try: return os.path.realpath(p)
    except: return os.path.normpath(p)

def resolve_full_path_py(all_lines, idx, home, pwd):
    try: t_line = all_lines[idx-1]
    except: return ""
    t_clean = get_clean_name(t_line)
    t_indent = get_indent(t_line)
    if t_indent == 0:
        return expand_path_py(t_clean, home, pwd)
    parts = [t_clean]
    cur_indent = t_indent
    for i in range(idx-2, -1, -1):
        line = all_lines[i]
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        ind = get_indent(line)
        if ind < cur_indent and line.rstrip().endswith('/'):
            parts.append(get_clean_name(line))
            cur_indent = ind
            if ind == 0:
                break
    parts = list(reversed(parts))
    root = expand_path_py(parts[0], home, pwd)
    full = root.rstrip("/")
    for p in parts[1:]:
        if p:
            full = full + "/" + p
    return full

def git_face_sym(code):
    c = (code + "  ")[:2]
    if c == "??": return ("magenta", "N")
    if c[0] == "A" and c[1] == " ": return ("green", "A")
    if c[0] == "M" and c[1] == " ": return ("green", "S")
    if c[1] == "M" or c[1] == "D": return ("yellow", "M")
    if c[0] == "R": return ("cyan", "R")
    if "C" in code or "U" in code: return ("red", "C")
    return None

severity = {"C": 5, "N": 4, "M": 3, "S": 3, "A": 3, "R": 2}

roots_set = set(active_roots)
t_start, t_end = find_tree_bounds(lines, cur_line)
cur_root = ""
if t_start < t_end:
    cur_root = norm(expand_path_py(get_clean_name(lines[t_start]), home, pwd))

if mode == "toggle":
    if cur_root:
        if cur_root in roots_set:
            roots_set.remove(cur_root)
            toggle_action = "off"
        else:
            roots_set.add(cur_root)
            toggle_action = "on"
    else:
        toggle_action = "noop"
else:
    toggle_action = "refresh"

all_trees = find_all_trees(lines)
active_tree_spans = []
for start, end in all_trees:
    r_clean = get_clean_name(lines[start])
    r_full = norm(expand_path_py(r_clean, home, pwd))
    if r_full in roots_set:
        active_tree_spans.append((start, end, r_full))

flag_entries = []
range_entries = []

for start, end, r_full in active_tree_spans:
    try:
        top = subprocess.check_output(['git', '-C', r_full, 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
        git_out = subprocess.check_output(['git', '-C', top, 'status', '--porcelain'], stderr=subprocess.DEVNULL).decode('utf-8')
    except Exception:
        continue

    status_map = {}
    for s in git_out.splitlines():
        if len(s) < 3: continue
        code = s[:2]
        f = s[3:].strip()
        if ' -> ' in f: f = f.split(' -> ')[-1]
        abs_f = norm(os.path.join(top, f))
        bs = git_face_sym(code)
        if bs:
            status_map[abs_f] = bs

    for idx in range(start + 1, end + 1):
        line = lines[idx - 1]
        s = line.lstrip()
        if not (s.startswith('+ ') or s.startswith('- ')):
            continue
        full = resolve_full_path_py(lines, idx, home, pwd)
        if not full: continue
        norm_full = norm(full)
        line_len = len(line)
        if line_len == 0: continue

        # 1. Visible file (- file)
        if not line.rstrip().endswith('/'):
            if norm_full in status_map:
                face, sym = status_map[norm_full]
                flag_entries.append(f"'{idx}|{{{face}}}{sym}'")
                range_entries.append(f"'{idx}.1,{idx}.{line_len}|{face}'")
        # 2. Collapsed folder (+ dir/)
        elif s.startswith('+ '):
            dir_prefix = norm_full.rstrip('/') + '/'
            best = None
            best_sev = -1
            for p, (face, sym) in status_map.items():
                if p == norm_full or p.startswith(dir_prefix):
                    sev = severity.get(sym, 0)
                    if sev > best_sev:
                        best_sev = sev
                        best = (face, sym)
            if best:
                face, sym = best
                flag_entries.append(f"'{idx}|{{{face}}}{sym}'")
                range_entries.append(f"'{idx}.1,{idx}.{line_len}|{face}'")

print(" ".join(shlex.quote(r) for r in sorted(roots_set)))
print(" ".join(flag_entries))
print(" ".join(range_entries))
print(toggle_action)
PYEOF
)
        [ -n "$tmp_buf" ] && rm -f -- "$tmp_buf" 2>/dev/null || true

        if [ -z "$res" ]; then
            exit 0
        fi

        roots_quoted=$(printf '%s\n' "$res" | sed -n '1p')
        flag_specs=$(printf '%s\n' "$res" | sed -n '2p')
        range_specs=$(printf '%s\n' "$res" | sed -n '3p')
        toggle_action=$(printf '%s\n' "$res" | sed -n '4p')

        # Clean legacy buffer regex highlighters if present
        cleanup="try %{ remove-highlighter buffer/kiki_tree_git_modified }; try %{ remove-highlighter buffer/kiki_tree_git_flag_modified }; try %{ remove-highlighter buffer/kiki_tree_git_staged }; try %{ remove-highlighter buffer/kiki_tree_git_flag_staged }; try %{ remove-highlighter buffer/kiki_tree_git_untracked }; try %{ remove-highlighter buffer/kiki_tree_git_flag_untracked }; try %{ remove-highlighter buffer/kiki_tree_git_renamed }; try %{ remove-highlighter buffer/kiki_tree_git_flag_renamed };"

        if [ -z "$roots_quoted" ]; then
            # All trees have overlay toggled off
            printf '%s %%{ set-option buffer kiki_tree_overlay_roots; set-option buffer kiki_tree_git_overlay false; %s try %%{ remove-highlighter window/kiki_tree_git_gutter }; try %%{ remove-highlighter window/kiki_tree_git_lines }; set-option window kiki_tree_git_flags %%val{timestamp}; set-option window kiki_tree_git_ranges %%val{timestamp}; echo -markup "{yellow}kiki-tree: git overlay off" }\n' "$eval_cmd" "$cleanup"
            exit 0
        fi

        cmds="${cleanup}set-option buffer kiki_tree_git_overlay true; set-option buffer kiki_tree_overlay_roots ${roots_quoted};"

        if [ -n "$flag_specs" ]; then
            cmds="${cmds}try %{ remove-highlighter window/kiki_tree_git_gutter }; add-highlighter window/kiki_tree_git_gutter flag-lines default kiki_tree_git_flags; set-option window kiki_tree_git_flags %val{timestamp} ${flag_specs};"
        else
            cmds="${cmds}try %{ remove-highlighter window/kiki_tree_git_gutter }; set-option window kiki_tree_git_flags %val{timestamp};"
        fi

        if [ -n "$range_specs" ]; then
            cmds="${cmds}try %{ remove-highlighter window/kiki_tree_git_lines }; add-highlighter window/kiki_tree_git_lines ranges kiki_tree_git_ranges; set-option window kiki_tree_git_ranges %val{timestamp} ${range_specs};"
        else
            cmds="${cmds}try %{ remove-highlighter window/kiki_tree_git_lines }; set-option window kiki_tree_git_ranges %val{timestamp};"
        fi

        if [ "$toggle_action" = "on" ]; then
            msg='echo -markup "{green}kiki-tree: git overlay on for current tree (v to toggle off)"'
        elif [ "$toggle_action" = "off" ]; then
            msg='echo -markup "{yellow}kiki-tree: git overlay off for current tree"'
        else
            msg=''
        fi

        printf '%s %%{ %s %s }\n' "$eval_cmd" "$cmds" "$msg"
    }}

# Refresh gutter when tree structure changes (expand/collapse) while overlay is on
define-command -override -hidden kiki-tree-git-overlay-refresh %{ evaluate-commands %sh{
    if [ "$kak_opt_kiki_tree_git_overlay" = "true" ]; then
        tmp_buf=$(mktemp "${TMPDIR:-/tmp}"/kak-kiki-buf.XXXXXXXX)
        printf 'write -sync -force "%s"\n' "$tmp_buf"
        printf 'kiki-tree-git-overlay-do "%s" "%s" refresh %%opt{kiki_tree_overlay_roots}\n' "$tmp_buf" "$kak_cursor_line"
    fi
}}

hook -group kiki-tree-gutter-refresh global WinDisplay \*kiki-file-tree\* %{
    evaluate-commands %sh{
        if [ "$kak_opt_kiki_tree_git_overlay" = "true" ]; then
            printf 'kiki-tree-git-overlay-refresh\n'
        fi
    }
}

# Close tree buffers
define-command -override -docstring "kiki-close-tree-buffers: close all file tree buffers" \
    kiki-close-tree-buffers %{
        kiki-close-buffers-matching tree
    }
