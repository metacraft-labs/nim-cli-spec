## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'args': a rest positional cannot follow a repeated one in command 'run'

import clispec

cliProgram(Tool, "tool"):
  subcmd "run":
    pos programs is seq[string], repeated = true
    pos args is seq[string], rest = true, required = false  # clispec-invalid
