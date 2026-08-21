# pysubprocess

[![Test](https://github.com/nimpylib/pysubprocess/actions/workflows/ci.yml/badge.svg)](https://github.com/nimpylib/pysubprocess/actions/workflows/ci.yml)
[![Docs](https://github.com/nimpylib/pysubprocess/actions/workflows/docs.yml/badge.svg)](https://github.com/nimpylib/pysubprocess/actions/workflows/docs.yml)

Python-like synchronous subprocess helpers for Nim, with native, Node.js, and
Deno backends.

```nim
import pysubprocess

let completed = run(["git", "--version"], capture_output = true, check = true)
echo completed.stdout
```

## Js backend
The JavaScript backend uses
`node:child_process.spawnSync` on Node.js and the
`Deno.Command` API on Deno.

Compile for Node.js with `nim js -d:nodejs program.nim`. For Deno, omit the
`nodejs` define and grant the permissions needed by the child command, for
example `deno run --allow-run --allow-env --allow-read --allow-write xxx.js`.


### why `--allow-read --allow-write` for deno
Read/write permission is needed only when non-empty stdin must be bridged for
Deno's synchronous command API, because
outputSync() rejects piped stdin

