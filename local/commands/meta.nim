import
    percy,
    basecli

type
    MetaCommand = ref object of BaseCommand

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
            path = console.getArg("path")
            action = console.getArg("action")
            value = console.getArg("value")
            force = parseBool(console.getOpt("force"))
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
                            info fmt "> Reason: `{prePath}` is not an object"
                            return 1
                else:
                    try:
                        curVal = this.settings.data.meta.get(path)

                        if curVal.kind notin {newVal.kind, JNull} and not force:
                            raise newException(
                                ValueError,
                                fmt "Value `{value}` would change type (force with -f)"
                            )
                        else:
                            this.settings.data.meta.set(path, newVal)
                    except Exception as e:
                        fail fmt "Cannot set value"
                        info fmt "> Path: {path}"
                        info fmt "> Reason: {e.msg}"
                        return 2

                this.settings.saveConfig()

shape MetaCommand: @[
    Command(
        name: "meta",
        description: "Get or set meta data",
        args: @[
            Arg(
                name: "action",
                values: @["get", "set"],
                description: "The package to require, a sourced alias or a URL"
            ),
            Arg(
                name: "path",
                description: "The meta path to get or set (e.g.: maps.myapp)"
            ),
            Arg(
                name: "value",
                default: "null",
                description: "For `get`, a default value, for `set` the value to set (null unsets)"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'f',
                name: "force",
                description: "Force operations which are generally considered unsafe"
            )
        ]
    )
]
