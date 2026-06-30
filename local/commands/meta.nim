import
    percy,
    basecli

type
    MetaCommand = ref object of BaseCommand

const
    CommandActionArg = Arg(
        name: "action",
        values: @["get", "set"],
        description: "The action that will be performed"
    )

    CommandPathArg = Arg(
        name: "path",
        description: "The dot-separated path to modify (e.g.: maps.myapp)"
    )

    CommandValueArg = Arg(
        name: "value",
        default: "null",
        description: "For `get`, a default if not set, for `set` the value itself (null unsets)"
    )

#[
    Get or set meta data in the JSON configuration
]#
begin MetaCommand:
    #[
        Translated a user provided string value into a proper JSON node
    ]#
    method translateValue(value: string): JsonNode {. base .} =
        var
            value = value.strip()
            floatVal: float
            intVal: int

        if value == "null":
            result = newJNull()
        elif value == "true":
            result = newJBool(true)
        elif value == "false":
            result = newJBool(false)
        elif value.parseInt(intVal) == value.len:
            result = newJInt(intVal)
        elif value.parseFloat(floatVal) == value.len:
            result = newJFloat(floatVal)
        else:
            result = newJString(value)

    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            path = console.getArg(CommandPathArg)
            action = console.getArg(CommandActionArg)
            value = console.getArg(CommandValueArg)
            force = parseBool(console.getOpt(CommandForceOpt))
        var
            newVal = this.translateValue(value)
            curVal: JsonNode

        case action:
            of "get":
                curVal = this.settings.data.meta.get(path)

                if curVal.kind == JNull:
                    print $newVal
                else:
                    print $curVal

            of "set":
                if newVal.kind == JNull:
                    var
                        parts = path.split('.')
                    let
                        setKey = parts.pop()
                        prePath = parts.join(".")

                    if parts.len == 0:
                        this.settings.data.meta.delete(setKey)
                    else:
                        curVal = this.settings.data.meta.get(prePath)

                        if curVal.kind == JObject:
                            curVal.delete(setKey)
                        else:
                            info fmt "Unsetting has no effect"
                            info fmt "> Path: {path}"
                            info fmt "> Hint: `{prePath}` is not an object"
                            return 1
                else:
                    try:
                        curVal = this.settings.data.meta.get(path)

                        if curVal.kind notin {newVal.kind, JNull} and not force:
                            raise newException(
                                ValueError,
                                fmt "setting `{value}` would change type (force with -f)"
                            )
                        else:
                            this.settings.data.meta.set(path, newVal)
                    except Exception as e:
                        fail fmt "Cannot set value"
                        info fmt "> Error: {e.msg}"
                        info fmt "> Path: {path}"
                        return 2

                this.settings.saveConfig()

shape MetaCommand: @[
    Command(
        name: "meta",
        description: "Get or set meta data for the project in the current directory",
        detail: """
            Meta data is used by percy's extended features. It can also store arbitrary data that
            can be used in your project's build or support scripts by executing `percy meta get`.
            Since it is stored in the configuration file (`percy.json` by default) file, it is
            generally committed and version controlled with your project's sources or package
            overloads.
        """,
        args: @[
            CommandActionArg,
            CommandPathArg,
            CommandValueArg
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandForceOpt
        ]
    )
]
