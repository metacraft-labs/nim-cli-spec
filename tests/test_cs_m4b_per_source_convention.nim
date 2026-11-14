## test_cs_m4b_per_source_convention: each source spells a parameter's name
## in its own naming convention, set once per source in the description.
##
## ``Svc`` spells every configuration file in snake_case, the file source
## named ``project`` in kebab-case and the command line's long flags in
## kebab-case. The model carries every source's spelling; the command line
## accepts the kebab-case flags, with short spellings and negation; help
## shows the command line's spelling and the machine-readable help every
## source's.
##
## Negative control: the declared spelling on the command line is an
## unknown flag.
##
## Reading configuration files and the environment under those spellings is
## confutils' job (it is instantiated over a clispec description and reads
## the conventions from the model); its tests of the same name cover the
## file sources.

import std/[json, strutils, unittest]

import clispec

cliProgram(Svc, "svc"):
  configSchema "svc.config.v1"
  convention file = snakeCase
  convention "project" = kebabCase
  convention cli = kebabCase
  flag writeReport is string, env = ["SVC_REPORT_PATH"]
  boolFlag dryRun is bool, negatable = true
  flag maxJobs is int, default = 1, short = 'j'
  call:
    help "Serve"
  subcmd "remote":
    flag pushUrl is string

suite "test_cs_m4b_per_source_convention":

  test "the model spells each source in its convention":
    const m = Svc.cliModel
    check m.keyStyle == cnSnakeCase
    check m.flagConvention == cnKebabCase
    check m.fileSources == @[CliSourceConvention(source: "project",
      convention: cnKebabCase)]
    let p = m.root.params[0]
    check p.name == "writeReport"
    check p.longName == "write-report"
    check p.configKey == "write_report"
    check p.sourceKeys == @[CliSourceSpelling(source: "project",
      spelling: "write-report")]
    var push: PlainCliParam
    for c in m.commands:
      if c.name == "remote":
        push = c.params[^1]
    check push.name == "pushUrl"
    check push.configKey == "remote.push_url"
    check push.sourceKeys[0].spelling == "remote.push-url"

  test "short spellings and negation follow the command line's convention":
    let conf = Svc.load(@["--dry-run", "-j", "5"])
    check conf.dryRun
    check conf.maxJobs == 5
    check not Svc.load(@["--dry-run", "--no-dry-run"]).dryRun

  test "negative control: the declared spelling is not a flag":
    expect CliUsageError:
      discard Svc.load(@["--writeReport", "x"])
    try:
      discard Svc.load(@["--write_report", "x"])
      check false
    except CliUsageError as e:
      check e.kind == cekUnknownFlag

  test "help shows the command line's spelling":
    let text = Svc.helpText()
    check "--write-report <string>" in text
    check "--[no-]dry-run" in text
    check "-j, --max-jobs <int>" in text
    check "writeReport" notin text
    check "--push-url <string>" in Svc.helpText(["remote"])

  test "the machine-readable help shows every source's spelling":
    let doc = parseJson(Svc.helpJson())
    check doc["conventions"] == %*{"cli": "kebabCase", "file": "snakeCase",
      "project": "kebabCase"}
    var found = false
    for p in doc["command"]["parameters"]:
      if p["name"].getStr == "writeReport":
        found = true
        check p["spellings"] == %*["--write-report"]
        check p["configKeys"] == %*{"file": "write_report",
          "project": "write-report"}
      if p["name"].getStr == "dryRun":
        check p["negation"].getStr == "--no-dry-run"
    check found
