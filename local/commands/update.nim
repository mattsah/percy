import
    percy,
    basecli

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

        if isSome(results.solution):
            checkouts = this.loadSolution(results.solution.get(), force)

            var
                lock = newJArray()
                commit: JsonNode

            for item in %(results.solution.get()):
                commit = newJObject()
                commit["id"] = item["id"]
                commit["info"] = item["info"]
                commit["version"] = item["version"]
                commit["repository"] = item["repository"]["url"]

                lock.add(commit)

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