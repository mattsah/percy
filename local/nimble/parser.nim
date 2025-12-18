## A primitive "parser" for .nimble files.
## It does not require the entire compiler to be imported, but it's
## probably more fragile than the declarative parser.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import
    std/re,
    std/json,
    std/sets,
    std/tables,
    std/strutils,
    ./fileinfo

export
    fileinfo

proc parseFile*(source: string, map: var string): NimbleFileInfo =
    const
        params = {
            "strings": @[
                "name", "version", "author", "description",
                "license", "backend", "binDir", "srcDir"
            ],
            "arrays": @[
                "bin", "paths"
            ],
            "objects": @[
                "namedBin"
            ]
        }
    let
        sourceLines = split(source & "\n", '\n')
    var
        mapped: HashSet[string]
        mapLines: seq[string]
        requires: seq[string]
        requiring: string  = ""
        info: JsonNode = %NimbleFileInfo()

    proc parseEqString(line: string): JsonNode =
        let
            value = line.split('=', 1)[1].strip()
        try:
            if value.len > 0 and value[0] == '"':
                return parseJson(value)
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid string value: " & value)

    proc parseEqArray(line: string): JsonNode =
        let
            value = line.split('=', 1)[1].strip()
        try:
            if value.len > 0:
                case value[0]:
                    of '[':
                        return parseJson(value)
                    of '@':
                        return parseJson(value[1..^1])
                    of '"':
                        return parseJson("[" & value & "]")
                    else:
                        discard
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid sequence/array value: " & value)

    proc parseEqObject(line: string): JsonNode =
        let
            value = line.split('=', 1)[1].strip()
        try:
            if value.len > 0 and value[0] == '{':
                return parseJson(value[0..value.rfind('}')])
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid object/map value: " & value)

    for line in sourceLines:
        var
            found = false

        if requiring.len > 0:
            if line.startsWith(' '):
                requiring = requiring & line
                continue
            else:
                requires.add(requiring)
                requiring = ""

        if line.match(re("""^requires\s*"""")):
            requiring = line[line.find('"')..^1]
            if requires.len == 0:
                mapLines.add("{%requires%}")
            continue

        for (kind, items) in params:
            for item in items:
                if not mapped.contains(item) and line.match(re("^" & item & "\\s*=")):
                    try:
                        var
                            node: JsonNode
                        case kind:
                            of "objects":
                                node = parseEqObject(line)
                            of "arrays":
                                node = parseEqArray(line)
                            of "strings":
                                node = parseEqString(line)
                        if node.kind != JNull:
                            info[item] = node
                            mapLines.add("{%" & item & "%}")
                        else:
                            mapLines.add(line)
                    except:
                        raise newException(
                            ValueError,
                            "Failed parsing " & item & ", " & getCurrentExceptionMsg()
                        )
                    mapped.incl(item)
                    found = true
                    break
            if found:
                break
        if found:
            continue

        mapLines.add(line)

    try:
        info["requires"] = parseJson("[" & requires.join(", ") & "]")
    except:
        raise newException(
            ValueError,
            "Failed parsing combined requirements: " & requires.join(", ")
        )

    result = info.to(NimbleFileInfo)
    map = mapLines.join("\n").strip()

    when defined debug:
        echo "Parsed Nimble file:"
        echo %result

proc parseFile*(source: string): NimbleFileInfo =
    var
        map: string
    result = parseFile(source, map)