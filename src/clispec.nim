## clispec — one declarative description of a command line.
##
## ``clispec/model`` is the typed model of a command tree; ``clispec/dsl``
## parses the ``cli:`` description language into it at compile time.
## ``clispec/program`` generates a program's typed configuration object, its
## argv parser (``clispec/parser``), its help (``clispec/help``) and its
## shell completion (``clispec/completion``, ``clispec/completion_scripts``)
## from a
## description, through the run-time tables of ``clispec/grammar``. See the
## README for the language, the generated API and how a consumer attaches
## its own declarations through the model's extension slots.
##
## Configuration files and the environment are not read here: confutils,
## instantiated over a clispec description, adds them as sources and
## delegates the command line to this library.
import clispec/[model, dsl, errors, values, grammar, help, parser, program,
  candidates, completers, completion, completion_scripts]
export model, dsl, errors, values, grammar, help, parser, program, candidates,
  completers, completion, completion_scripts
