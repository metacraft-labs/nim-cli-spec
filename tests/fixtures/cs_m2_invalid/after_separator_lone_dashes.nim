## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'command': afterSeparator takes the words after --, but under parsing loneDashesAreFlags -- is an unknown flag, so nothing could fill it

import clispec

cliProgram(Tool, "tool"):
  parsing loneDashesAreFlags  # clispec-invalid
  boolFlag verbose is bool
  pos command is seq[string], required = false, afterSeparator = true
