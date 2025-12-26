import
    percy,
    basecli,
    lib/lockfile

type
    InstallCommand = ref object of BaseGraphCommand

begin InstallCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            loader = this.getLoader()
            force = parseBool(console.getOpt("force"))

        if fileExists("percy.lock"):
            var
                solution: Solution
                checkouts: seq[Checkout]

            for node in parseJson(readFile("percy.lock")):
                let
                    commit = Commit.fromLockFile(node)
                if not commit.repository.cacheExists:
                    discard commit.repository.clone()
                solution.add(commit)

            checkouts = loader.loadSolution(solution, force)

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
