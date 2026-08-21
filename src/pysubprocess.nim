## Python-like subprocess management for native Nim, Node.js, and Deno.
##
## Commands are passed as an argument vector by default. Set ``shell=true``
## only when shell syntax is deliberately required.

import std/[options, streams, strtabs]
export options, streams

import ./pysubprocess/[types, utils]
import ./pysubprocess/macros
import ./pysubprocess/execution
export types

when defined(windows):
  import ./pysubprocess/windows
  export windows

when defined(js):
  import ./pysubprocess/popen_js
  export popen_js
else:
  import ./pysubprocess/popen_native
  export popen_native

proc runImpl(spec: CommandSpec; input: string;
    captureOutput, check, shell: bool; cwd: string; env: StringTableRef;
    stdinMode, stdoutMode, stderrMode: Stdio; timeout: float): CompletedProcess =
  if captureOutput and (stdoutMode != INHERIT or stderrMode != INHERIT):
    raise newException(ValueError,
      "stdout and stderr arguments may not be used with capture_output")
  if input.len != 0 and stdinMode != INHERIT:
    raise newException(ValueError, "stdin and input arguments may not both be used")
  validateStdio(stdinMode, stdoutMode)

  let
    effectiveStdin = if input.len != 0: PIPE else: stdinMode
    effectiveStdout = if captureOutput: PIPE else: stdoutMode
    effectiveStderr = if captureOutput: PIPE else: stderrMode
  result = executeSync(spec, input, shell, cwd, env, effectiveStdin,
    effectiveStdout, effectiveStderr, timeout)

  if check and result.returncode != 0:
    raise newCalledProcessError(result)

defineCommandOverloads:
  proc run*(args: openArray[string]; input = ""; captureOutput = false;
      check = false; shell = false; cwd = ""; env: StringTableRef = nil;
      stdin = INHERIT; stdout = INHERIT; stderr = INHERIT; timeout = -1.0;
      encoding = ""; errors = ""; text = false;
      universalNewlines = false): CompletedProcess =
    ## Run a command and wait for it to finish.
    runImpl(commandSpec(args), input, captureOutput, check, shell, cwd, env,
      stdin, stdout, stderr, timeout)

template defineStatusHelper(name: untyped; checked: static bool) =
  defineCommandOverloads:
    proc name*(args: openArray[string]; shell = false; cwd = "";
        env: StringTableRef = nil; stdin = INHERIT; stdout = INHERIT;
        stderr = INHERIT; timeout = -1.0): int {.discardable.} =
      run(args, check = checked, shell = shell, cwd = cwd, env = env,
        stdin = stdin, stdout = stdout, stderr = stderr,
        timeout = timeout).returncode

defineStatusHelper(call, false)
defineStatusHelper(checkCall, true)

defineCommandOverloads:
  proc checkOutput*(args: openArray[string]; input = ""; shell = false;
      cwd = "";
      env: StringTableRef = nil; stderr = INHERIT; timeout = -1.0;
      encoding = ""; errors = ""; text = false;
      universalNewlines = false): string =
    run(args, input = input, check = true, shell = shell, cwd = cwd, env = env,
      stdout = PIPE, stderr = stderr, timeout = timeout, encoding = encoding,
      errors = errors, text = text,
      universalNewlines = universalNewlines).stdout

proc checkReturncode*(completed: CompletedProcess) =
  ## Raise `CalledProcessError` if this process did not exit successfully.
  if completed.returncode != 0:
    raise newCalledProcessError(completed)

proc getstatusoutput*(command: string; encoding = "";
    errors = ""): tuple[status: int, output: string] =
  ## Run a shell command with stderr redirected to stdout.
  let completed = run(command, shell = true, stdout = PIPE, stderr = STDOUT,
    encoding = encoding, errors = errors)
  result = (completed.returncode, completed.stdout)
  while result.output.len != 0 and result.output[^1] in {'\r', '\n'}:
    result.output.setLen(result.output.len - 1)

proc getoutput*(command: string; encoding = ""; errors = ""): string =
  ## Return combined output from a shell command.
  getstatusoutput(command, encoding = encoding, errors = errors).output
