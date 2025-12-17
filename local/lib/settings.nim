import
    percy,
    std/uri,
    std/hashes,
    lib/source,
    lib/package,
    lib/repository,
    mininim/dic

export
    source,
    package,
    repository

type
    SettingsData = object
        meta* = newJObject()
        sources* = initOrderedTable[string, Source]()
        packages* = initOrderedTable[string, Package]()

    Settings* = ref object of Class
        data* = SettingsData()
        cache* = initTable[string, Repository]()
        index*: OrderedTable[string, string]
        config*: string

begin Settings:
    method getName*(url: string): string {. base .} =
        result = parseUri(url).path.strip("/")
        for name, value in this.index:
            if url == value:
                result = name
                break;

    method getRepository*(reference: string): Repository {. base .} =
        var
            instance: Repository
        if this.index.hasKey(reference):
            instance = Repository.init(this.index[reference])
        else:
            instance = Repository.init(reference)

        if not this.cache.hasKey(instance.shaHash):
            this.cache[instance.shaHash] = instance

        result = this.cache[instance.shaHash]

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

    method validateMeta(node: JsonNode): void {. base .} =
        discard

    method build(node: JsonNode): void {. base .} =
        try:
            if node.kind != JObject:
                raise newException(ValueError, "must contain an object.")
            for key, value in node:
                case key:
                    of "meta":
                        this.validateMeta(value)

                    of "sources":
                        this.validateSources(value)
                        for name, url in value:
                            this.data.sources[name] = Source.init(
                                this.getRepository(getStr(url))
                            )

                    of "packages":
                        this.validatePackages(value)
                        for name, url in value:
                            this.data.packages[name] = Package.init(
                                this.getRepository(getStr(url))
                            )

                    else:
                        raise newException(ValueError, fmt "unknown configuration key '{key}'")

        except ValueError:
            raise newException(
                ValueError,
                (fmt "Invalid {percy.name}.json, ") & getCurrentExceptionMsg()
            )

    method load*(config: string = percy.name & ".json"): void {. base .} =
        var
            node: JsonNode
        let
            index = percy.target / "index." & config

        this.config = config

        if fileExists(this.config):
            node = parseJson(readFile(this.config))

            this.build(node)

        if fileExists(index):
            this.index = parseJson(readFile(index)).to(OrderedTable[string, string])

    method open*(config: string = percy.name & ".json"): Settings {. base .} =
        this.load(config)
        result = this

    method save*(): void {. base .} =
        writeFile(this.config, pretty(%this.data))

    method index*(): void {. base .} =
        var
            aliases = initOrderedTable[string, string]()
            resolved: OrderedTable[string, string]

        for name, source in this.data.sources:
            let
                content = source.repository.readFile("packages.json")
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

        writeFile(percy.target / "index." & this.config, $(%(this.index)))


    method prepare*(reindex: bool = false): void {. base .} =
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
        if reindex:
            removeFile(percy.target / "index." & this.config)

        if updated or not fileExists(percy.target / "index." & this.config):
            this.index()

        for name, package in this.data.packages:
            if package.repository.clone() == RCloneExists:
                discard package.repository.update()

shape Settings: @[
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                let
                    cacheDir = percy.getAppCacheDir()

                if not dirExists(cacheDir):
                    createDir(cacheDir)
        )
    )
]
