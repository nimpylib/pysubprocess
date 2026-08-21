import std/[osproc, streams, strtabs]

import ../[types, utils]

proc runBackend*(completed: var CompletedProcess; command: string;
    commandArgs: openArray[string]; input: string; shell: bool; cwd: string;
    env: StringTableRef; stdoutMode, stderrMode: Stdio) =
  var options = {poUsePath}
  if shell:
    options.incl poEvalCommand
  if stderrMode == STDOUT:
    options.incl poStdErrToStdOut

  let useParentStreams = input.len == 0 and stdoutMode == INHERIT and
    stderrMode == INHERIT
  if useParentStreams:
    options.incl poParentStreams

  var process = startProcess(command, workingDir = cwd, args = commandArgs,
    env = env, options = options)
  try:
    if useParentStreams:
      completed.returncode = process.waitForExit()
    else:
      let childInput = process.inputStream()
      if input.len != 0:
        childInput.write input
      childInput.close()

      let childStdout = process.outputStream().readAll()
      let childStderr = if stderrMode == STDOUT: ""
                        else: process.errorStream().readAll()
      completed.returncode = process.waitForExit()

      case stdoutMode
      of PIPE: completed.stdout = childStdout
      of DEVNULL: discard
      of INHERIT:
        if childStdout.len != 0: writeParentStdout childStdout
      of STDOUT: discard # validated by the public API
      case stderrMode
      of PIPE: completed.stderr = childStderr
      of STDOUT: discard # already merged and routed as stdout
      of DEVNULL: discard
      of INHERIT:
        if childStderr.len != 0: writeParentStderr childStderr
  finally:
    process.close()
