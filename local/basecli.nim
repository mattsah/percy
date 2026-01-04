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

    CommandSkipOpt* = Opt(
        flag: 's',
        name: "skip-resolution",
        description: "Skip resolution (i.e. don't build out vendor, just manage config)"
    )

begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config")
        this.settings = Settings.open(this.config)
        this.verbosity = parseInt(console.getOpt("verbosity"))

begin BaseGraphCommand:
    method execute*(console: Console): int =
        result = super.execute(console)

        for file in walkFiles("*.nimble"):
            this.nimbleFile = file
            this.nimbleInfo = parser.parse(readFile(file), this.nimbleMap)
            break

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
            results: SolverResults
            checkouts: seq[Checkout]
            lockFile = LockFile.init(fmt "{percy.name}.lock")

        try:
            graph.build(this.nimbleInfo, newest)
        except Exception as e:
            if graph.stack.len > 0:
                graph.reportStack()
            fail fmt "Failed updating"
            info fmt "> Error: {e.msg}"

            with e of NoUsableVersionsException:
                info fmt "> Repositories:"
                for repository in e.repositories:
                    info fmt "       {repository.url}"

            with e of EmptyCommitPoolException:
                info fmt "> Attempted URL: {e.requirement.repository.url}"
                info fmt "> Required As: {e.requirement.package}"
                if e.requirement.package.contains("://"):
                    info fmt """
                        > Hint: There was most likely an issue connecting to the repository, you
                                should verify it exists at the specified URL.
                    """
                else:
                    info fmt """
                        > Hint: Your project is trying to use a package that it can't find. This
                                most likely indicates that it was removed from an existing
                                source, or you may have forgotten to set a required source. Use
                                `percy set source` to add a source that can resolve the package
                                alias to a valid git repository. Alternatively, you can use
                                `percy set package` to set it directly.
                    """
            return 1

        if this.verbosity > 0:
            graph.report()

        results = solver.solve(graph)

        if results.isEmpty:
            fail fmt "There Is No Available Solution"
            return 1
        else:
            checkouts = loader.loadSolution(results.solution.get(), preserve, force)

            lockFile.save(results)
