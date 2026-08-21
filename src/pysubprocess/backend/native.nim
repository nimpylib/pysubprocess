import std/[math, monotimes, os, osproc, streams, strtabs, times]

import ../[types, utils]
import ./native_common

proc waitWithTimeout(process: Process; timeout: float): tuple[code: int,
    timedOut: bool] =
  let
    timeoutMs = max(0, int(ceil(timeout * 1000.0)))
    started = getMonoTime()
  while process.running():
    if (getMonoTime() - started).inMilliseconds >= timeoutMs:
      process.kill()
      return (process.waitForExit(), true)
    sleep min(5, max(1, timeoutMs))
  (process.waitForExit(), false)

proc runBackend*(completed: var CompletedProcess; command: string;
    commandArgs: openArray[string]; input: string; shell: bool; cwd: string;
    env: StringTableRef; stdinMode, stdoutMode, stderrMode: Stdio;
    timeout: float) =
  let useParentStreams = input.len == 0 and stdinMode == INHERIT and
    stdoutMode == INHERIT and
    stderrMode == INHERIT
  let options = processOptions(shell, useParentStreams, stderrMode)

  var process = startProcess(command, workingDir = cwd, args = commandArgs,
    env = env, options = options)
  try:
    var timedOut = false
    if useParentStreams:
      if timeout < 0:
        completed.returncode = process.waitForExit()
      else:
        (completed.returncode, timedOut) = process.waitWithTimeout(timeout)
    else:
      let childInput = process.inputStream()
      if input.len != 0:
        childInput.write input
      childInput.close()

      if timeout >= 0:
        (completed.returncode, timedOut) = process.waitWithTimeout(timeout)

      let childStdout = process.outputStream().readAll()
      let childStderr = if stderrMode == STDOUT: ""
                        else: process.errorStream().readAll()
      if timeout < 0:
        completed.returncode = process.waitForExit()

      (completed.stdout, completed.stderr) = routeOutput(stdoutMode,
        stderrMode, childStdout, childStderr)
    if timedOut:
      raise newTimeoutExpired(commandLine(command, commandArgs), timeout,
        completed.stdout, completed.stderr)
  finally:
    process.close()
