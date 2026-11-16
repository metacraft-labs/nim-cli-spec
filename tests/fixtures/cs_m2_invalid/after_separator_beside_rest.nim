## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'command': command 'exec' takes the rest of the command line in an earlier positional, so no positional can follow it

import clispec

cliProgram(Tool, "tool"):
  subcmd "exec":
    pos args is seq[string], required = false, rest = true  # clispec-invalid
    pos command is seq[string], required = false, afterSeparator = true
