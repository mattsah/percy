import
    percy,
    std/uri,
    std/hashes,
    lib/source,
    lib/package,
    lib/repository

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
    method init*(): void {. base .} =
        discard

    method hasName*(url: string): bool {. base .} =
        result = false
        for name, value in this.index:
            if url == value:
                result = true
                break

    method getWorkDir*(url: string): string {. base .} =
        result = parseUri(url).path.strip(chars = {'/'}).toLower() # default to lowercased path
        for name, value in this.index:
            if url == value:
                if name.contains('/'):
                    result = name
                else:
                    result = "+global" / name
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

    method validatePackages*(node: JsonNode): void {. base .} =
        if node.kind != JObject:
            raise newException(ValueError, "`packages` must be an object.")
        for key, value in node:
            try:
                Package.validateName(key)
            except:
                raise newException(
                    ValueError,
                    fmt "package @ '{key}' contains an invalid name: {getCurrentExceptionMsg()}."
                )

            try:
                if value.kind != JString:
                    raise newException(ValueError, "must be a string")
                Repository.validateUrl(getStr(value))
            except:
                raise newException(
                    ValueError,
                    fmt "package @ '{key}' contains an invalid value: {getCurrentExceptionMsg()}."
                )

    method validateSources*(node: JsonNode): void {. base .} =
        if node.kind != JObject:
            raise newException(ValueError, "`sources` must be an object.")
        for key, value in node:
            try:
                Source.validateName(key)
            except:
                raise newException(
                    ValueError,
                    fmt "source @ '{key}' contains an invalid value: {getCurrentExceptionMsg()}."
                )

            try:
                if value.kind != JString:
                    raise newException(ValueError, "must be a string")
                Repository.validateUrl(getStr(value))
            except:
                raise newException(
                    ValueError,
                    fmt "source @ '{key}' contains an invalid value: {getCurrentExceptionMsg()}"
                )

    #[
        Validates meta information from a JSON config file (currently not used)
    ]#
    method validateMeta*(node: JsonNode): void {. base .} =
        if node.kind != JObject:
            raise newException(ValueError, "`meta` must be an object.")
        discard

    #[
        Save the configuration and the index.
    ]#
    method saveIndex*(): void {. base .} =
        writeFile(percy.target / "index." & this.config, pretty(%(this.index)))

    #[
        Save the configuration and the index.
    ]#
    method save*(): void {. base .} =
        writeFile(this.config, pretty(%this.data))
        this.saveIndex()

    #[
        Takes all the active sources and packages on this object and constructs an index then
        writes and index file to based on the configuraiton name.
    ]#
    method index(): void {. base .} =
        var
            aliases = initOrderedTable[string, string]()
            resolved: OrderedTable[string, string]

        if not dirExists(percy.target):
            createDir(percy.target)

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

    #[

    ]#
    method prepare*(force: bool = false): void {. base .} =
        let
            index = percy.target / "index." & this.config
            cacheDir = percy.getAppCacheDir()
        var
            refresh = force
            updated = false

        if not dirExists(cacheDir):
            createDir(cacheDir)

        for name, source in this.data.sources:
            case source.repository.clone():
                of RCloneCreated:
                    updated = true
                of RCloneExists:
                    case source.repository.update(force):
                        of RUpdated:
                            updated = true
                        else:
                            discard

        for name, package in this.data.packages:
            case package.repository.clone():
                of RCloneCreated:
                    updated = true
                of RCloneExists:
                    case package.repository.update(force):
                        of RUpdated:
                            updated = true
                        else:
                            discard

        #
        # Determine if we need to re-index and refresh.  There are a handful of conditions for
        # when this can occur.
        #
        if fileExists(this.config):
            if not fileExists(index):
                refresh = true
            elif getLastModificationTime(this.config) > getLastModificationTime(index):
                refresh = true
            else:
                discard

        if refresh or updated:
            this.index()
            this.saveIndex()

        if fileExists(index):
            this.index = parseJson(readFile(index)).to(OrderedTable[string, string])

    #[
        Validates a JSON configuration and builds the internal settings data from that
        configuration.  This is used internally by load().
    ]#
    method build(node: JsonNode): void {. base .} =
        try:
            if node.kind != JObject:
                raise newException(ValueError, "must be an object.")
            for key, value in node:
                case key:
                    of "meta":
                        this.validateMeta(value)
                        this.data.meta = value

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
                        raise newException(ValueError, fmt "unknown configuration key `{key}`")

        except ValueError:
            raise newException(
                ValueError,
                (fmt "Invalid {percy.name}.json, ") & getCurrentExceptionMsg()
            )

    #[
        Loads a configuration
    ]#
    method load(config: string = percy.name & ".json"): void {. base .} =
        var
            node: JsonNode

        this.config = config

        #[
            If the file exists load it and build our source/package data from it.
        ]#
        if fileExists(this.config):
            node = parseJson(readFile(this.config))
            this.build(node)

        #[
            If no file existed, we don't have any source/package data, but we'll run prepare
            in the event we do, which will check that our config files are at least created,
            as well as our vendor dir and, if we did have source/package data, will clone and
            update those repositories if necessary.
        ]#
        this.prepare()


    #[
        Loads a configuration and returns a Settings object
    ]#
    proc open*(config: string = percy.name & ".json"): Settings {. static .} =
        result = self.init()
        result.load(config)

