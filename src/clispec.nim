## clispec — one declarative description of a command line.
##
## ``clispec/model`` is the typed model of a command tree; ``clispec/dsl``
## parses the ``cli:`` description language into it at compile time. See
## the README for the language and for how a consumer attaches its own
## declarations through the model's extension slots.
import clispec/[model, dsl]
export model, dsl
