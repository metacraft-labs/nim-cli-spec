## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': retired '--threads' is already declared by the root command

import clispec

cliProgram(Tool, "tool"):
  flag jobs is int, default = 1
  retired "--threads", replacement = "--jobs"
  subcmd "build":
    retired "--threads", replacement = "--jobs"  # clispec-invalid
    pos target is string
