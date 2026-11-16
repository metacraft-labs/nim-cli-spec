## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'switch': retired word 'start' needs a command with subcommands

import clispec

cliProgram(Tool, "tool"):
  subcmd "switch":
    pos name is string
    retired "start", replacement = "tool switch -b"  # clispec-invalid
  subcmd "status":
    discard
