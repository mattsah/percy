import
    percy,
    basecli,
    lib/package,
    lib/source

type
    SetCommand = ref object of BaseGraphCommand

const
    CommandAliasArg = Arg(
        name: "alias",
        default: "url=<location:path> | directory=<location:basename>",
        description: "The name by which the resource can be referenced"
    )

#[
    The `set` command is responsible for adding a source or package to the configuration file,
    triggering updates and re-indexing of existing and new sources and packages and, by default
    attempting to re-resolve the dependency graph.  Resolution can be skipped via the `-s` option
    in order to enable configuration management only.
]#
begin SetCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt(CommandSkipOpt))
            force = parseBool(console.getOpt(CommandForceOpt))
            resource = console.getArg(CommandResourceArg)
            location = console.getArg(CommandLocationArg)
            repository = Repository.init(location)
            alias = console.getArg(CommandAliasArg, repository.defaultAlias)

        try:
            case resource:
                of "source":
                    Source.validateName(alias)
                    this.settings.data.sources[alias.toLower()] = Source.init(repository)
                of "package":
                    Package.validateName(alias)
                    this.settings.data.packages[alias.toLower()] = Package.init(repository)
        except Exception as e:
            fail fmt "Invalid {resource} alias (specify a valid alias)"
            info fmt "> Error: {e.msg}"
            info fmt "> Alias: {alias}"
            return 1

        try:
            Repository.validateUrl(repository.url)

            if not repository.exists:
                raise newException(
                    ValueError,
                    fmt "could not reach repository at {location}"
                )

        except Exception as e:
            fail fmt "Invalid url specified"
            info fmt "> Error: {e.msg}"
            info fmt "> Location: {location}"
            return 2

        this.settings.prepare(force = true, save = false)

        if not skip:
            result = this.resolve(false, false, force)

        if result == 0:
            this.settings.save()
            print fmt "Successfully added {resource}"
            print fmt "> Location: {repository.url}"
            print fmt "> Alias: {alias}"
        else:
            fail fmt "Unable to update after setting {resource}, no files written"
            info fmt "> Location: {repository.url}"
            info fmt "> Alias: {alias}"
            result = 10 + result

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package's location and alias",
        detail: """
            This tells percy where to get packages. You can set the location of a single package
            or add an entirely new source of packages. Source repositories must contain, at minimum,
            a `packages.json` file, such as the official nim package list and nimble directory.
        """,
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandForceOpt,
            CommandSkipOpt,
        ],
        args: @[
            CommandResourceArg,
            CommandLocationArg,
            CommandAliasArg
        ]
    )
]
