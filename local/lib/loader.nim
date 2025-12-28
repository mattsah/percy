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

const
    allYields = {pcFile, pcDir, pcLinkToDir, pcLinkToFile}
    allFollows = {pcDir, pcLinkToDir}


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

    method writeMapFile(): void {. base .} =
        let
            mapFile = fmt "{percy.name}.map"
        var
            toRemove: seq[string]

        for relPath, map in this.map:
            if map["subs"].len == 0:
                toRemove.add(relPath)

                if fileExists(relPath):
                    removeFile(relPath)
                elif dirExists(relPath):
                    removeDir(relPath)
                else:
                    discard
            else:
                if map["subs"] == %["main"]:
                    toRemove.add(relPath)

        for relPath in toRemove:
            this.map.delete(relPath)

        if this.map.len:
            writeFile(mapFile, pretty(this.map))
        else:
            if fileExists(mapFile):
                removeFile(mapFile)

    method getMappedPaths(targetDir: string): OrderedTable[string, string] {. base .} =
        let
            percyFile = targetDir / fmt "{percy.name}.json"
            localMeta = this.settings.data.meta
        var
            targetMeta: JsonNode

        result = initOrderedTable[string, string]()

        if fileExists(percyFile):
            try:
                targetMeta = json.parseFile(percyFile)["meta"]
                this.settings.validateMeta(targetMeta)

                if localMeta.hasKey("map") and targetMeta.hasKey("maps"):
                    let
                        localMap = localMeta["map"].getStr()
                    if targetMeta["maps"].hasKey(localMap):
                        let
                            mapDir = targetDir / targetMeta["maps"][localMap].getStr()

                        if dirExists(mapDir):
                            for relPath in walkDirRec(mapDir, allYields, allFollows, true):
                                result[relPath] = mapDir / relPath
            except:
                discard


    method resolveMappedFile(repository: Repository, mapPath: string, relPath: string): string {. base .} =
        let
            currentHash = $secureHashFile(relPath)
            newHash = $secureHashFile(mapPath)
        var
            error: int
            answer: string
            knownHash: string
            resolve = false

        if this.map.hasKey(relPath):
            knownHash = this.map[relPath]["hash"].getStr()

        if newHash == currentHash: # existing version is already installed, no need to copy
            result = currentHash
        elif newHash == knownHash: # the file has not change in the repo since the last time
            result = knownHash
        elif currentHash == knownHash: # the file has not been changed locally
            let
                subs = this.map[relPath]["subs"]
            #
            # Although we know the file has not been changed we want to ensure that either there
            # is no current other subscribers or that we are the only subscriber to make sure it
            # belongs to us or a related fork.  Otherwise, we'll want to force user resolution.
            #
            if subs.len == 0 or (subs.len == 1 and subs.contains(%repository.shaHash)):
                copyFile(mapPath, relPath, {cfSymlinkFollow})
                result = newHash
            else:
                resolve = true
        else: # the file has changed locally and we need the user to resolve
            resolve = true

        if resolve:
            while true:
                print fmt "A Package Wants To Update a File"
                print fmt "> New File: {mapPath}"
                print fmt "> Existing File: {relPath}"
                print fmt "> Do you want to install the new version? (y/n/[D]iff): ", 0
                answer = stdin.readLine().strip()

                case answer.toLower():
                    of "n":
                        result = newHash
                        break
                    of "y":
                        result = newHash
                        copyFile(mapPath, relPath, {cfSymlinkFollow})
                        break
                    of "d":
                        error = execCmd(fmt "git diff --no-index {relPath} {mapPath}")
                    else:
                        fail fmt "Invalid Answer"

    method removeMappedPaths(repository: Repository, targetDir: string, all: bool = false): void {. base .} =
        let
            mappedPaths = this.getMappedPaths(targetDir)

        for relPath, map in this.map:
            var
                newSubs = newJArray()

            if all or not mappedPaths.hasKey(relPath):
                for sub in map["subs"]:
                    if sub.getStr() == repository.shaHash:
                        continue
                    newSubs.add(sub)

                this.map[relPath]["subs"] = newSubs

    method createMappedPaths(repository: Repository, targetDir: string): void {. base .} =
        for relPath, mapPath in this.getMappedPaths(targetDir):
            var
                hash: string
                subs = @[
                    repository.shaHash
                ]

            if dirExists(mapPath):
                if fileExists(relPath):
                    raise MappingException(
                        msg: fmt "could not map directory {relPath} from {mapPath}, file exists"
                    )
                if not dirExists(relPath):
                    createDir(relPath)
                else:
                    subs.add("main")

            if fileExists(mapPath):
                if dirExists(relPath):
                    raise MappingException(
                        msg: fmt "could not map file {relPath} from {mapPath}, directory exists"
                    )
                if not fileExists(relPath):
                    copyFile(mapPath, relPath)
                    hash = $secureHashFile(relPath)
                else:
                    subs.add("main")
                    hash = this.resolveMappedFile(repository, mapPath, relPath)

            if not this.map.hasKey(relPath):
                this.map[relPath] = %(
                    hash: hash,
                    subs: subs
                )
            else:
                this.map[relPath]["hash"] = %hash
                if not this.map[relPath]["subs"].contains(%repository.shaHash):
                    this.map[relPath]["subs"].add(%repository.shaHash)

    method loadSolution*(solution: Solution, preserve: bool = false, force: bool = false): seq[Checkout] {. base .} =
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
                workDir = this.settings.getWorkDir(commit.repository.url)
                targetDir = getVendorDir(workDir)
                workTrees = commit.repository.workTrees
                currentUrl = commit.repository.url

            if not workTrees.hasKey(targetDir):
                if dirExists(targetDir) and not force:
                    info fmt "> Skipped '{targetDir}'"
                    info fmt "> Reason: Working copy is not managed as {currentUrl} (force with -f)"
                    info fmt "> Hint: Your project may have moved or your cache was cleared"
                    retainDirs.incl(targetDir)
                else:
                    createDirs.incl(targetDir)
            else:
                let
                    branch = workTrees[targetDir].branch
                    head = workTrees[targetDir].head

                if head == commit.id and not force: # We can just retain the current state if it matches
                    # info fmt "> Skipped '{targetDir}'"
                    # info fmt "> Reason: Working copy is already up to date (force with -f)"
                    retainDirs.incl(targetDir)
                elif branch.len != 0 and not force: # Someone may be working on something
                    info fmt "> Skipped '{targetDir}'"
                    info fmt "> Reason: Explicit branch `{branch}` is in use (force with -f)"
                    info fmt "> Hint: Use `git checkout -d` in the directory to release the branch"
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

        scanDeletes(getVendorDir())

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

        if not preserve:
            this.openMapFile()

        for deleteDir in deleteDirs:
            percy.execIn(
                ExecHook as (
                    block:
                        error = percy.execCmdCapture(output, @[
                            fmt "git remote get-url origin"
                        ])
                ),
                deleteDir
            )

            if error == 0:
                let
                    repository = this.settings.getRepository(output.strip())

                if not preserve:
                    this.removeMappedPaths(repository, deleteDir, true)

            removeDir(deleteDir)

        for commit in solution:
            let
                workDir = this.settings.getWorkDir(commit.repository.url)
                targetDir = getVendorDir(workDir)
                commitHash = commit.id

            if updateDirs.contains(targetDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmd(@[
                                fmt "git checkout -q --detach {commitHash}"
                            ])
                    ),
                    targetDir
                )

                if not preserve:
                    this.removeMappedPaths(commit.repository, targetDir)
                    this.createMappedPaths(commit.repository, targetDir)

            elif createDirs.contains(targetDir):
                error = commit.repository.exec(
                    @[
                        fmt "git worktree add -d {targetDir} {commitHash}"
                    ],
                    output
                )

                if not preserve:
                    this.createMappedPaths(commit.repository, targetDir)

            else:
                discard

            if commit.info.srcDir.len > 0: # optimized
                pathList.add(fmt "{percy.target / workDir / commit.info.srcDir}")
            else:
                pathList.add(fmt "{percy.target / workDir}")

        if not preserve:
            this.writeMapFile()

        writeFile(fmt "vendor/{percy.name}.paths", pathList.join("\n"))
