type
  Stdio* = enum
    ## Redirection choices accepted by `run`.
    INHERIT, PIPE, STDOUT, DEVNULL

  CompletedProcess* = object
    ## Result returned by `run`.
    args*: seq[string]
    returncode*: int
    stdout*: string
    stderr*: string

  CalledProcessError* = object of CatchableError
    ## Raised when ``check=true`` and the command fails.
    returncode*: int
    cmd*: seq[string]
    output*: string
    stdout*: string
    stderr*: string

proc `$`*(completed: CompletedProcess): string =
  "CompletedProcess(args=" & $completed.args & ", returncode=" &
    $completed.returncode & ")"
