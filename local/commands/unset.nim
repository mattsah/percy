import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

begin UnsetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            graph = this.getGraph()
            solver = Solver.init()
            unsetType = console.getArg("type")
            unsetAlias = console.getArg("alias")

        case unsetType:
            of "source":
                if not this.settings.data.sources.hasKey(unsetAlias):
                    fail fmt "Invalid source alias '{unsetAlias}' specified"
                    info fmt "  Error: does not appear to be set."
                    return 1
                this.settings.data.sources.del(unsetAlias)

            of "package":
                if not this.settings.data.packages.hasKey(unsetAlias):
                    fail fmt "Invalid package alias '{unsetAlias}' specified"
                    info fmt "  Error: does not appear to be set."
                    return 1
                this.settings.data.packages.del(unsetAlias)

        this.settings.prepare(true)

        try:
            graph.build(this.nimbleInfo)
            # TODO: Validate solution and suggest running update
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ],
        args: @[
            Arg(
                name: "type",
                values: @["source", "package"],
                description: "The type of URL to unset"
            ),
            Arg(
                name: "alias",
                description: "The alias for the source or package"
            )
        ]
    )
]