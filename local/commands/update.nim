import
    percy,
    basecli,
    lib/lockfile

type
    UpdateCommand = ref object of BaseGraphCommand

begin UpdateCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        var
            checkouts: seq[Checkout]
            results: SolverResult
        let
            force = parseBool(console.getOpt("force"))
            newest = console.getOpt("newest")
            solver = Solver.init()
            graph = this.getGraph()

        graph.build(this.nimbleInfo, parseBool(newest))

        if this.verbosity > 0:
            graph.report()

        results = solver.solve(graph)

        if isNone(results.solution):
            fail fmt "There Is No Available Solution"
            return 1
        else:
            checkouts = this.loadSolution(results.solution.get(), force)

            var
                lock = newJArray()
                commit: JsonNode

            for commit in results.solution.get():
                lock.add(commit.toLockFile())

            writeFile("percy.lock", pretty(lock))

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update package(s) and write the lock file",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'f',
                name: "force",
                description: "Force checkouts which may otherwise destroy unsaved work in vendor"
            ),
            Opt(
                flag: 'n',
                name: "newest",
                description: "Force fetching of HEADs even if local cache is not stale"
            )
        ]
    )
]
