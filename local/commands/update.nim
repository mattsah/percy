import
    percy,
    basecli

type
    UpdateCommand = ref object of BaseGraphCommand

#[
    The update command is responsible for updaing all dependency versions to the latest versions
    that match constraints and writing the solution to the lock file.
]#
begin UpdateCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            force = parseBool(console.getOpt("force"))
            newest = parseBool(console.getOpt("newest"))
            preserve = parseBool(console.getOpt("preserve"))

        result = this.resolve(newest, preserve, force)

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update package(s) and write the lock file",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'n',
                name: "newest",
                description: "Fetch remote HEADs even if local cache is not stale (true update)"
            ),
            Opt(
                flag: 'p',
                name: "preserve",
                description: "Preserve all local files by skipping any mapping operations"
            ),
            Opt(
                flag: 'f',
                name: "force",
                description: "Force checkouts which may otherwise destroy unsaved work in vendor"
            )
        ]
    )
]
