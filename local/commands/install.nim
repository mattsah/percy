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
            results: SolverResult
        let
            graph = this.getGraph()
            solver = Solver.init()

        graph.build(this.nimbleInfo)

        if this.verbosity > 0:
            graph.report()

        results = solver.solve(graph)

        if isSome(results.solution):
            checkouts = this.loadSolution(results.solution.get())

shape InstallCommand: @[
    Command(
        name: "install",
        description: "Install all dependencies (use lock file if exists)",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ]
    )
]
