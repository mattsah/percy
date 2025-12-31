import
    percy,
    semver,
    lib/settings,
    lib/depgraph,
    lib/repository

type
    LockFile* = ref object of Class
        file: string
        data: Solution

    LockItemGraph* = ref object of Class
        directory*: string
        dependents*: OrderedSet[Commit]
        dependencies*: OrderedSet[Commit]

    LockItemGraphs* = OrderedTable[Commit, LockItemGraph]

begin Commit:
    proc fromLockFile*(node: JsonNode): Commit {. static .} =
        result = Commit(
            id: node["id"].getStr(),
            version: node["version"].to(Version),
            repository: Repository.init(node["repository"].getStr()),
            info: node["info"].to(NimbleFileInfo)
        )

    method toLockFile*(): JsonNode {. base .} =
        result = newJObject()
        result["id"] = %(this.id)
        result["info"] = %(this.info)
        result["version"] = %(this.version)
        result["repository"] = %(this.repository.url)


begin LockFile:
    #[

    ]#
    method exists*(): bool {. base .} =
        result = fileExists(this.file)

    #[

    ]#
    method len*(): int {. base .} =
        result = this.data.len

    #[

    ]#
    method `%`*(): JsonNode {. base .} =
        result = newJArray()

        for commit in this.data:
            result.add(commit.toLockFile())

    #[

    ]#
    method content*(): string {. base .} =
        result = pretty(%this)

    #[

    ]#
    method commits*(): seq[Commit] {. base .} =
        result = this.data

    #[

    ]#
    method solution*(): Solution {. base .} =
        for commit in this.data:
            if not commit.repository.cacheExists:
                discard commit.repository.clone()
                continue
            if isNone(commit.repository.getCommit(commit.id)):
                discard commit.repository.update(force = true)
                continue

        result = this.data

    #[

    ]#
    method graph*(graph: DepGraph, settings: Settings): LockItemGraphs {. base .} =
        var
            itemGraphs: LockItemGraphs

        proc resolveCommit(commit: Commit): void =
            if not itemGraphs.hasKey(commit):
                itemGraphs[commit] = LockItemGraph(
                    directory: settings.getWorkDir(commit.repository.url)
                )

            for requirements in commit.info.requires:
                for requirement in requirements:
                    let
                        requirement = graph.parseRequirement(requirement)
                    for dependency in this.data:
                        if dependency.repository.url != requirement.repository.url:
                            continue
                        if itemGraphs[commit].dependencies.contains(dependency):
                            continue

                        itemGraphs[commit].dependencies.incl(dependency)
                        resolveCommit(dependency)

                        for subDependency in itemGraphs[dependency].dependencies:
                            itemGraphs[commit].dependencies.incl(subDependency)

        for commit in this.data:
            resolveCommit(commit)

            for dependency in itemGraphs[commit].dependencies:
                itemGraphs[dependency].dependents.incl(commit)

            itemGraphs[commit].dependencies = itemGraphs[commit].dependencies
                .toSeq()
                .sortedByIt(itemGraphs[it].directory)
                .toOrderedSet()

            itemGraphs[commit].dependents = itemGraphs[commit].dependents
                .toSeq()
                .sortedByIt(itemGraphs[it].directory)
                .toOrderedSet()

        itemGraphs.sort(
            proc (x, y: (Commit, LockItemGraph)): int =
                result = cmp(x[1].directory, y[1].directory)
        )

        return itemGraphs

    #[

    ]#
    method openFile*(path: string): void {. base .} =
        var
            data: JsonNode

        this.file = absolutePath(path)
        this.data = newSeq[Commit]()

        if fileExists(this.file):
            data = parseFile(path)

            if data.kind != JArray:
                raise newException(
                    ValueError,
                    fmt "must contain an array"
                )

            for item in data:
                this.data.add(Commit.fromLockFile(item))

    #[

    ]#
    method writeFile*(): void {. base .} =
        writeFile(this.file, this.content)

    #[
        Save solver results
    ]#
    method save*(results: SolverResults): void {. base .} =
        this.data = results.solution.get()
        this.writeFile()

    #[
        Save a solution
    ]#
    method save*(solution: Solution): void {. base .} =
        this.data = solution
        this.writeFile()

    #[

    ]#
    method init*(path: string = ""): void {. base .} =
        if path != "":
            try:
                this.openFile(path)
            except Exception as e:
                raise newException(
                    ValueError,
                    fmt "invalid lockfile '{this.file}', {e.msg}"
                )
