## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'command': afterSeparator takes the words after -- on the command line, but `sources` exclude cli

import clispec

const model {.used.} = plainCliModel:
  pos selector is string, required = false
  pos command is seq[string], afterSeparator = true, sources = {env}, env = "CMD"  # clispec-invalid
