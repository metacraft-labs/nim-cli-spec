## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'extra': command 'exec' gives the words after -- to 'command' (afterSeparator), which must be its last positional

import clispec

cliProgram(Tool, "tool"):
  subcmd "exec":
    pos command is seq[string], required = false, afterSeparator = true
    pos extra is string, required = false  # clispec-invalid
