import
    percy,
    mininim/cli,
    lib/settings,
    lib/depgraph,
    lib/lockfile,
    lib/loader

export
    cli,
    parser,
    settings,
    depgraph,
    loader

type
    BaseCommand* = ref object of Class
        config*: string
        verbosity*: int
        settings*: Settings

    BaseGraphCommand* = ref object of BaseCommand
        nimbleInfo*: NimbleFileInfo
        nimbleFile*: string
        nimbleMap*: string

let
    CommandConfigOpt* = Opt(
        flag: 'c',
        name: "config",
        default: "percy.json",
        description: "The configuration settings filename"
    )

    CommandVerbosityOpt* = Opt(
        flag: 'v',
        name: "verbosity",
        default: "0",
        values: @["1", "2", "3"],
        description: "The verbosity level of the output"
    )

begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config")
        this.settings = Settings.open(this.config)
        this.verbosity = parseInt(console.getOpt("verbosity"))

begin BaseGraphCommand:
    method execute*(console: Console): int =
        var
            foundNimble = false

        result = super.execute(console)

        for file in walkFiles("*.nimble"):
            this.nimbleFile = file
            this.nimbleInfo = parser.parse(readFile(file), this.nimbleMap)
            foundNimble = true
            break

        if not foundNimble:
            raise newException(ValueError, "Could not find .nimble file")

    method getGraph*(): DepGraph {. base .} =
        result = DepGraph.init(this.settings, this.verbosity == 0)

    method getLoader*(): Loader {. base .} =
        result = Loader.init(this.settings, this.verbosity == 0)

    method resolve*(newest: bool = false, preserve: bool = false, force: bool = false): int {. base .} =
        let
            graph = this.getGraph()
            loader = this.getLoader()
            solver = Solver.init()
        var
            results: SolverResult
            checkouts: seq[Checkout]

        try:
            graph.build(this.nimbleInfo, newest)
        except Exception as e:
            graph.reportStack()
            fail fmt "Failed Updating"
            info fmt "> Error: {e.msg}"

            with e of MissingRepositoryException:
                info fmt "> Tried: {e.repository.url}"
                if not e.repository.url.contains("://"):
                    if graph.stack.len > 1:
                        info fmt "> Required By: {graph.stack[^2].repository.url}"
                        info fmt """
                            > Hint: Check the requiring repository for custom sources or package
                                    settings that may be able to resolve the package alias to an
                                    appropriate repository, then use `percy set` to add it.
                        """
                    else:
                        info fmt """
                            > Hint: Your project is trying to use a package that it can't find. You
                                    may have forgotten to use `percy set source` to add a source
                                    that can resolve the package alias to a repository. You can
                                    also use `percy set package` to set it directly.
                        """
            return 1

        if this.verbosity > 0:
            graph.report()

        results = solver.solve(graph)

        if isNone(results.solution):
            fail fmt "There Is No Available Solution"
            return 1
        else:
            checkouts = loader.loadSolution(results.solution.get(), preserve, force)

            var
                lock = newJArray()

            for commit in results.solution.get():
                lock.add(commit.toLockFile())

            writeFile("percy.lock", pretty(lock))





