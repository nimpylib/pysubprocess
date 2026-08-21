import std/macros

macro defineCommandOverloads*(body: untyped): untyped =
  ## Emit the same command API once for an argv openArray and once for a
  ## single command string. The implementation can normalize both through
  ## `commandSpec(args)`.
  if body.kind == nnkStmtList and body.len != 1:
    error("expected exactly one proc definition", body)
  let definition = if body.kind == nnkStmtList: body[0] else: body
  definition.expectKind nnkProcDef
  let params = definition[3]
  params.expectKind nnkFormalParams
  if params.len < 2 or params[1].kind != nnkIdentDefs:
    error("expected a proc whose first parameter is an openArray", definition)

  var stringDefinition = definition.copyNimTree
  stringDefinition[3][1][1] = ident("string")
  result = newStmtList(definition, stringDefinition)
