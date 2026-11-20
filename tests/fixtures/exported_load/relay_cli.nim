## The ``relay`` description, exported for another module to load
## (``tests/test_exported_load_from_another_module.nim``). It declares the
## program and nothing else; ``relay.nim`` is the program that loads it.
## A second exported description, ``beacon``, gives every importer two
## ``load`` overload sets that differ only in the ``typedesc``.

import clispec

cliProgram(Relay, "relay", exported = true):
  help "Forward messages"
  flag port is int, default = 8080, help = "The port to listen on"
  boolFlag quiet is bool, short = 'q', help = "Print only errors"
  subcmd "send", help = "Send one message":
    pos message is string, help = "The message"

cliProgram(Beacon, "beacon", exported = true):
  flag level is int, default = 1, help = "The signal level"
