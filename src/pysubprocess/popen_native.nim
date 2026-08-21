import std/[math, monotimes, options, os, osproc, streams, strtabs, times]

when defined(posix):
  import std/posix

import ./[types, utils]
import ./backend/native_common
import ./popen/common

type PopenProcess* = ref object of PopenBase
  ## A running native child process returned by `Popen`.
  process: Process
  parentStreams: bool

proc startPopen(spec: CommandSpec; shell: bool;
    cwd: string; env: StringTableRef; executable: string; stdin, stdout,
    stderr: Stdio): PopenProcess =
  new result
  result.initPopenBase(spec, shell, cwd, env, executable, stdin, stdout, stderr)
  result.parentStreams = stdin == INHERIT and stdout == INHERIT and
    stderr == INHERIT

  let options = processOptions(shell, result.parentStreams, stderr)
  result.process = startProcess(result.effectiveProgram, workingDir = cwd,
    args = spec.args,
    env = env, options = options)
  result.pid = result.process.processID
  if not result.parentStreams:
    if stdin == PIPE:
      result.stdin = result.process.inputStream()
    else:
      result.process.inputStream().close()
      result.stdinClosed = true
    if stdout == PIPE: result.stdout = result.process.outputStream()
    if stderr == PIPE: result.stderr = result.process.errorStream()

definePopenConstructors(PopenProcess, startPopen)

proc poll*(child: PopenProcess): Option[int] =
  ## Check whether the child has terminated without blocking.
  if child.returncode.isSome:
    return child.returncode
  let code = child.process.peekExitCode()
  if code != -1:
    child.returncode = some(code)
  child.returncode

proc wait*(child: PopenProcess; timeout = -1.0): int =
  ## Wait for the child and return its exit status.
  if child.returncode.isSome:
    return child.returncode.get
  if timeout < 0:
    result = child.process.waitForExit()
    child.returncode = some(result)
    return

  let
    timeoutMs = max(0, int(ceil(timeout * 1000.0)))
    started = getMonoTime()
  while true:
    let status = child.poll()
    if status.isSome:
      return status.get
    if (getMonoTime() - started).inMilliseconds >= timeoutMs:
      raise newTimeoutExpired(child.args, timeout)
    sleep min(5, max(1, timeoutMs))

proc communicate*(child: PopenProcess; input = "";
    timeout = -1.0): tuple[stdout: string, stderr: string] =
  ## Send input, collect both output streams, and wait for termination.
  if child.streamsConsumed:
    discard child.wait(timeout)
    return
  child.validateCommunicateInput(input)
  if child.stdinMode == PIPE and not child.stdinClosed:
    if input.len != 0: child.stdin.write input
    child.stdin.close()
    child.stdinClosed = true

  # Waiting first makes timeout effective for finite-output commands. As with
  # Python, callers should use communicate rather than manual sequential reads.
  if timeout >= 0:
    try:
      discard child.wait(timeout)
    except TimeoutExpired as error:
      if child.stdoutMode == PIPE: error.output = result.stdout
      if child.stderrMode == PIPE: error.stderr = result.stderr
      raise

  if not child.parentStreams:
    let rawStdout = child.process.outputStream().readAll()
    let rawStderr = if child.stderrMode == STDOUT: ""
                    else: child.process.errorStream().readAll()
    result = routeOutput(child.stdoutMode, child.stderrMode, rawStdout,
      rawStderr)
  if timeout < 0:
    discard child.wait()
  child.streamsConsumed = true

proc sendSignal*(child: PopenProcess; signal: int) =
  ## Send an operating-system signal to a running child.
  if child.poll().isSome: return
  when defined(posix):
    if posix.kill(Pid(child.pid), cint(signal)) != 0:
      raiseOSError(osLastError())
  else:
    child.process.terminate()

proc terminate*(child: PopenProcess) =
  ## Request graceful termination of the child.
  if child.poll().isNone: child.process.terminate()

proc kill*(child: PopenProcess) =
  ## Forcefully stop the child.
  if child.poll().isNone: child.process.kill()
