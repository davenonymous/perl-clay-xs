# NAME

Clay::UI::\_error - how Clay::UI reports misuse (internal)

# DESCRIPTION

Internal to Clay::UI. `croak_ui($message)` dies with `$message` plus
` at FILE line N.`, where FILE and N name the first caller outside the
`Clay::UI` namespace. Every error Clay::UI raises for bad input goes
through it, so the message points at the program's line, never into the
library.
