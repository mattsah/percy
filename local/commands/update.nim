import
    percy,
    basecli

type
    UpdateCommand = ref object of BaseGraphCommand

const
    CommandPreserveOpt = Opt(
        flag: 'p',
        name: "preserve",
        description: "Preserve all local files by skipping any mapping operations"
    )

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
            force = parseBool(console.getOpt(CommandForceOpt))
            newest = parseBool(console.getOpt(CommandNewestOpt))
            preserve = parseBool(console.getOpt(CommandPreserveOpt))

        result = this.resolve(newest, preserve, force)

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update a project's dependencies and write a new lock file",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandForceOpt,
            CommandNewestOpt,
            CommandPreserveOpt
        ]
    )
]
