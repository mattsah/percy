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
        file*: string
        settings*: Settings

    BaseGraphCommand* = ref object of BaseCommand
        nimbleInfo*: NimbleFileInfo
        solver*: Solver

let
    CommandFileOpt* = Opt(
        flag: "f",
        name: "file",
        default: "percy.json",
        description: "The settings filename"
    )

begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.file = console.getOpt("file", "f")
        this.settings = this.app.get(Settings).open(this.file)

begin BaseGraphCommand:
    method execute*(console: Console): int =
        result = super.execute(console)

        this.nimbleInfo = percy.getNimbleInfo()
        this.solver = Solver.init()

    method getGraph*(): DepGraph {. base .} =
        result =  DepGraph.init(this.settings)

        for requirement in this.nimbleInfo.requires:
            result.addRequirement(
                Commit(),
                Repository.init(getCurrentDir()),
                result.parseRequirement(requirement)
            )
