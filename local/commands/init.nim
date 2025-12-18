import
    percy,
    basecli

type
    InitCommand = ref object of BaseCommand

begin InitCommand:
    method getPaths(): string {. base .} =
        result = dedent(
            fmt """
            # <{percy.name}>

            when withDir(thisDir(), system.fileExists("vendor/{percy.name}.paths")):
                include "vendor/{percy.name}.paths"

            # </{percy.name}>
            """
        )

    method getTasks(): string {. base .} =
        result = dedent(
            fmt """
            import
                std/os,
                std/strutils

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
            """
        )

    method execute(console: Console): int =
        result = super.execute(console)

        var
            nowrite = 0
            configIn: seq[string]
            configOut: seq[string]
        let
            reset = console.getOpt("reset", "r")

        if reset:
            this.settings.data.sources.clear()
            this.settings.data.packages.clear()

            this.settings.data.meta = newJObject()
            this.settings.data.sources["nim-lang"] = Source.init(
                this.settings.getRepository("gh://nim-lang/packages")
            )

        if fileExists("config.nims"):
            configIn = readFile("config.nims").split('\n')

        for line in configIn:
            if line == fmt "# <{percy.name}>":
                inc nowrite
                continue
            if line == fmt "# </{percy.name}>":
                dec nowrite
                continue

            if nowrite:
                continue

            configOut.add(line)

        var
            config = ""

        config = configOut.join("\n").strip()
        config = config & "\n\n" & this.getPaths().strip()

        if console.getOpt("writeTasks", "w") of true:
            config = config & "\n\n" & this.getTasks.strip()

        writeFile("config.nims", config)

        this.settings.prepare(true)
        this.settings.save()



shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize as a percy package",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
            Opt(
                flag: "w",
                name: "withTasks",
                description: "Include nim build/test tasks"
            ),
            Opt(
                flag: "r",
                name: "reset",
                description: "Reset the source/packages back to standard nim"
            )
        ]
    )
]