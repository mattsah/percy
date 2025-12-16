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
            setUrl = console.getArg("url")
            setType = console.getArg("type")
            setAlias = console.getArg("alias")

        # validate alias
        # validate url

        case setType:
            of "source":
                this.settings.data.sources[setAlias] = Source.init(
                    this.settings.getRepository(setUrl)
                )
            of "package":
                this.settings.data.packages[setAlias] = Package.init(
                    this.settings.getRepository(setUrl)
                )

        this.settings.prepare(true)
        try:
            discard this.getGraph(true)
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ],
        args: @[
            Arg(
                name: "type",
                require: true,
                values: @["source", "package"],
                description: "The type of URL to set"
            ),
            Arg(
                name: "alias",
                require: true,
                description: "The alias for the source or package"
            ),
            Arg(
                name: "url",
                require: true,
                description: "A valid git URL for the source or package repository"
            )
        ]
    )
]