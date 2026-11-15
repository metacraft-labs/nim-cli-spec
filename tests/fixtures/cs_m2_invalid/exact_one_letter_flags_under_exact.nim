## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parsing exactOneLetterFlags keeps one-letter flag spellings exact under flagMatching ignoreCase or ignoreStyle, and changes nothing under flagMatching exact

import clispec

const model {.used.} = plainCliModel:
  parsing loneDashesAreFlags, exactOneLetterFlags  # clispec-invalid
  flag trace is string, short = 't'
