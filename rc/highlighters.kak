# Kiki Syntax & Highlighting

try %{ add-highlighter -override global/kiki_arrow regex ^>[^\n]+ 0:green }
try %{ add-highlighter -override global/kiki_dollar regex "\$ " 0:default+rb }
try %{ add-highlighter -override global/kiki_cmd regex "(?<=\$ )[^\n]+" 0:cyan }
