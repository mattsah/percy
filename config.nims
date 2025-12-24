#
# Common arguments
#

--mm:atomicArc
--deepcopy:on
--verbosity:1
--path:"local"

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# <percy>
--noNimblePath
import
    std/strutils
when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    for path in readFile("vendor/percy.paths").split("\n"):
        switch("path", path)
# </percy>

# <percy>
#
# Build Task
#

import
    std/os,
    std/json,
    std/strutils

#
# Internal commands
#

proc build(args: seq[string]): void =
    var
        cfg: JsonNode
    when defined(windows):
        let
            (info, error) = gorgeEx("percy info -j 2>NUL")
    else:
        let
            (info, error) = gorgeEx("percy info -j 2>/dev/null")
    if error > 0:
        cfg = parseJson("""{"bin": "", "srcDir": "", "binDir": ""}""")
    else:
        cfg = parseJson(info)

    let
        bins = cfg["bin"].getElems()
        srcDir = cfg["srcDir"].getStr()
        binDir = cfg["binDir"].getStr()
        output = if binDir.len > 0: binDir & "/" else: "./"

    for path in listFiles(if srcDir.len > 1: srcDir else: "./"):
        if path.endsWith(".nim"):
            let
                target = path[path.find('/')+1..^5]
            if bins.len == 0 or bins.contains(%target):
                let
                    cmd = @[
                        "nim -o:" & output,
                        commandLineParams()[1..^1].join(" "),
                        args.join(" "),
                        "c " & path
                    ].join(" ")
                echo "Executing: " & cmd
                exec cmd

task build, "Build the application (whatever it's called)":
    when defined release:
        build(@["--opt:speed", "--linetrace:on", "--checks:on"])
    elif defined debug:
        build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
    else:
        build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])
# </percy>

# <percy>
#
# Test Task
#

task test, "Run testament tests":
    exec "testament --megatest:off --directory:testing " & commandLineParams()[1..^1].join(" ")

# </percy>