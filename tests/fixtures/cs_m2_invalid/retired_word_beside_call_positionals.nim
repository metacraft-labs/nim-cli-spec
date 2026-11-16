## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired word 'checkout' would be read as positional 'target' of its call:

import clispec

cliProgram(Tool, "tool"):
  subcmd "switch":
    pos name is string
  call:
    pos target is string, required = false
  retired "checkout", replacement = "tool switch"  # clispec-invalid
