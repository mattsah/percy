import
    percy,
    basecli

type
    InstallCommand = ref object of BaseGraphCommand

begin InstallCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            force = parseBool(console.getOpt("force"))

        if fileExists("percy.lock"):
            var
                solution: Solution
                checkouts: seq[Checkout]

            for commit in parseJson(readFile("percy.lock")):
                let
                    id = commit["id"].getStr()
                    version = commit["version"].to(Version)
                    repository = Repository.init(commit["repository"].getStr())
                    info = commit["info"].to(NimbleFileInfo)

                if not repository.cacheExists:
                    discard repository.clone()

                solution.add(Commit(
                    id: id,
                    version: version,
                    repository: repository,
                    info: info
                ))

            checkouts = this.loadSolution(solution, force)

        else:
            let
                subConsole = this.app.get(Console, false)
            var
                command = @["update", "-n"]

            if this.verbosity:
                command.add("-v:" & $this.verbosity)
            if force:
                command.add("-f")

            result = subConsole.run(command)

shape InstallCommand: @[
    Command(
        name: "install",
        description: "Install all dependencies (use lock file if exists)",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'f',
                name: "force",
                description: "Force checkouts which may otherwise destroy unsaved work in vendor"
            )
        ]
    )
]
