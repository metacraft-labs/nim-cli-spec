## test_cs_m4b_convention_conversion: ``cliConvert`` spells a name in each
## naming convention by one word-splitting rule (``clispec/model``, "Naming
## conventions"), and ``declared`` is always the name as written.
##
## A table of names covers camelCase and PascalCase input, acronyms (a run
## of capitals before a word, at the end of a name, alone), digits (inside a
## word, after an acronym, after a separator), names already in kebab-case
## and snake_case, mixed separators, non-ASCII letters and names with no
## word character. Every row states the words and the spelling in each
## convention; converting any of them to ``declared`` gives the input back
## unchanged. A description with no ``convention`` statement keeps every
## long flag and key exactly as declared.
##
## Pure functions over strings and a compile-time model; nothing is mocked.

import std/unittest

import clispec

type
  Row = object
    name: string
    words: seq[string]
    camel, snake, kebab: string

const rows = [
  Row(name: "writeReport", words: @["write", "Report"],
    camel: "writeReport", snake: "write_report", kebab: "write-report"),
  Row(name: "WriteReport", words: @["Write", "Report"],
    camel: "writeReport", snake: "write_report", kebab: "write-report"),
  Row(name: "jobs", words: @["jobs"],
    camel: "jobs", snake: "jobs", kebab: "jobs"),
  Row(name: "X", words: @["X"], camel: "x", snake: "x", kebab: "x"),
  # Acronyms: the last capital before a lower-case letter starts the next
  # word; a run of capitals with nothing lower-case after it is one word.
  Row(name: "HTTPPort", words: @["HTTP", "Port"],
    camel: "httpPort", snake: "http_port", kebab: "http-port"),
  Row(name: "parseHTTPRequest", words: @["parse", "HTTP", "Request"],
    camel: "parseHttpRequest", snake: "parse_http_request",
    kebab: "parse-http-request"),
  Row(name: "userID", words: @["user", "ID"],
    camel: "userId", snake: "user_id", kebab: "user-id"),
  Row(name: "ABC", words: @["ABC"], camel: "abc", snake: "abc", kebab: "abc"),
  Row(name: "ABCdef", words: @["AB", "Cdef"],
    camel: "abCdef", snake: "ab_cdef", kebab: "ab-cdef"),
  # Digits stay with the word before them.
  Row(name: "ipv6Address", words: @["ipv6", "Address"],
    camel: "ipv6Address", snake: "ipv6_address", kebab: "ipv6-address"),
  Row(name: "HTTP2Server", words: @["HTTP2", "Server"],
    camel: "http2Server", snake: "http2_server", kebab: "http2-server"),
  Row(name: "sha256Sum", words: @["sha256", "Sum"],
    camel: "sha256Sum", snake: "sha256_sum", kebab: "sha256-sum"),
  Row(name: "utf8", words: @["utf8"], camel: "utf8", snake: "utf8",
    kebab: "utf8"),
  Row(name: "v2beta", words: @["v2beta"], camel: "v2beta", snake: "v2beta",
    kebab: "v2beta"),
  Row(name: "max_depth_2", words: @["max", "depth", "2"],
    camel: "maxDepth2", snake: "max_depth_2", kebab: "max-depth-2"),
  # Already in one of the conventions.
  Row(name: "write-report", words: @["write", "report"],
    camel: "writeReport", snake: "write_report", kebab: "write-report"),
  Row(name: "debug_dump", words: @["debug", "dump"],
    camel: "debugDump", snake: "debug_dump", kebab: "debug-dump"),
  Row(name: "already-kebab-name", words: @["already", "kebab", "name"],
    camel: "alreadyKebabName", snake: "already_kebab_name",
    kebab: "already-kebab-name"),
  Row(name: "already_snake_name", words: @["already", "snake", "name"],
    camel: "alreadySnakeName", snake: "already_snake_name",
    kebab: "already-snake-name"),
  Row(name: "HTTP_PORT", words: @["HTTP", "PORT"],
    camel: "httpPort", snake: "http_port", kebab: "http-port"),
  # Mixed separators; every non-word character separates and is dropped.
  Row(name: "Mixed_Case-Name", words: @["Mixed", "Case", "Name"],
    camel: "mixedCaseName", snake: "mixed_case_name",
    kebab: "mixed-case-name"),
  Row(name: "__private__", words: @["private"],
    camel: "private", snake: "private", kebab: "private"),
  Row(name: "a.b", words: @["a", "b"], camel: "aB", snake: "a_b",
    kebab: "a-b"),
  # Non-ASCII bytes are word characters with no case.
  Row(name: "größeLimit", words: @["größe", "Limit"],
    camel: "größeLimit", snake: "größe_limit", kebab: "größe-limit"),
  # No word character: kept as written.
  Row(name: "---", words: @[], camel: "---", snake: "---", kebab: "---"),
]

suite "test_cs_m4b_convention_conversion":

  test "the table is not empty":
    check rows.len >= 20

  for row in rows:
    test "'" & row.name & "'":
      check cliWords(row.name) == row.words
      check cliConvert(row.name, cnCamelCase) == row.camel
      check cliConvert(row.name, cnSnakeCase) == row.snake
      check cliConvert(row.name, cnKebabCase) == row.kebab
      check cliConvert(row.name, cnDeclared) == row.name

  test "converting any spelling to declared is the identity":
    for row in rows:
      for spelling in [row.name, row.camel, row.snake, row.kebab]:
        check cliConvert(spelling, cnDeclared) == spelling

  test "a spelling converted to its own convention stays as it is":
    # Every spelling in the table whose words survive the round trip (a
    # one-letter word followed by another capital does not: ``xYZ``).
    for row in rows:
      check cliConvert(row.snake, cnSnakeCase) == row.snake
      check cliConvert(row.kebab, cnKebabCase) == row.kebab
      check cliConvert(row.camel, cnCamelCase) == row.camel

  test "the older names keep their meaning":
    check cksDeclared == cnDeclared
    check cksSnakeCase == cnSnakeCase
    check cksKebabCase == cnKebabCase
    for row in rows:
      check cliKeySegment(row.name, cksSnakeCase) == row.snake
    check cliDerivedKey(["debug-dump"], "maxDepth", cksKebabCase) ==
      "debug-dump.max-depth"

  test "a description without conventions keeps every name as declared":
    const model = plainCliModel:
      configSchema "t.config.v1"
      flag writeReport is string
      flag HTTP_PORT is int
      subcmd "debug-dump":
        flag maxDepth is int
    check model.keyStyle == cnDeclared
    check model.flagConvention == cnDeclared
    check model.fileSources.len == 0
    check model.root.params[0].longName == "writeReport"
    check model.root.params[0].configKey == "writeReport"
    check model.root.params[1].longName == "HTTP_PORT"
    check model.root.params[1].configKey == "HTTP_PORT"
    check model.commands[0].params[2].longName == "maxDepth"
    check model.commands[0].params[2].configKey == "debug-dump.maxDepth"
