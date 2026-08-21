# Package

version       = "0.1.0"
author        = "litlighilit"
description   = "like Lib/subprocess of Python"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim > 2.0.8"

var pylibPre = "https://github.com/nimpylib"
let envVal = getEnv("NIMPYLIB_PKGS_BARE_PREFIX")
if envVal != "": pylibPre = ""
elif pylibPre[^1] != '/':
  pylibPre.add '/'
template pylib(package, version) =
  requires if pylibPre == "": package & version
           else: pylibPre & package

pylib "jscompat", " ^= 0.1.6"
