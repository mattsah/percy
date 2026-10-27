discard """
  timeout: 300
"""

import std/os, std/osproc, std/strutils, std/tempfiles

const nimBin = getCurrentCompilerExe()

let
  percyBin =
    currentSourcePath().parentDir() / ".." / ".." / ".." / "bin" / ("percy" & ExeExt)
  root = createTempDir("percy-golden-", "")
  repos = root / "repos"
  app = root / "app"

#
# Keep percy's cache and data out of the user's home directory
#

putEnv("XDG_CACHE_HOME", root / "cache")
putEnv("XDG_DATA_HOME", root / "data")

proc run(dir: string, cmd: string): string =
  let (output, code) = execCmdEx(cmd, workingDir = dir)

  doAssert code == 0, "`" & cmd & "` exited with " & $code & ":\n" & output

  result = output.strip()

proc percy(args: string): string =
  result = run(app, quoteShell(percyBin) & " " & args)

proc commit(dir: string, tag: string = ""): void =
  discard run(dir, "git add -A")
  discard run(dir, "git -c user.name=test -c user.email=test@test commit -q -m fixture")
  if tag.len > 0:
    discard run(dir, "git tag " & tag)

proc makeLibrary(name: string, requires: string, versions: seq[string]): void =
  let dir = repos / name

  createDir(dir / "src")
  discard run(dir, "git init -q")

  for version in versions:
    writeFile(
      dir / name & ".nimble",
      @[
        "version = \"" & version & "\"",
        "author = \"test\"",
        "description = \"" & name & "\"",
        "license = \"MIT\"",
        "srcDir = \"src\"",
        requires,
      ].join("\n"),
    )
    writeFile(
      dir / "src" / name & ".nim", "const " & name & "Version* = \"" & version & "\"\n"
    )
    commit(dir, "v" & version)

#
# Fixtures
#

doAssert fileExists(percyBin),
  "percy binary not found at " & percyBin & " (run `nimble build`)"

makeLibrary("liba", "", @["1.0.0", "1.1.0", "2.0.0"])
makeLibrary("libb", "requires \"liba >= 1.0.0 & < 2.0.0\"", @["1.0.0"])

createDir(repos / "registry")
discard run(repos / "registry", "git init -q")
writeFile(
  repos / "registry" / "packages.json",
  """[
    {"name": "liba", "url": "$1", "method": "git"},
    {"name": "libb", "url": "$2", "method": "git"}
]""" %
    [repos / "liba", repos / "libb"],
)
commit(repos / "registry")

createDir(app)
writeFile(
  app / "app.nimble",
  "version = \"0.1.0\"\nauthor = \"test\"\ndescription = \"app\"\nlicense = \"MIT\"\n",
)
writeFile(app / "app.nim", "import liba, libb\necho libaVersion, \" \", libbVersion\n")

#
# A pre-existing empty config stops init from adding the remote nim-lang source
#

writeFile(app / "percy.json", """{"meta": {}, "sources": {}, "packages": {}}""")

#
# init: wires vendor paths into config.nims
#

discard percy("init")
doAssert readFile(app / "config.nims").contains("vendor/percy.paths")

#
# set source: indexes packages from the registry's packages.json
#

discard percy("set source " & quoteShell(repos / "registry"))
doAssert readFile(app / "percy.json").contains("registry")

#
# require: resolves the transitive dependency to the newest compatible version
#

discard percy("require libb \">= 1.0.0\"")
doAssert readFile(app / "app.nimble").contains("libb")
doAssert fileExists(app / "percy.lock")
doAssert run(app, quoteShell(nimBin) & " c -r --hints:off app.nim").endsWith(
  "1.1.0 1.0.0"
)

#
# install: rebuilds vendor from the lock file
#

removeDir(app / "vendor")
discard percy("install")
doAssert readFile(app / "vendor" / "+global" / "liba" / "src" / "liba.nim").contains(
  "1.1.0"
)
doAssert dirExists(app / "vendor" / "+global" / "libb")

#
# remove: drops the requirement and its dependencies
#

discard percy("remove libb")
doAssert not readFile(app / "app.nimble").contains("libb")
doAssert not dirExists(app / "vendor" / "+global" / "liba")

removeDir(root)
