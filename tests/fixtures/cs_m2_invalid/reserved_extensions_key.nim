## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'plugin': configuration key 'extensions.plugin' is reserved

import clispec

cliProgram(Tool, "tool"):
  configSchema "tool.config.v1"
  subcmd "extensions":
    flag plugin is string  # clispec-invalid
    flag other is string, key = "plugins.other"

# A description that loads no configuration file may use the key.
cliProgram(External, "external"):
  flag extensions is seq[string]
