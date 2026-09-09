# Kiki Syntax & Highlighting

define-command -override -hidden kiki-update-highlighters %{
    evaluate-commands %sh{
        prefix="$kak_opt_kiki_prefix"
        [ -z "$prefix" ] && prefix='$ '
        escaped_prefix=$(printf '%s' "$prefix" | sed 's/[][\/.^$*+?(){}|]/\\&/g')

        printf 'try %%{ remove-highlighter global/kiki_prefix }\n'
        printf 'try %%{ remove-highlighter global/kiki_cmd }\n'
        printf 'add-highlighter -override global/kiki_prefix regex "%s" 0:default+rb\n' "$escaped_prefix"
        printf 'add-highlighter -override global/kiki_cmd regex "(?<=%s)[^\n]+" 0:cyan\n' "$escaped_prefix"
    }
}

kiki-update-highlighters

hook -group kiki-highlight global GlobalSetOption kiki_prefix=.* %{
    kiki-update-highlighters
}

try %{ add-highlighter -override global/kiki_arrow regex ^>[^\n]+ 0:green }

# File Tree Highlighting
try %{ add-highlighter -override global/kiki_tree_plus regex "^\s*\+\s" 0:green+b }
try %{ add-highlighter -override global/kiki_tree_minus regex "^\s*-\s" 0:red+b }
try %{ add-highlighter -override global/kiki_tree_dir regex "(?<=[+-]\s)[^\n]+/" 0:blue+b }
try %{ add-highlighter -override global/kiki_tree_root regex "^/[^\n]+/$" 0:magenta+b }
