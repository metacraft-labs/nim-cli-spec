## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired '--force' is a spelling of flag 'force' in command 'push'

import clispec

cliProgram(Tool, "tool"):
  retired "--force", replacement = "--yes"  # clispec-invalid
  subcmd "push":
    boolFlag force is bool
  subcmd "pull":
    discard
