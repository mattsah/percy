import
    std/os,
    std/strutils

#
# Common arguments
#

--mm:atomicArc
--deepcopy:on
--verbosity:1
--path:"./local"
--path:"./vendor"

#
# Internal commands
#

proc build(args: seq[string]): void =
    for path in listFiles("./"):
        if path.endsWith(".nim"):
            exec @[
                "nim -o:bin/" & splitFile(path).name,
                commandLineParams()[1..^1].join(" "),
                args.join(" "),
                "c " & path
            ].join(" ")

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

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
