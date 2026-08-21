import std/strtabs

import ./[types, utils]

when defined(js):
  import ./backend/js
else:
  import ./backend/native

proc executeSync*(spec: CommandSpec; input: string; shell: bool; cwd: string;
    env: StringTableRef; stdinMode, stdoutMode, stderrMode: Stdio;
    timeout: float): CompletedProcess =
  ## Execute one normalized command through the selected synchronous backend.
  result.args = spec.argv
  runBackend(result, spec.command, spec.args, input, shell, cwd, env,
    stdinMode, stdoutMode, stderrMode, timeout)
