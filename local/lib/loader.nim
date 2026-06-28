import
    percy,
    lib/vcs,
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
            deleteDirs: OrderedSet[string]
            updateDirs: OrderedSet[string]
            createDirs: OrderedSet[string]
            targetCommits: Table[string, Commit]

        if not this.quiet:
            print "Loading Solution"

        proc hasFile(path: string): bool =
            result = false
            for item in walkDir(path):
                if fileExists(item.path):
                    return true

        proc scanChanges(dir: string, depth: int = 0): void =
            var
                delCount = 0
                subCount = 0

            for item in walkDir(dir):
                var
                    isControlled = false
                    currentCommit = ""
                    currentChanges = ""
                    commonDirectory = ""

                inc subCount

                #
                # We're only looking for directories
                #
                if not dirExists(item.path):
                    continue

                #
                # At this point, we know the item is a directory and is not being retained.
                # If it contains no files, we can recursively scan it and continue.
                #
                if not hasFile(item.path):
                    scanChanges(item.path, depth + 1)
                    continue

                #
                # We don't want to touch people's links
                #
                if not force and symLinkExists(item.path):
                    info fmt "> Skipped changes to '{item.path}'"
                    info fmt "> Reason: Linked dependency (force with -f)"
                    continue

                #
                # VCS Information
                #
                isControlled = vcs.controlled(item.path)

                if isControlled:
                    currentCommit = vcs.currentHead(item.path)
                    currentChanges = vcs.currentChanges(item.path)
                    commonDirectory = vcs.commonDirectory(item.path)

                    if not force and currentChanges.len > 0: # Skip if it has changes.
                        info fmt "> Skipped changes to '{item.path}'"
                        info fmt "> Reason: Unsaved changes (force with -f)"
                        continue

                    if not force and commonDirectory == item.path / ".git": # Skip non-worktrees.
                        info fmt "> Skipped changes to '{item.path}'"
                        info fmt "> Reason: Invalid worktree (force with -f)"
                        continue

                    if targetCommits.hasKey(item.path):
                        if commonDirectory != targetCommits[item.path].repository.cacheDir:
                            deleteDirs.incl(item.path) # Delete and...
                            createDirs.incl(item.path) # Recreate
                            continue
                        else:
                            if currentCommit != targetCommits[item.path].id:
                                updateDirs.incl(item.path) # Add to updates if commit differs
                            continue

                elif not force:
                    info fmt "> Skipped changes to '{item.path}'"
                    info fmt "> Reason: Uncontrolled directory (force with -f)"
                    continue

                else:
                    discard

                #
                # Delete all remnants not needing to be created
                #
                deleteDirs.incl(item.path)
                inc delCount

            if subCount == delCount and depth > 0:
                deleteDirs.incl(dir)

        #
        # Loop through all commits in our solution:
        #   - Add their source paths to the export pathList
        #   - Add their target directories to create dirs for now [scanChanges() will modify]
        #
        for commit in solution:
            let
                workDir = this.settings.getWorkDir(commit.repository.url)
                targetDir = getVendorDir(workDir)

            targetCommits[targetDir] = commit

            if not dirExists(targetDir):
                createDirs.incl(targetDir)

            if commit.info.srcDir.len > 0:
                pathList.add(fmt "{percy.target / workDir / commit.info.srcDir}")
            else:
                pathList.add(fmt "{percy.target / workDir}")

        scanChanges(getVendorDir())

        #
        # Report changes
        #

        deleteDirs = deleteDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        updateDirs = updateDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        createDirs = createDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()

        if not this.quiet:
            if deleteDirs.len + updateDirs.len + createDirs.len > 0:
                print fmt "> Solution: Changes Required"
                if deleteDirs.len > 0:
                    print fmt ">   Delete:"
                    for dir in deleteDirs:
                        print fmt ">     {dir}"
                if updateDirs.len > 0:
                    print fmt ">   Update:"
                    for dir in updateDirs:
                        print fmt ">     {dir}"
                if createDirs.len > 0:
                    print fmt ">   Create:"
                    for dir in createDirs:
                        print fmt ">     {dir}"
            else:
                print fmt "> Solution: There Are No Applicable Changes"

        #
        # Perform loading
        #

        if not preserve:
            this.openMapFile()

        block:

            #
            # DELETES
            #
            for deleteDir in deleteDirs:
                let
                    repository = this.settings.getRepository(vcs.origin(deleteDir))

                if repository.cacheExists:
                    if not preserve:
                        this.removeMappedPaths(repository, deleteDir, true)

                    discard repository.exec(
                        @[
                            fmt "git worktree remove {deleteDir}"
                        ],
                        output
                    )

                removeDir(deleteDir)

            #
            # UPDATES
            #
            for updateDir in updateDirs:
                let
                    commit = targetCommits[updateDir]
                    repository = this.settings.getRepository(vcs.origin(updateDir))

                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmdCapture(output, @[
                                fmt "git checkout -q --detach {commit.id}"
                            ])
                    ),
                    updateDir
                )

                if not preserve:
                    this.removeMappedPaths(repository, updateDir)
                    this.createMappedPaths(commit.repository, updateDir)

                result.add(Checkout(
                    commit: commit,
                    path: updateDir
                ))

            #
            # CREATES
            #
            for createDir in createDirs:
                let
                    commit = targetCommits[createDir]

                error = commit.repository.exec(
                    @[
                        fmt "git worktree add -df {createDir} {commit.id}"
                    ],
                    output
                )

                if not preserve:
                    this.createMappedPaths(commit.repository, createDir)

                result.add(Checkout(
                    commit: commit,
                    path: createDir
                ))

        if not preserve:
            this.writeMapFile()

        for checkout in result:
            percy.execIn(
                ExecHook as (
                    block:
                        if fileExists(".gitmodules"):
                            error = percy.execCmdCapture(output, @[
                                fmt "git submodule update --init --recursive"
                            ])
                ),
                checkout.path
            )

        writeFile(fmt "vendor/{percy.name}.paths", pathList.join("\n"))
