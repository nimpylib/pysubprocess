# pysubprocess

[![Test](https://github.com/nimpylib/pysubprocess/actions/workflows/ci.yml/badge.svg)](https://github.com/nimpylib/pysubprocess/actions/workflows/ci.yml)
[![Docs](https://github.com/nimpylib/pysubprocess/actions/workflows/docs.yml/badge.svg)](https://github.com/nimpylib/pysubprocess/actions/workflows/docs.yml)

Python-like subprocess management for Nim, with native, Node.js, and Deno
backends. The package exports the portable public surface from Python 3.14's
`subprocess.__all__`:

- `run`, `Popen`, `call`, `check_call`, `check_output`, `getstatusoutput`, and
  `getoutput`
- `CompletedProcess`, `SubprocessError`, `CalledProcessError`, and
  `TimeoutExpired`
- `PIPE`, `STDOUT`, and `DEVNULL`

On Windows it additionally exports `STARTUPINFO` and the documented Windows
creation, priority, standard-handle, and startup constants.

```nim
import pysubprocess

let completed = run(["git", "--version"], capture_output = true, check = true)
echo completed.stdout
```

`CompletedProcess.check_returncode()` is available as
`completed.check_returncode()`. A native `Popen` starts immediately and exposes
`stdin`, `stdout`, `stderr`, `pid`, `returncode`, `poll`, `wait`, `communicate`,
`send_signal`, `terminate`, and `kill`.

Nim strings are used for subprocess input and output on every backend, so
`encoding`, `errors`, `text`, and `universal_newlines` are compatibility
parameters rather than byte/text type switches. Process-creation controls that
`std/osproc` cannot honor (`pass_fds`, user/group changes, `umask`, pipe sizing,
and process groups) are accepted by `Popen` but fail explicitly when set to a
non-default value.

## JavaScript backends
The JavaScript backend uses
`node:child_process.spawnSync` on Node.js and the
`Deno.Command` API on Deno.

JavaScript `Popen` is a deferred synchronous handle: the child runs when
`wait()` or `communicate()` is called. Consequently it has no live PID and
cannot be signalled before execution. This keeps the Python-shaped synchronous
API without pretending that a JavaScript event loop can synchronously wait on
an already-running child.

Compile for Node.js with `nim js -d:nodejs program.nim`. For Deno, omit the
`nodejs` define and grant the permissions needed by the child command, for
example `deno run --allow-run --allow-env --allow-read --allow-write xxx.js`.


### Why `--allow-read --allow-write` for Deno

Read/write permission is needed when non-empty stdin or a timeout is bridged
through a nested `Deno.Command`, because `outputSync()` rejects piped stdin and
does not provide an asynchronous timeout hook.
