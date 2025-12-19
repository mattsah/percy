#
# Common arguments
#

--mm:atomicArc
--deepcopy:on
--verbosity:1
--path:"local"

# <percy>
when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    include "vendor/percy.paths"
# </percy>

# <percy>
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
    let
        (info, error) = gorgeEx("percy info -j")

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

# Tasks

task test, "Run testament tests":
    exec "testament --megatest:off --directory:testing " & commandLineParams()[1..^1].join(" ")

task build, "Build the application (whatever it's called)":
    when defined release:
        build(@["--opt:speed", "--linetrace:on", "--checks:on"])
    elif defined debug:
        build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
    else:
        build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])
# </percy>