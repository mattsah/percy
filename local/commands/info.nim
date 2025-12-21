import
    percy,
    basecli

type
    InfoCommand = ref object of BaseGraphCommand

begin InfoCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            infoType = console.getArg("type", "nimble")
            useJson = console.getOpt("json") of true

        case infoType:
            of "nimble":
                if useJson:
                    echo %this.nimbleInfo
                else:
                    echo "Not Implemented Yet"
            of "graph":
                if useJson:
                    echo "Not Implemented Yet"
                else:
                    echo "Not Implemented Yet"
            else:
                stderr.writeLine("Invalid type specified")
                result = 1

shape InfoCommand: @[
    Command(
        name: "info",
        description: "Get useful information about this package",
        args: @[
            Arg(
                name: "type",
                values: @["nimble", "graph"],
                default: "nimble",
                description: "The type of information to get"
            )
        ],
        opts: @[
            Opt(
                flag: 'j',
                name: "json",
                description: "Get the information as JSON"
            )
        ]
    )
]