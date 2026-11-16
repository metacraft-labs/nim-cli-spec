## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the call: of the root command: retired '--quiet' is a spelling of flag 'quiet' in the root command

import clispec

cliProgram(Tool, "tool"):
  subcmd "list":
    discard
  call:
    retired "--quiet", replacement = "--silent"  # clispec-invalid
    boolFlag dryRun is bool
  # Declared after the call: opened, so the call: does not inherit it, but
  # the root command, where the call:'s flags are read too, has it.
  boolFlag quiet is bool
