## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired word 'co' is a word of command 'switch'

import clispec

cliProgram(Tool, "tool"):
  subcmd "switch", aliases = ["co"]:
    pos name is string
  retired "co", replacement = "tool switch"  # clispec-invalid
  retired "checkout", replacement = "tool switch"
