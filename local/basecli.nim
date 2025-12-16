import
    percy,
    mininim/cli,
    lib/settings,
    lib/depgraph

export
    cli,
    parser,
    settings,
    depgraph

type
    BaseCommand* = ref object of Class
        config*: string
        verbose*: string
        settings*: Settings

    BaseGraphCommand* = ref object of BaseCommand
        nimbleInfo*: NimbleFileInfo
        solver*: Solver

let
    CommandConfigOpt* = Opt(
        flag: "c",
        name: "config",
        default: "percy.json",
        description: "The configuration settings filename"
    )

    CommandVerboseOpt* = Opt(
        flag: "v",
        name: "verbose",
        description: "Whether or not to be verbose in output"
    )



begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config", "c")
        this.verbose = console.getOpt("verbose", "v")
        this.settings = this.app.get(Settings).open(this.config)

begin BaseGraphCommand:
    method execute*(console: Console): int =
        result = super.execute(console)

        this.nimbleInfo = percy.getNimbleInfo()
        this.solver = Solver.init()

    method getGraph*(quiet: bool = false): DepGraph {. base .} =
        result =  DepGraph.init(this.settings, quiet or not this.verbose)

        let
            repository = this.settings.getRepository(getCurrentDir())

        for requirement in this.nimbleInfo.requires:
            result.addRequirement(
                Commit(repository: repository),
                result.parseRequirement(requirement)
            )
