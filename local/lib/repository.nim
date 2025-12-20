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
        origin: string
        url: string

    Commit* = ref object of Class
        id*: string
        version*: Version
        repository*: Repository
        info*: NimbleFileInfo

    WorkTree* = ref object of Class
        repository*: Repository
        head*: string
        path*: string

    Checkout* = ref object of Class
        repository*: Repository
        commit*: Commit
        path*: string


begin Commit:
    proc `$`*(): string =
        result = fmt "{this.id} ($this.version)"

    proc hash*(): Hash =
        result = hash(this.id)

begin Repository:
    proc hash*(): Hash =
        result = this.hash

    proc qualifyUrl*(url: string): string {. static .} =
        var
            uri = parseUri(url)

        if not uri.scheme:
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

        if uri.scheme:
            if uri.path.endsWith(".git"):
                uri.path = uri.path[0..^5]
        else:
            uri.path = absolutePath($uri)

        result = $uri

    proc validateUrl*(url: string): void {. static .} =
        let
            qualifiedUrl = self.qualifyUrl(url)
        var
            error: int
            output: string

        if not qualifiedUrl.startsWith($paths.getCurrentDir()):
            (output, error) = execCmdEx(fmt "git ls-remote '{qualifiedUrl}' 'null'")
        else:
            error = 1

        if error:
            raise newException(ValueError, fmt "repository at '{url}' does not seem to exist")

    method init*(url: string): void {. base .} =
        this.url = self.qualifyUrl(url)
        this.hash = hash(toLower(this.url))
        this.shaHash = toLower($secureHash(this.url))
        this.cacheDir = percy.getAppCacheDir(this.shaHash)
        this.origin = url

        let
            head = this.cacheDir / "FETCH_HEAD"
        if fileExists(head):
            this.stale = getTime() > getLastModificationTime(head) + 2.minutes
        else:
            this.stale = true

    method url*(): string {. base .} =
        result = this.url

    method origin*(): string {. base .} =
        result = this.origin

    method shaHash*(): string {. base .} =
        result = this.shaHash

    method cacheDir*(): string {. base .} =
        result = this.cacheDir

    method cacheExists*(): bool {. base .} =
        result = dirExists(this.cacheDir)

    method exists*(): bool {. base .} =
        try:
            self.validateUrl(this.url)
            result = true
        except:
            result = false

    method clone*(): RCloneStatus {. base .} =
        var
            error: int

        if this.cacheExists:
            result = RCloneExists
        else:
            echo fmt "Downloading {this.url} into central caching"

            error = percy.execCmd(@[
                fmt "git clone --bare {this.url} {this.cacheDir}"
            ])

            if error:
                raise newException(ValueError, fmt "failed cloning {this.url}")
            else:
                result = RCloneCreated

    method exec*(cmdParts: seq[string], output: var string): int {. base .} =
        var
            error: int
            wrappedOutput: string

        if not this.cacheExists:
            discard this.clone()

        percy.execIn(
            ExecHook as (
                block:
                    (wrappedOutput, error) = execCmdEx(cmdParts.join(" "))
            ),
            this.cacheDir
        )

        result = error
        output = wrappedOutput

    method update*(): RUpdateStatus {. base .} =
        var
            error: int
            output: string

        result = RUpdateSkip

        if this.stale:
            this.stale = false

            if not this.cacheExists:
                discard this.clone()
                result = RUpdateCloned

            when defined debug:
                echo fmt "Checking for updates in {this.url}"

            error = this.exec(
                @[
                    fmt "git fetch origin -f --prune",
                    fmt "'+refs/tags/*:refs/{percy.name}/*'",
                    fmt "'+refs/heads/*:refs/{percy.name}/*'",
                    fmt "HEAD"
                ],
                output
            )

            if error:
                raise newException(ValueError, fmt "failed updating {this.url}: {output}")
            elif not output.len:
                result = RUpdateNone
            else:
                echo fmt "Fetched new references from {this.url}"
                result = RUpdated

            setLastModificationTime(this.cacheDir / "FETCH_HEAD", getTime())

    method commits*(): OrderedSet[Commit] {. base .} =
        const
            tag  = "%(refname:short)"
            hash = "%(if:equals=tag)%(objecttype)%(then)%(*objectname)%(else)%(objectname)%(end)"
        let
            prefix = fmt "{percy.name}/"
        var
            error: int
            output: string
            head: string

        discard this.update()

        error = this.exec(
            @[
                fmt "git for-each-ref --omit-empty --format='{tag} {hash}'",
                fmt "'refs/{percy.name}/?*[0-9]*.*'",
                fmt "'refs/{percy.name}/*'"
            ],
            output
        )

        for line in readFile(this.cacheDir / "FETCH_HEAD").split("\n"):
            if line.endsWith("\t\t" & this.url):
                head = line[0..39]
                break

        output = fmt "HEAD {head}\n{output}"

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
            error: int
            worktrees: string

        error = this.exec(
            @[
                fmt "git worktree prune"
            ],
            worktrees
        )
        if error:
            raise newException(ValueError, "Could not prune worktree list")

        error = this.exec(
            @[
                fmt "git worktree list --porcelain"
            ],
            worktrees
        )
        if error:
            raise newException(ValueError, "Could not get worktree list")

        for worktree in worktrees.strip().split("\n\n"):
            let
                lines = worktree.split('\n')
            var
                path: string = ""
                head: string = ""

            if lines[1] == "bare":
                continue
            if not lines[0].startsWith("worktree "):
                continue

            path = lines[0].split(' ')[1]

            for line in lines:
                if line.startsWith("HEAD "):
                    head = line.split(' ')[1]

            if path and head:
                result[path] = WorkTree(
                    repository: this,
                    head: head,
                    path: path
                )

    method listDir*(path: string, reference: string = "HEAD"): seq[string] {. base .} =
        var
            error: int
            output: string

        error = this.exec(
            @[
                fmt "git ls-tree --name-only {reference} --name-only :{path}"
            ],
            output
        )

        if error:
            raise newException(
                ValueError,
                fmt "failed to list directory {reference}:{path} on {this.url}"
            )

        result = output.strip().split('\n')

    method readFile*(path: string, reference: string = "HEAD"): string {. base .} =
        let
            file = reference & ":" & path.strip("/")
        var
            error: int
            output: string

        when debugging(2):
            echo fmt "Reading file {file} @ {this.url}"

        error = this.exec(
            @[
                fmt "git show {file}"
            ],
            output
        )

        if error:
            raise newException(
                ValueError,
                fmt "failed to read file {reference}:{path} on {this.url}"
            )

        result = output



