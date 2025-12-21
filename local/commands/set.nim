import
    percy,
    basecli,
    lib/package,
    lib/source

type
    SetCommand = ref object of BaseGraphCommand

begin SetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            graph = this.getGraph()
            solver = Solver.init()
            setUrl = console.getArg("url")
            setType = console.getArg("type")
            setAlias = console.getArg("alias")
            repository = Repository.init(setUrl)

        case setType:
            of "source":
                try:
                    Source.validateName(setAlias)
                    this.settings.data.sources[setAlias] = Source.init(repository)
                except:
                    fail fmt "Invalid source alias '{setAlias}' specified"
                    info fmt "  Error: {getCurrentExceptionMsg()}"
                    return 1
            of "package":
                try:
                    Package.validateName(setAlias)
                    this.settings.data.packages[setAlias] = Package.init(repository)
                except:
                    fail fmt "Invalid package alias '{setAlias}' specified"
                    info fmt "  Error: {getCurrentExceptionMsg()}"
                    return 1

        if not repository.exists:
            fail fmt "Invalid url specified"
            info fmt "  Error: {getCurrentExceptionMsg()}"
            return 2

        this.settings.prepare(true)

        try:
            graph.build(this.nimbleInfo)
            # TODO: Validate solution and suggest running update
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ],
        args: @[
            Arg(
                name: "type",
                values: @["source", "package"],
                description: "The type of URL to set"
            ),
            Arg(
                name: "alias",
                description: "The alias for the source or package"
            ),
            Arg(
                name: "url",
                description: "A valid git URL for the source or package repository"
            )
        ]
    )
]