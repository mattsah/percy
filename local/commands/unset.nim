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
        var
            repository: Repository

        case unsetType:
            of "source":
                if not this.settings.data.sources.hasKey(unsetAlias):
                    fail fmt "Invalid source alias specified"
                    info fmt "> Error: does not appear to be set."
                    info fmt "> Source Alias: {unsetAlias}"
                    return 1

                repository = this.settings.data.sources[unsetAlias].repository
                this.settings.data.sources.del(unsetAlias)

            of "package":
                if not this.settings.data.packages.hasKey(unsetAlias):
                    fail fmt "Invalid package alias specified"
                    info fmt "> Error: does not appear to be set."
                    info fmt "> Package Alias: {unsetAlias}"
                    return 1

                repository = this.settings.data.packages[unsetAlias].repository
                this.settings.data.packages.del(unsetAlias)

        this.settings.prepare(true)

        try:
            graph.build(this.nimbleInfo)
            # TODO: Validate solution and suggest running update
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

        print fmt "Successfully unset {unsetType}"
        print fmt "> Repository: {repository.url}"
        print fmt "> Package Alias: {unsetAlias}"
        result = 0


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