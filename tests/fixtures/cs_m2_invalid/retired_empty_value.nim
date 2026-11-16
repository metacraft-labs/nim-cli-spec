## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': retired spelling '--mode=' is malformed: the value after '=' is empty

import clispec

cliProgram(Tool, "tool"):
  subcmd "build":
    flag style is string, default = ""
    retired "--mode=", replacement = "--style"  # clispec-invalid
