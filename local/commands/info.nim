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
                    print $(%this.nimbleInfo)
                    return 0
                else:
                    print "Not Implemented Yet"
            of "graph":
                if useJson:
                    print "Not Implemented Yet"
                else:
                    print "Not Implemented Yet"
            else:
                fail fmt "Invalid type specified"

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
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'j',
                name: "json",
                description: "Get the information as JSON"
            )
        ]
    )
]