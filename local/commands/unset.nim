import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

const
    CommandResourceArg = Arg(
        name: "resource",
        values: @["source", "package"],
        description: "The type of resource to unset"
    )

    CommandReferenceArg = Arg(
        name: "reference",
        description: "The reference to unset, an alias or location (URL or local directory)"
    )


#[
    The `unset` command is responsible for removing a source or package from the configuration
    file, triggering updates and re-indexing of remaining sources and packages and, by default
    attempting to re-resolve the dependency graph.  Resolution can be skipped via the `-s` option
    in order to enable configuration management only.
]#
begin UnsetCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            force = parseBool(console.getOpt("force"))
            resource = console.getArg(CommandResourceArg)
            reference = console.getArg(CommandReferenceArg)
        var
            alias: string
            repository: Repository

        try:
            case resource:
                of "source":
                    alias = this.settings.getSourceAlias(reference)

                    if not alias:
                        raise newException(ValueError, "does not appear to be set")

                    repository = this.settings.data.sources[alias].repository
                    this.settings.data.sources.del(alias)

                of "package":
                    alias = this.settings.getPackageAlias(reference)

                    if not alias:
                        raise newException(ValueError, "does not appear to be set")

                    repository = this.settings.data.packages[alias].repository
                    this.settings.data.packages.del(alias)

        except Exception as e:
            fail fmt "Invalid {resource} specified"
            info fmt "> Error: {e.msg}"
            info fmt "> Reference: {reference}"
            return 1

        this.settings.prepare(force = true, save = false)

        if not skip:
            result = this.resolve(false, false, force)

        if result == 0:
            this.settings.save()
            print fmt "Successfully unset {resource}"
            print fmt "> Location: {repository.url}"
            print fmt "> Alias: {alias}"
        else:
            fail fmt "Unable to update after unsetting {resource}, no files written"
            info fmt "> Location: {repository.url}"
            info fmt "> Alias: {alias}"
            result = 10 + result

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package for the project in the current directory",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
        ],
        args: @[
            CommandResourceArg,
            CommandReferenceArg
        ]
    )
]
