#[
    A structured nimble file parser and mapper which tries to extract data and leave the file
    as untouched as possible.  This is hacky, but effective.  It should be noted that this approach
    parses invalid files and does not throw any warnings.

    NOTE:  This file hs been left intentionally in non-mininm style Nim so that it's easier for
    other package managers like neo to use it in their own solution.  This could be its own
    package, but for now it just chills here.
]#
import
    std/re,
    std/json,
    std/sets,
    std/tables,
    std/strutils,
    ./fileinfo

export
    fileinfo

const
    params = {
        "strings": @[
            "name", "author", "description",
            "license", "backend", "binDir", "srcDir"
        ],
        "arrays": @[
            "bin", "paths"
        ],
        "objects": @[
            "namedBin"
        ]
    }.toTable()

proc parse*(source: string, map: var string): NimbleFileInfo =
    let
        sourceLines = split(source & "\n", '\n')
    var
        info: JsonNode = %NimbleFileInfo()
        mapped: HashSet[string]
        mapLines: seq[string]
        requires: seq[string]
        requiring: string = ""
        indenting: string = ""
        current = -1

    proc clean(value: string, breakCommas: bool = false): string =
        var
            inString = false
        #
        # Fix comments and other abnormalities
        #
        for pos, i in value:
            if i == '"':
                if inString:
                    inString = false
                else:
                    inString = true
            elif i == ',':
                if inString and breakCommas:
                    result.add("""", """")
                    continue
            elif i == '#':
                if not inString:
                    break
            result.add(i)

    proc parseUntil(value: var string, closing: char): void =
        while current < sourceLines.high:
            let
                rclose = value.rfind(closing)
            if rclose > 0:
                value = value[0..rclose]
                break
            else:
                inc current
                value = value & sourceLines[current].clean().strip()

    proc parseEqString(line: string): JsonNode =
        var
            value = line.split('=', 1)[1].clean().strip()
        try:
            if value.len > 0:
                if value.startsWith("\"\""):
                    value = value[0..value.rfind('"')].strip(chars = {'"'}).escape()
                elif value[0] == '"':
                    value = value[0..value.rfind('"')]
                else:
                    value = value.escape()
                return parseJson(value)
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid string value: " & value)

    proc parseEqArray(line: string): JsonNode =
        var
            value = line.split('=', 1)[1].strip()

        try:
            if value.len > 0:
                case value[0]:
                    of '[', '@':
                        parseUntil(value, ']')
                        return parseJson(value.strip(chars = {'@'}))
                    of '"':
                        return parseJson("[" & $parseEqString(" = " & value) & "]")
                    else:
                        discard
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid sequence/array value: " & value)

    proc parseEqObject(line: string): JsonNode =
        var
            value = line.split('=', 1)[1].strip()

        parseUntil(value, '}')

        try:
            if value.len > 0:
                case value[0]:
                    of '{':
                        return parseJson(value[0..value.rfind('}')])
                    else:
                        discard
            else:
                return newJNull()
        except:
            discard

        raise newException(ValueError, "invalid object/map value: " & value)

    while current < sourceLines.high:
        inc current

        var
            found = false
        let
            line = sourceLines[current]

        if requiring.len > 0:
            if line.startsWith(indenting & ' '):
                requiring = requiring & line
                continue
            else:
                requires.add(requiring)
                requiring = ""

        if line.match(re("""^\s*requires\s*"""")):
            indenting = ""
            requiring = line[line.find('"')..^1]
            for i in line:
                if i == ' ':
                    indenting.add(' ')
                else:
                    break
            mapLines.add(indenting & "{%requires-" & $requires.len & "%}")
            continue

        for kind, items in params:
            for item in items:
                if line.match(re("^" & item & """\[.*\]\s*=""")):
                    discard
                elif line.match(re("^" & item & """\s*=""")) and not mapped.contains(item):
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
                            else:
                                discard
                        if node.kind != JNull:
                            mapped.incl(item)
                            mapLines.add("{%" & item & "%}")
                            info[item] = node
                            found = true
                    except:
                        raise newException(
                            ValueError,
                            "Failed parsing " & item & ", " & getCurrentExceptionMsg()
                        )
                    break
                else:
                    discard
            if found:
                break
        if not found:
            mapLines.add(line)

    map = mapLines.join("\n").strip()

    for linereqs in requires:
        let
            cleaned = linereqs.clean(breakCommas = true)
        try:
            info["requires"].add(parseJson("[" & cleaned & "]"))
        except:
            raise newException(
                ValueError,
                "Failed parsing requirements: " & cleaned
            )

    if info.hasKey("bin"):
        if not info.hasKey("namedBin"):
            info["namedBin"] = newJObject()
        for bin in info["bin"]:
            let
                name = bin.getStr()
            if not info["namedBin"].hasKey(name):
                info["namedBin"][name] = bin

    result = info.to(NimbleFileInfo)

proc parse*(source: string): NimbleFileInfo =
    var
        map: string
    result = parse(source, map)

proc render*(map: string, info: NimbleFileInfo): string =
    result = map

    for field, value in %info:
        if field == "requires":
            var
                offset = 0
            for requirements in value:
                if requirements.len == 0:
                    result = result.replace(
                        "{%requires-" & $offset & "%}\n",
                        ""
                    )
                else:
                    result = result.replace(
                        "{%requires-" & $offset & "%}",
                        "requires " & requirements.pretty.strip(chars = {'[', ']', '\n', ' '})
                    )
                inc offset
        else:
            let
                token = "{%" & field & "%}"
            if params["strings"].contains(field):
                result = result.replace(token, field & " = " & value.pretty)
            elif params["arrays"].contains(field):
                result = result.replace(token, field & " = @" & value.pretty)
            elif params["objects"].contains(field):
                result = result.replace(token, field & " = toTable(" & value.pretty & ")")
            else:
                discard

    result = result.strip() & "\n"
