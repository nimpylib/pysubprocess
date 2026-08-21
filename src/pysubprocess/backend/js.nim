import std/[jsffi, strtabs]

from pkg/jscompat/utils/denoAttrs import importByNodeOrDeno

import ../[types, utils]

{.emit: """/*INCLUDESECTION*/
function pysubprocessEnvironment(envPairs) {
  if (envPairs === null) return undefined;
  const env = {};
  for (let i = 0; i < envPairs.length; i += 2)
    env[envPairs[i]] = envPairs[i + 1];
  return env;
}

function pysubprocessNodeSpawnSync(
    command, args, input, cwd, shell, envPairs, timeoutMs, stdinMode) {
  const options = {
    encoding: 'utf8',
    input: input,
    maxBuffer: 64 * 1024 * 1024,
    shell: shell
  };
  options.stdio = [stdinMode === 0 ? 'inherit' :
                   stdinMode === 3 ? 'ignore' : 'pipe', 'pipe', 'pipe'];
  if (cwd.length !== 0) options.cwd = cwd;
  if (timeoutMs >= 0) options.timeout = timeoutMs;
  const env = pysubprocessEnvironment(envPairs);
  if (env !== undefined) options.env = env;
  const child = require('node:child_process').spawnSync(command, args, options);
  return {
    status: child.status === null ? -1 : child.status,
    stdout: child.stdout === null ? '' : child.stdout,
    stderr: child.stderr === null ? '' : child.stderr,
    error: child.error === undefined ? '' : child.error.message,
    timedOut: child.error !== undefined && child.error.code === 'ETIMEDOUT'
  };
}

const pysubprocessTextDecoder = new TextDecoder();
function pysubprocessDenoResult(child) {
  return {
    status: child.code,
    stdout: pysubprocessTextDecoder.decode(child.stdout),
    stderr: pysubprocessTextDecoder.decode(child.stderr),
    error: ''
  };
}

function pysubprocessDenoCommand(command, args, cwd, shell, envPairs, stdinMode) {
  let executable = command;
  let commandArgs = args;
  if (shell) {
    if (Deno.build.os === 'windows') {
      executable = 'cmd.exe';
      commandArgs = ['/d', '/s', '/c', command];
    } else {
      executable = '/bin/sh';
      commandArgs = ['-c', command];
    }
  }
  const options = {
    args: commandArgs,
    stdin: stdinMode === 0 ? 'inherit' :
           stdinMode === 3 ? 'null' : 'piped',
    stdout: 'piped',
    stderr: 'piped'
  };
  if (cwd.length !== 0) options.cwd = cwd;
  const env = pysubprocessEnvironment(envPairs);
  if (env !== undefined) {
    options.env = env;
    options.clearEnv = true;
  }
  return { executable, options };
}

async function pysubprocessDenoInputBridgeMain() {
  const spec = JSON.parse(Deno.readTextFileSync(Deno.args[0]));
  const child = new Deno.Command(spec.executable, spec.options).spawn();
  let timedOut = false;
  let timer;
  if (spec.timeoutMs >= 0) {
    timer = setTimeout(() => {
      timedOut = true;
      try { child.kill('SIGKILL'); } catch (_) {}
    }, spec.timeoutMs);
  }
  if (spec.options.stdin === 'piped') {
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(spec.input));
    await writer.close();
  }
  const output = await child.output();
  if (timer !== undefined) clearTimeout(timer);
  Deno.writeTextFileSync(spec.resultPath, JSON.stringify({
    status: output.code,
    stdout: new TextDecoder().decode(output.stdout),
    stderr: new TextDecoder().decode(output.stderr),
    error: '',
    timedOut
  }));
}
const pysubprocessDenoInputBridge =
  '(' + pysubprocessDenoInputBridgeMain.toString() + ')()';

function pysubprocessDenoSpawnSync(
    command, args, input, cwd, shell, envPairs, timeoutMs, stdinMode) {
  try {
    const spec = pysubprocessDenoCommand(
      command, args, cwd, shell, envPairs, stdinMode);
    if (stdinMode !== 1 && input.length === 0 && timeoutMs < 0) {
      const result = pysubprocessDenoResult(
        new Deno.Command(spec.executable, spec.options).outputSync());
      result.timedOut = false;
      return result;
    }

    // outputSync rejects piped stdin, so a synchronous Deno.Command runs a
    // small bridge that uses Deno.Command.spawn() to feed the input.
    const specPath = Deno.makeTempFileSync({
      prefix: 'pysubprocess-', suffix: '.json'
    });
    const resultPath = Deno.makeTempFileSync({
      prefix: 'pysubprocess-result-', suffix: '.json'
    });
    try {
      Deno.writeTextFileSync(specPath, JSON.stringify({
        executable: spec.executable,
        options: spec.options,
        input: input,
        timeoutMs: timeoutMs,
        resultPath: resultPath
      }));
      const bridge = new Deno.Command(Deno.execPath(), {
        args: ['eval', pysubprocessDenoInputBridge, specPath],
        stdin: 'null',
        stdout: 'piped',
        stderr: 'piped'
      }).outputSync();
      if (!bridge.success)
        throw new Error(new TextDecoder().decode(bridge.stderr));
      return JSON.parse(Deno.readTextFileSync(resultPath));
    } finally {
      Deno.removeSync(specPath);
      Deno.removeSync(resultPath);
    }
  } catch (error) {
    return {
      status: -1,
      stdout: '',
      stderr: '',
      error: String(error.message || error),
      timedOut: false
    };
  }
}
""".}

type JsRunResult = JsObject

proc spawnSync(command: cstring; args: seq[cstring]; input, cwd: cstring;
    shell: bool; envPairs: JsObject; timeoutMs, stdinMode: int): JsRunResult
    {.importByNodeOrDeno(
      "pysubprocessNodeSpawnSync", "pysubprocessDenoSpawnSync").}

proc status(res: JsRunResult): int {.importjs: "#.status".}
proc stdout(res: JsRunResult): cstring {.importjs: "#.stdout".}
proc stderr(res: JsRunResult): cstring {.importjs: "#.stderr".}
proc error(res: JsRunResult): cstring {.importjs: "#.error".}
proc timedOut(res: JsRunResult): bool {.importjs: "#.timedOut".}
proc jsNull(ignored: int): JsObject {.importjs: "(#, null)".}
proc asJsObject(values: seq[cstring]): JsObject {.importjs: "#".}

proc environmentPairs(env: StringTableRef): seq[cstring] =
  if env != nil:
    for key, value in env:
      result.add cstring(key)
      result.add cstring(value)

proc runBackend*(completed: var CompletedProcess; command: string;
    commandArgs: openArray[string]; input: string; shell: bool; cwd: string;
    env: StringTableRef; stdinMode, stdoutMode, stderrMode: Stdio;
    timeout: float) =
  var jsArgs = newSeqOfCap[cstring](commandArgs.len)
  for arg in commandArgs:
    jsArgs.add cstring(arg)
  let pairs = environmentPairs(env)
  let jsEnv = if env == nil: jsNull(0) else: asJsObject(pairs)
  let timeoutMs = if timeout < 0: -1 else: max(0, int(timeout * 1000.0))
  let child = spawnSync(cstring(command), jsArgs, cstring(input), cstring(cwd),
    shell, jsEnv, timeoutMs, ord(stdinMode))
  if child.error.len != 0 and not child.timedOut:
    raise newException(OSError, $child.error)
  completed.returncode = child.status
  let childStdout = $child.stdout
  let childStderr = $child.stderr
  (completed.stdout, completed.stderr) = routeOutput(stdoutMode, stderrMode,
    childStdout, childStderr)
  if child.timedOut:
    raise newTimeoutExpired(commandLine(command, commandArgs), timeout,
      completed.stdout, completed.stderr)
