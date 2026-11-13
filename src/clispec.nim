## clispec — one declarative description of a command line.
##
## ``clispec/model`` is the typed model of a command tree; ``clispec/dsl``
## parses the ``cli:`` description language into it at compile time.
## ``clispec/program`` generates a program's typed configuration object, its
## argv parser (``clispec/parser``) and its help (``clispec/help``) from a
## description, through the run-time tables of ``clispec/grammar``. See the
## README for the language, the generated API and how a consumer attaches
## its own declarations through the model's extension slots.
import clispec/[model, dsl, errors, values, grammar, help, parser, program,
  origins, sources]
export model, dsl, errors, values, grammar, help, parser, program, origins,
  sources
