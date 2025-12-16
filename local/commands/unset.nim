import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

begin UnsetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            setType = console.getArg("type")
            setAlias = console.getArg("alias")

        # validate alias
        # validate url

        case setType:
            of "source":
                this.settings.data.sources.del(setAlias)
            of "package":
                this.settings.data.packages.del(setAlias)

        this.settings.prepare(true)
        try:
            discard this.getGraph(true)
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ],
        args: @[
            Arg(
                name: "type",
                require: true,
                values: @["source", "package"],
                description: "The type of URL to unset"
            ),
            Arg(
                name: "alias",
                require: true,
                description: "The alias for the source or package"
            )
        ]
    )
]