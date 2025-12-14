import
    percy,
    mininim/dic,
    lib/source,
    lib/package,
    lib/repository,
    std/uri

export
    source,
    package,
    repository

type
    SettingsData = object
        meta* = newJObject()
        build* = newJObject()
        sources* = initOrderedTable[string, Source]()
        packages* = initOrderedTable[string, Package]()

    Settings* = ref object of Class
        data* = SettingsData()
        index*: OrderedTable[string, string]

begin Settings:
    method validateBuild(node: JsonNode): void {. base .} =
        discard

    method validatePackages(node: JsonNode): void {. base .} =
        if node.kind != JObject:
            raise newException(ValueError, "`packages` must be an object.")
        for key, value in node:
            try:
                Package.validateName(key)
            except:
                raise newException(
                    ValueError,
                    fmt "`packages` key '{key}' contains invalid package name: {getCurrentExceptionMsg()}."
                )

            try:
                if value.kind != JString:
                    raise newException(ValueError, "not a string")
                Repository.validateUrl(getStr(value))
            except:
                raise newException(
                    ValueError,
                    fmt "`packages` value for '{key}' contains invalid URL value: {getCurrentExceptionMsg()}."
                )

    method validateSources(node: JsonNode): void {. base .} =
        if node.kind != JObject:
            raise newException(ValueError, "`sources` must be an object.")
        for key, value in node:
            try:
                Source.validateName(key)
            except:
                raise newException(
                    ValueError,
                    fmt "`sources` key '{key}' contains invalid source name: {getCurrentExceptionMsg()}."
                )

            try:
                if value.kind != JString:
                    raise newException(ValueError, "not a string")
                Repository.validateUrl(getStr(value))
            except:
                raise newException(
                    ValueError,
                    fmt "`sources` value for '{key}' contains invalid URL value: {getCurrentExceptionMsg()}"
                )

    method validate(node: JsonNode): void {. base .} =
        try:
            if node.kind != JObject:
                raise newException(ValueError, "must contain an object.")
            for key, value in node:
                case key:
                    of "meta":
                        discard

                    of "sources":
                        this.validateSources(value)
                        for name, url in value:
                            this.data.sources[name] = Source.init(getStr(url))

                    of "packages":
                        this.validatePackages(value)
                        for name, url in value:
                            this.data.packages[name] = Package.init(getStr(url))

                    of "build":
                        this.validateBuild(value)

                    else:
                        raise newException(ValueError, fmt "unknown configuration key '{key}'")

        except ValueError:
            raise newException(
                ValueError,
                (fmt "Invalid {percy.name}.json, ") & getCurrentExceptionMsg()
            )

    method getName*(url: string): string {. base .} =
        result = ""
        for name, value in this.index:
            if url == value:
                result = name
                break;

    method load*(file: string = percy.name & ".json"): void {. base .} =
        var
            node: JsonNode
        let
            index = percy.target / percy.index
        if fileExists(file):
            node = parseJson(readFile(file))

            this.validate(node)
        else:
            this.data.sources["nim-lang"] = Source.init("gh://nim-lang/packages")

        if fileExists(index):
            this.index = parseJson(readFile(index)).to(OrderedTable[string, string])

    method save*(file: string = percy.name & ".json"): void {. base .} =
        writeFile(file, pretty(%this.data))

    method index*(): void {. base .} =
        var
            aliases = initOrderedTable[string, string]()
            resolved: OrderedTable[string, string]

        for name, source in this.data.sources:
            let
                content = source.repository.read("packages.json")
            if content.len:
                let
                    packages = parseJson(content)
                if packages.kind == JArray:
                    if  resolved.len == 0:
                         resolved = initOrderedTable[string, string](packages.len)

                    for package in getElems(packages):
                        let
                            name = getStr(package["name"])

                        if aliases.hasKey(name):
                            aliases.del(name)
                        if resolved.hasKey(name):
                            resolved.del(name)

                        if package.hasKey("alias"):
                            aliases[name] = getStr(package["alias"])
                        else:
                            resolved[name] = Repository.qualifyUrl(getStr(package["url"]))

        for name, package in this.data.packages:
             resolved[name] = package.repository.url

        var
            pairs = newSeq[(string, string)](aliases.len + resolved.len)

        while aliases.len > 0:
            var
                remove = newSeq[string]()
            for alias, name in aliases:
                if resolved.hasKey(name):
                    pairs.add((alias, resolved[name]))
                    remove.add(alias)
            if remove.len == 0:
                raise newException(ValueError, "Unresolvable aliases found")
            for alias in remove:
                aliases.del(alias)

        for name, value in resolved:
            pairs.add((name, value))

        this.index = pairs.reversed().toOrderedTable()

        writeFile(percy.target / percy.index, $(%(this.index)))


    method prepare*(): void {. base .} =
        var
            updated = false

        if not dirExists(percy.target):
            createDir(percy.target)

        for name, source in this.data.sources:
            case source.repository.clone():
                of RCloneCreated:
                    updated = true
                of RCloneExists:
                    case source.repository.update():
                        of RUpdated:
                            updated = true
                        else:
                            discard
        if updated or not fileExists(percy.target / percy.index):
            this.index()

        for name, package in this.data.packages:
            if package.repository.clone() == RCloneExists:
                discard package.repository.update()

shape Settings: @[
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                result.load()

                let
                    cacheDir = percy.getAppCacheDir()

                if not dirExists(cacheDir):
                    createDir(cacheDir)
        )
    )
]