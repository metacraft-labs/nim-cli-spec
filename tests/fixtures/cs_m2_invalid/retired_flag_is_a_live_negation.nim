## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired '--no-color' is a spelling of flag 'color' in the root command

import clispec

cliProgram(Tool, "tool"):
  boolFlag color is bool, negatable = true
  retired "--no-color", replacement = "--color=false"  # clispec-invalid
  retired "--no-colour", replacement = "--color=false"
