import
    percy,
    semver,
    std/re,
    std/uri,
    std/paths,
    std/hashes,
    checksums/sha1

type
    RCloneStatus* = enum
        RCloneExists
        RCloneCreated

    RUpdateStatus* = enum
        RUpdateCloned
        RUpdateSkip
        RUpdateNone
        RUpdated

    Repository* = ref object of Class
        hash: Hash
        stale: bool
        shaHash: string
        cacheDir: string
        original: string
        url: string

    Commit* = ref object of Class
        id*: string
        version*: Version
        repository*: Repository
        info*: NimbleFileInfo

    WorkTree* = ref object of Class
        repository*: Repository
        branch*: string
        head*: string
        path*: string

    Checkout* = ref object of Class
        repository*: Repository
        commit*: Commit
        path*: string

begin Commit:
    proc `$`*(): string =
        result = fmt "{this.id} {$this.version}"

    proc hash*(): Hash =
        result = hash(this.id)

begin Repository:
    proc hash*(): Hash =
        result = this.hash

    proc validateUrl*(url: string): void {. static .} =
        if url.startsWith($paths.getCurrentDir()):
            raise newException(
                ValueError,
                fmt "repository at '{url}' should not be in your working directory"
            )

    proc qualifyUrl*(url: string): string {. static .} =
        var
            uri = parseUri(url)

        if uri.scheme.len == 0: # optimized
            if dirExists(uri.path / ".git"):
                uri.path = $absolutePath(Path uri.path)
            elif uri.path.match(re"^.+\@.+\:.+$"):
                var
                    parts = uri.path.split(':')
                    uhost = parts[0].split('@')

                uri.path = parts[1]
                uri.scheme = "git+ssh"
                uri.username = uhost[0]
                uri.hostname = uhost[1]
        else:
            if uri.scheme notin ["http", "https", "git+ssh"]:
                case uri.scheme:
                    of "gh", "github":
                        uri.path = uri.hostname & uri.path
                        uri.hostname = "github.com"
                    of "gl", "gitlab":
                        uri.path = uri.hostname & uri.path
                        uri.hostname = "github.com"
                    of "cb", "codeberg":
                        uri.path = uri.hostname & uri.path
                        uri.hostname = "codeberg.org"
                    else:
                        raise newException(ValueError, fmt "invalid scheme {uri.scheme}")
                uri.scheme = "https"

        if uri.scheme.len > 0: # optimized
            if uri.path.endsWith(".git"):
                uri.path = uri.path[0..^5]
        else:
            uri.path = absolutePath($uri)

        if uri.anchor.len > 0:
            uri.anchor = ""

        result = strip($uri, leading = false, chars = {'/'})

    method init*(url: string): void {. base .} =
        this.url = self.qualifyUrl(url)
        this.hash = hash(toLower(this.url))
        this.shaHash = toLower($secureHash(this.url))
        this.cacheDir = percy.getAppCacheDir(this.shaHash)
        this.original = url

        let
            head = this.cacheDir / "FETCH_HEAD"
        if fileExists(head):
            this.stale = getTime() > getLastModificationTime(head) + 60.minutes
        else:
            this.stale = true

    method url*(): string {. base .} =
        result = this.url

    method original*(): string {. base .} =
        result = this.original

    method shaHash*(): string {. base .} =
        result = this.shaHash

    method cacheDir*(): string {. base .} =
        result = this.cacheDir

    method cacheExists*(): bool {. base .} =
        result = dirExists(this.cacheDir)

    method exists*(): bool {. base .} =
        var
            status: int
            output: string

        result = false

        if this.cacheExists:
            result = true
        else:
            try:
                if this.stale:
                    status = percy.execCmdCapture(output, @[
                        fmt "git ls-remote '{this.url}' 'null'"
                    ])

                    if status == 0:
                        result = true
            except:
                discard

    method exec*(cmdParts: seq[string], output: var string): int {. base .} =
        var
            error: int
            wrappedOutput: string

        if not this.cacheExists:
            raise newException(ValueError, fmt "cannot exec commands in {this.url}, no local cache")

        percy.execIn(
            ExecHook as (
                block:
                    error = percy.execCmdCapture(wrappedOutput, @[cmdParts.join(" ")])
            ),
            this.cacheDir
        )

        result = error
        output = wrappedOutput

    method fetch*(): bool {. base .} =
        var
            status: int
            output: string
        status = this.exec(
            @[
                fmt "git fetch origin -f --prune",
                fmt "'+refs/tags/*:refs/{percy.name}/*'",
                fmt "'+refs/heads/*:refs/{percy.name}/*'",
                fmt "'HEAD'"
            ],
            output
        )

        if status != 0 or not fileExists(this.cacheDir / "FETCH_HEAD"): # optimized
            raise newException(ValueError, fmt "failed fetching from {this.url}: {output}")

        result = output.len > 0

    method clone*(): RCloneStatus {. base .} =
        var
            error: int

        if this.cacheExists:
            result = RCloneExists
        else:
            print fmt "Downloading {this.url} into central caching"

            error = percy.execCmd(@[
                fmt "git clone --bare {this.url} {this.cacheDir}"
            ])

            if not error:
                result = RCloneCreated
            else:
                raise newException(ValueError, fmt "failed cloning {this.url}")

            discard this.fetch()

    method update*(force: bool = false): RUpdateStatus {. base .} =
        result = RUpdateSkip

        if force or this.stale:
            if not this.cacheExists:
                discard this.clone()
                result = RUpdateCloned

            when defined debug:
                print fmt "Getting updates available in {this.url}"

            if not this.fetch():
                result = RUpdateNone
            else:
                result = RUpdated

            setLastModificationTime(this.cacheDir / "FETCH_HEAD", getTime())
            this.stale = false

    method head*(): string {. base .} =
        for line in readFile(this.cacheDir / "FETCH_HEAD").split("\n"):
            if line.toLower().split("\t\t")[1].startsWith(this.url.strip(chars = {'/'}).toLower()):
                result = line[0..39]
                break
        if not result:
            raise newException(ValueError, fmt "could not determine head on {this.url}")

    method commits*(newest: bool = false): OrderedSet[Commit] {. base .} =
        const
            tag  = "%(refname:short)"
            hash = "%(if:equals=tag)%(objecttype)%(then)%(*objectname)%(else)%(objectname)%(end)"
        let
            prefix = fmt "{percy.name}/"
        var
            status: int
            output: string
            head: string

        discard this.update(newest)

        status = this.exec(
            @[
                fmt "git for-each-ref --omit-empty --format='{tag} {hash}'",
                fmt "'refs/{percy.name}/?*[0-9]*.*'",
                fmt "'refs/{percy.name}/*'"
            ],
            output
        )

        if status != 0:
            raise newException(ValueError, fmt "failed aggregating commits on {this.url}")

        output = fmt "HEAD {this.head}\n{output}"

        for reference in output.split('\n'):
            let
                parts = reference.split(' ', 1)
            var
                version: Version
            if parts.len == 2:
                try:
                    if parts[0] == "HEAD":
                        version = v("0.0.0-HEAD")
                    elif parts[0].match(re".*[0-9]+\.[0-9]+.*"):
                        version = v(parts[0].replace(re"^[^0-9]*", ""))
                    else:
                        version = v(
                                "0.0.0-branch." & (
                                    parts[0][prefix.len..^1].replace(re"[!@#$%^&*+_.,/]", "-")
                                )
                            )

                    result.incl(Commit(
                        id: parts[1],
                        repository: this,
                        version: version
                    ))

                except:
                    raise newException(
                        ValueError,
                        fmt "Failed loading reference '{reference}': {getCurrentExceptionMsg()}"
                    )

    method worktrees*(): Table[string, WorkTree] {. base .} =
        var
            status: int
            worktrees: string

        status = this.exec(
            @[
                fmt "git worktree prune"
            ],
            worktrees
        )
        if status != 0: # optimized
            raise newException(ValueError, "Could not prune worktree list")

        status = this.exec(
            @[
                fmt "git worktree list --porcelain"
            ],
            worktrees
        )
        if status != 0: # optimized
            raise newException(ValueError, "Could not get worktree list")

        for worktree in worktrees.strip().split("\n\n"):
            let
                lines = worktree.split('\n')
            var
                branch: string = ""
                head: string = ""
                path: string = ""

            if lines[1] == "bare":
                continue
            if not lines[0].startsWith("worktree "):
                continue

            path = lines[0].split(' ')[1]

            for line in lines:
                if line.startsWith("HEAD "):
                    head = line.split(' ')[1]
                elif line.startsWith("branch"):
                    branch = line.split(' ')[1].replace("refs/heads/", "")

            if path.len > 0 and head.len > 0: # optimized
                result[path] = WorkTree(
                    repository: this,
                    branch: branch,
                    head: head,
                    path: path
                )

    method listDir*(path: string, reference: string = ""): seq[string] {. base .} =
        var
            error: int
            output: string
            commit: string

        if not reference:
            commit = this.head
        else:
            commit = reference

        error = this.exec(
            @[
                fmt "git ls-tree --name-only {commit} --name-only :{path}"
            ],
            output
        )

        if error:
            raise newException(
                ValueError,
                fmt "failed to list directory {commit}:{path} on {this.url}"
            )

        result = output.strip().split('\n')

    method readFile*(path: string, reference: string = ""): string {. base .} =
        var
            error: int
            output: string
            commit: string

        if not reference:
            commit = this.head
        else:
            commit = reference

        let
            file = commit & ":" & path.strip("/")

        when debugging(2):
            print fmt "Reading file {file} @ {this.url}"

        error = this.exec(
            @[
                fmt "git show {file}"
            ],
            output
        )

        if error:
            raise newException(
                ValueError,
                fmt "failed to read file {commit}:{path} on {this.url}"
            )

        result = output