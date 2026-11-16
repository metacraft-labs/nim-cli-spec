## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': retired is written retired

import clispec

cliProgram(Tool, "tool"):
  subcmd "build":
    flag jobs is int, default = 1
    retired "--threads", replacement = "--jobs", help = "x"  # clispec-invalid
