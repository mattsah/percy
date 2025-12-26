import
    percy,
    lib/settings,
    lib/depgraph,
    lib/repository,
    pkg/checksums/sha1

type
    MappingException* = ref object of CatchableError

    Loader* = ref object of Class
        quiet: bool
        settings: Settings
        map: JsonNode


begin Loader:
    method init*(settings: Settings, quiet: bool = true): void {. base .} =
        this.quiet = quiet
        this.settings = settings

    method openMapFile(): void {. base .} =
        let
            mapFile = fmt "{percy.name}.map"
        if fileExists(mapFile):
            this.map = json.parseFile(mapFile)
        else:
            this.map = newJObject()

    method writeMapFile(map: JsonNode): void {. base .} =
        let
            mapFile = fmt "{percy.name}.map"
        writeFile(mapFile, pretty(this.map))

    method getMappedPaths(targetDir: string): Table[string, string] {. base .} =
        let
            percyFile = targetDir / fmt "{percy.name}.json"
        var
            localMeta: JsonNode
            targetMeta: JsonNode

        result = initTable[string, string]()

        if fileExists(percyFile):
            try:
                localMeta = this.settings.data.meta
                targetMeta = json.parseFile(percyFile)["meta"]
                this.settings.validateMeta(targetMeta)
            except:
                discard

            if localMeta.hasKey("map") and targetMeta.hasKey("maps"):
                let
                    localMap = localMeta["map"].getStr()
                if targetMeta["maps"].hasKey(localMap):
                    let
                        mapDir = targetDir / targetMeta["maps"][localMap].getStr()

                    if dirExists(mapDir):
                        for relPath in walkDirRec(mapDir, relative = true):
                            result[mapDir / relPath] = relPath

    method resolveMappedFile(repository: Repository, mapPath: string, relPath: string): string {. base .} =
        let
            currentHash = $secureHashFile(relPath)
            newHash = $secureHashFile(mapPath)
        var
            status: int
            answer: string
            knownHash: string
            resolve = false

        if this.map.hasKey(relPath):
            knownHash = $(this.map[relPath]["hash"])

        if currentHash == newHash: # existing version is already installed, no need to copy
            result = currentHash
        elif currentHash == knownHash: # the file has not changed
            let
                subs = this.map[relPath]["subs"]
            if subs.len == 1 and subs.contains(%repository.hash): # the file is ours
                copyFile(mapPath, relPath, {cfSymlinkFollow})
                result = newHash
            else: # the file belongs to someone else or multiple... check
                resolve = true
        else: # the file has changed
            resolve = true

        if resolve:
            while true:
                print fmt "A Package Wants To Update a File"
                print fmt "> New File: {mapPath}"
                print fmt "> Existing File: {relPath}"
                print fmt "> Do you want to install the new version? (y/n/[D]iff): ", 0
                answer = stdin.readLine()

            case answer.toLower():
                of "n":
                    result = knownHash
                of "y":
                    result = newHash
                    copyFile(mapPath, relPath, {cfSymlinkFollow})
                of "d":
                    status = execCmd(fmt "git diff --no-index {relPath} {mapPath}")
                    discard
                else:
                    fail fmt "Invalid Answer"

    method removeMappedPaths(repository: Repository): void {. base .} =
        discard

    method updateMappedPaths(repository: Repository, targetDir: string): void {. base .} =
        discard

    method createMappedPaths(repository: Repository, targetDir: string): void {. base .} =
        for mapPath, relPath in this.getMappedPaths(targetDir):
            var
                hash: string

            if dirExists(mapPath):
                if fileExists(relPath):
                    raise MappingException(
                        msg: fmt "could not map directory {relPath} from {mapPath}, file exists"
                    )
                if not dirExists(relPath):
                    createDir(relPath)

            if fileExists(mapPath):
                if dirExists(relPath):
                    raise MappingException(
                        msg: fmt "could not map file {relPath} from {mapPath}, directory exists"
                    )
                if not fileExists(relPath):
                    copyFile(mapPath, relPath)
                    hash = $secureHashFile(relPath)
                else:
                    hash = this.resolveMappedFile(repository, mapPath, relPath)

            if not this.map.hasKey(relPath):
                this.map[relPath] = %(
                    hash: hash,
                    subs: @[
                        repository.hash
                    ]
                )
            else:
                this.map[relPath]["hash"] = %hash
                this.map[relPath]["subs"].add(%repository.hash)

    method loadSolution*(solution: Solution, force: bool = false): seq[Checkout] {. base .} =
        var
            error: int
            output: string
            pathList: seq[string]
            retainDirs: HashSet[string]
            deleteDirs: OrderedSet[string]
            updateDirs: OrderedSet[string]
            createDirs: OrderedSet[string]
            workTrees: Table[string, WorkTree]

        if not this.quiet:
            print "Loading Solution"

        #
        # Loop through all of our workDirs based commits in the solution and the corresponding
        # work tree.  Mark directories depending on their state, we can either:
        # - retain
        # - create
        # - update
        #
        # Deletes are handled after this as we want to cleanup directories no longer being used.
        #
        for commit in solution:
            let
                targetDir = vendorDir / this.settings.getWorkDir(commit.repository.url)
                workTrees = commit.repository.workTrees
                currentUrl = commit.repository.url

            if not workTrees.hasKey(targetDir):
                if dirExists(targetDir) and not force:
                    info fmt "> Skip: '{targetDir}': non-worktree of {currentUrl} (force with -f)"
                    retainDirs.incl(targetDir)
                else:
                    createDirs.incl(targetDir)
            else:
                let
                    branch = workTrees[targetDir].branch
                    head = workTrees[targetDir].head

                if head == commit.id: # We can just retain the current state if it matches
                    retainDirs.incl(targetDir)
                else: # If it doesn't match we want to check if there's a branch checked out
                    if branch.len != 0 and not force: # Someone may be working on something
                        info fmt "> Skip: '{targetDir}': using branch `{branch}` (force with -f)"
                        retainDirs.incl(targetDir)
                    else:
                        updateDirs.incl(targetDir)

        proc scanDeletes(dir: string): void =
            var
                delCount = 0
                subCount = 0
            for item in walkDir(dir):
                inc subCount
                if not dirExists(item.path): # We're only looking for directories
                    continue
                if symLinkExists(item.path): # Enable people to link to work on things
                    continue
                if retainDirs.contains(item.path):
                    continue
                if percy.hasFile(item.path):
                    if dirExists(item.path / ".git"): # Check if this is a git directory
                        percy.execIn(
                            ExecHook as (
                                block:
                                    error = percy.execCmdCapture(output, @[
                                        fmt "git status --porcelain"
                                    ])
                            ),
                            item.path
                        )

                        if error == 0 and output.len > 0 and not force:
                            info fmt "> Skip: '{item.path}': has unsaved changes (force with -f)"
                            if updateDirs.contains(item.path):
                                updateDirs.excl(item.path)

                    if not updateDirs.contains(item.path):
                        deleteDirs.incl(item.path)
                        inc delCount
                else:
                    scanDeletes(item.path)
            if subCount == delCount:
                deleteDirs.incl(dir)

        scanDeletes(vendorDir)

        #
        # Report changes
        #

        deleteDirs = deleteDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        updateDirs = updateDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        createDirs = createDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()

        let # optimized
            hasDeleteDirs = deleteDirs.len > 0
            hasUpdateDirs = updateDirs.len > 0
            hasCreateDirs = createDirs.len > 0

        if not this.quiet:
            if hasDeleteDirs or hasUpdateDirs or hasCreateDirs:
                print fmt "> Solution: Changes Required"
                if hasDeleteDirs:
                    print fmt "> Delete:"
                    for dir in deleteDirs:
                        print fmt ">    {dir}"
                if hasUpdateDirs:
                    print fmt ">  Update:"
                    for dir in updateDirs:
                        print fmt ">    {dir}"
                if hasCreateDirs:
                    print fmt ">  Create:"
                    for dir in createDirs:
                        print fmt ">    {dir}"
            else:
                print fmt "> Solution: There Are No Applicable Changes"

        #
        # Perform loading
        #

        this.openMapFile()

        for dir in deleteDirs:
            percy.execIn(
                ExecHook as (
                    block:
                        error = percy.execCmdCapture(output, @[
                            fmt "git remote get-url origin"
                        ])
                )
            )

            if error == 0:
                let
                    repository = this.settings.getRepository(output.strip())

                this.removeMappedPaths(repository)

            removeDir(dir)

        for commit in solution:
            let
                workDir = this.settings.getWorkDir(commit.repository.url)
                targetDir = vendorDir / workDir
                commitHash = commit.id

            if updateDirs.contains(targetDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmd(@[
                                fmt "git checkout -q --detach {commitHash}"
                            ])
                    ),
                    workDir
                )

                this.updateMappedPaths(commit.repository, targetDir)

            elif createDirs.contains(targetDir):
                error = commit.repository.exec(@[
                    fmt "git worktree add -d {targetDir} {commitHash}"
                ], output)

                this.createMappedPaths(commit.repository, targetDir)

            else:
                discard

            if commit.info.srcDir.len > 0: # optimized
                pathList.add(fmt "{percy.target / workDir / commit.info.srcDir}")
            else:
                pathList.add(fmt "{percy.target / workDir}")

        writeFile(fmt "vendor/{percy.name}.paths", pathList.join("\n"))
