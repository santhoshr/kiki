# Kiki Syntax & Highlighting

try %{ add-highlighter -override global/kiki_arrow regex ^>[^\n]+ 0:green }
try %{ add-highlighter -override global/kiki_dollar regex "\$ " 0:default+rb }
try %{ add-highlighter -override global/kiki_cmd regex "(?<=\$ )[^\n]+" 0:cyan }

# File Tree Highlighting
try %{ add-highlighter -override global/kiki_tree_plus regex "^\s*\+\s" 0:green+b }
try %{ add-highlighter -override global/kiki_tree_minus regex "^\s*-\s" 0:red+b }
try %{ add-highlighter -override global/kiki_tree_dir regex "(?<=[+-]\s)[^\n]+/" 0:blue+b }
try %{ add-highlighter -override global/kiki_tree_root regex "^/[^\n]+/$" 0:magenta+b }
