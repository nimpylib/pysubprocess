## A small, synchronous subset of Python's ``subprocess`` API.
##
## Commands are passed as an argument vector by default. Set ``shell=true``
## only when shell syntax is deliberately required.

import std/strtabs

import ./pysubprocess/[types, utils]
export types

when defined(js):
  import ./pysubprocess/backend/js
else:
  import ./pysubprocess/backend/native

proc runImpl(command: string; commandArgs: openArray[string]; input: string;
    captureOutput, check, shell: bool; cwd: string; env: StringTableRef;
    stdoutMode, stderrMode: Stdio): CompletedProcess =
  if command.len == 0:
    raise newException(ValueError, "args must not be empty")
  if captureOutput and (stdoutMode != INHERIT or stderrMode != INHERIT):
    raise newException(ValueError,
      "stdout and stderr arguments may not be used with capture_output")

  let
    effectiveStdout = if captureOutput: PIPE else: stdoutMode
    effectiveStderr = if captureOutput: PIPE else: stderrMode
  if effectiveStdout == STDOUT:
    raise newException(ValueError, "STDOUT is only valid for stderr")

  result.args = commandLine(command, commandArgs)
  runBackend(result, command, commandArgs, input, shell, cwd, env,
    effectiveStdout, effectiveStderr)

  if check and result.returncode != 0:
    raise newCalledProcessError(result)

proc run*(args: openArray[string]; input = ""; captureOutput = false;
    check = false; shell = false; cwd = ""; env: StringTableRef = nil;
    stdout = INHERIT; stderr = INHERIT): CompletedProcess =
  ## Run a command and wait for it to finish.
  ##
  ## ``args`` is an executable followed by its arguments. Captured output is
  ## UTF-8 text on the JavaScript backends and a Nim string natively.
  if args.len == 0:
    raise newException(ValueError, "args must not be empty")
  if args.len == 1:
    runImpl(args[0], [], input, captureOutput, check, shell, cwd, env, stdout,
      stderr)
  else:
    runImpl(args[0], args.toOpenArray(1, args.high), input, captureOutput,
      check, shell, cwd, env, stdout, stderr)

proc run*(command: string; input = ""; captureOutput = false; check = false;
    shell = false; cwd = ""; env: StringTableRef = nil; stdout = INHERIT;
    stderr = INHERIT): CompletedProcess =
  ## String form of `run`. Without ``shell=true`` the whole string is treated
  ## as the executable name, matching Python's subprocess behavior.
  runImpl(command, [], input, captureOutput, check, shell, cwd, env, stdout,
    stderr)

proc call*(args: openArray[string]; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## Run a command and return its exit status.
  run(args, shell = shell, cwd = cwd, env = env).returncode

proc call*(command: string; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## String form of `call`.
  run(command, shell = shell, cwd = cwd, env = env).returncode

proc checkCall*(args: openArray[string]; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## Run a command, raising `CalledProcessError` on failure.
  run(args, check = true, shell = shell, cwd = cwd, env = env).returncode

proc checkCall*(command: string; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## String form of `checkCall`.
  run(command, check = true, shell = shell, cwd = cwd, env = env).returncode

proc checkOutput*(args: openArray[string]; input = ""; shell = false;
    cwd = ""; env: StringTableRef = nil; stderr = INHERIT): string =
  ## Run a command and return stdout, raising on failure.
  run(args, input = input, check = true, shell = shell, cwd = cwd, env = env,
    stdout = PIPE, stderr = stderr).stdout

proc checkOutput*(command: string; input = ""; shell = false; cwd = "";
    env: StringTableRef = nil; stderr = INHERIT): string =
  ## String form of `checkOutput`.
  run(command, input = input, check = true, shell = shell, cwd = cwd,
    env = env, stdout = PIPE, stderr = stderr).stdout

proc checkReturncode*(completed: CompletedProcess) =
  ## Raise `CalledProcessError` if this process did not exit successfully.
  if completed.returncode != 0:
    raise newCalledProcessError(completed)

proc getstatusoutput*(command: string): tuple[status: int, output: string] =
  ## Run a shell command with stderr redirected to stdout.
  let completed = run(command, shell = true, stdout = PIPE, stderr = STDOUT)
  result = (completed.returncode, completed.stdout)
  while result.output.len != 0 and result.output[^1] in {'\r', '\n'}:
    result.output.setLen(result.output.len - 1)

proc getoutput*(command: string): string =
  ## Return combined output from a shell command.
  getstatusoutput(command).output
