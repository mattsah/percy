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
        let
            cfg = "\"\"\"{\"bin\": \"\", \"srcDir\": \"\", \"binDir\": \"\"}\"\"\""

        result = dedent(
            fmt """
            # <{percy.name}>
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
                    cfg = parseJson({cfg})
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
            # </{percy.name}>
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
            repo = console.getArg("repo")
        var
            error: int
            target = console.getArg("target")

        if repo:
            let
                repository = Repository.init(repo)

            if not target:
                target = repository.url[repository.url.rfind('/')..^1]
                if target.endsWith(".git"):
                    target = target[0..^5]

            if dirExists(target) or fileExists(target):
                echo fmt "Cannot initialize repository in {target}, already exists"
                return 1

            error = percy.execCmd(@[
                fmt "git clone {repository.url} {target}"
            ])

            if error:
                return error

            setCurrentDir(target)

            this.settings = this.settings.open(this.config)

        if not fileExists(this.settings.config) or reset:
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

        if repo:
            error = percy.execCmd(@[
                fmt "{getAppFilename()} install"
            ])

            if error:
                return error

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize as a percy package",
        args: @[
            Arg(
                name: "repo",
                description: "A repository to clone, if empty current directory is intialized"
            ),
            Arg(
                name: "target",
                description: "The directory to clone to, if empty named after repository"
            )
        ],
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