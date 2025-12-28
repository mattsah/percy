


import
    percy,
    basecli

type
    MetaCommand = ref object of BaseCommand

begin MetaCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            path = console.getArg("path")
            action = console.getArg("action")
            value = console.getArg("value").strip()
            force = parseBool(console.getOpt("force"))
        var
            current: JsonNode
            jsonVal: JsonNode
            floatVal: float
            intVal: int

        if value == "null":
            jsonVal = newJNull()
        elif value == "true":
            jsonVal = newJBool(true)
        elif value == "false":
            jsonVal = newJBool(false)
        elif value.parseInt(intVal) == value.len:
            jsonVal = newJInt(intVal)
        elif value.parseFloat(floatVal) == value.len:
            jsonVal = newJFloat(floatVal)
        else:
            jsonVal = newJString(value)

        case action:
            of "get":
                current = this.settings.data.meta.get(path)

                if current.kind == JNull:
                    print $jsonVal
                else:
                    print $current

            of "set":
                if jsonVal.kind == JNull:
                    var
                        parts = path.split('.')
                    let
                        setKey = parts.pop()
                        prePath = parts.join(".")

                    if parts.len == 0:
                        this.settings.data.meta.delete(setKey)
                    else:
                        current = this.settings.data.meta.get(prePath)

                        if current.kind == JObject:
                            current.delete(setKey)
                            this.settings.saveConfig()
                        else:
                            info fmt "Unsetting has no effect"
                            info fmt "> Path: {path}"
                            info fmt "> Reason: `{prePath}` is not an object"
                else:
                    try:
                        current = this.settings.data.meta.get(path)

                        if current.kind notin {jsonVal.kind, JNull} and not force:
                            raise newException(
                                ValueError,
                                fmt "Value `{value}` would change type (force with -f)"
                            )
                        else:
                            this.settings.data.meta.set(path, jsonVal)
                            this.settings.saveConfig()
                    except Exception as e:
                        fail fmt "Cannot set value"
                        info fmt "> Path: {path}"
                        info fmt "> Reason: {e.msg}"
                        return 1

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
