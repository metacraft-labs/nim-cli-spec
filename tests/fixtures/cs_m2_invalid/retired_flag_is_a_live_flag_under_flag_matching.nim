## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired '--JOBS' is a spelling of flag 'jobs' in the root command

import clispec

cliProgram(Tool, "tool"):
  flagMatching ignoreCase
  flag jobs is int, default = 1
  retired "--JOBS", replacement = "--jobs"  # clispec-invalid
