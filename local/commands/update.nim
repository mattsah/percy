import
    percy,
    basecli

type
    UpdateCommand = ref object of BaseGraphCommand

begin UpdateCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            force = parseBool(console.getOpt("force"))
            newest = parseBool(console.getOpt("newest"))

        result = this.resolve(newest, force)

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update package(s) and write the lock file",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'f',
                name: "force",
                description: "Force checkouts which may otherwise destroy unsaved work in vendor"
            ),
            Opt(
                flag: 'n',
                name: "newest",
                description: "Force fetching of HEADs even if local cache is not stale"
            )
        ]
    )
]
