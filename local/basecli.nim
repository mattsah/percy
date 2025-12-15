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
        depGraph*: DepGraph
        nimbleInfo*: NimbleFileInfo

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
        this.depGraph = DepGraph.init(this.settings, this.nimbleInfo)