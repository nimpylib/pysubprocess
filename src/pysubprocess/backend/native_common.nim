import std/osproc

import ../types

proc processOptions*(shell, parentStreams: bool;
    stderrMode: Stdio): set[ProcessOption] =
  result = {poUsePath}
  if shell: result.incl poEvalCommand
  if stderrMode == STDOUT: result.incl poStdErrToStdOut
  if parentStreams: result.incl poParentStreams
