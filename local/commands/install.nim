import
    percy,
    basecli

type
    InstallCommand = ref object of BaseGraphCommand

begin InstallCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        this.settings.prepare()

        var
            checkouts: seq[Checkout]
        let
            graph = this.getGraph()
            solver = Solver.init(graph)
        #[
        ]#
            results = solver.solve()

        if isSome(results.solution):
            checkouts = this.loadSolution(results.solution.get())

        # Build the dep graph and resolve
        # for each resolved hash
        # git worktree add -d <location> <hash>


shape InstallCommand: @[
    Command(
        name: "install",
        description: "Install all dependencies (use lock file if exists)",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ]
    )
]
