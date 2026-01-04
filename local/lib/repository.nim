import
    percy,
    semver,
    std/re,
    std/uri,
    std/hashes,
    checksums/sha1

type
    InvalidRepositoryUrlException* = ref object of CatchableError
        url*: string

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
        if url.startsWith(getCurrentDir() & "/"):
            raise InvalidRepositoryUrlException(
                msg: fmt "repository should not be in your working directory",
                url: url
            )

    proc qualifyUrl*(url: string): string {. static .} =
        var
            uri = parseUri(url)

        if uri.scheme.len == 0: # optimized
            if dirExists(uri.path / ".git"):
                uri.path = absolutePath(uri.path)
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
        elif uri.path != "":
            uri.path = absolutePath(uri.path)
        else:
            uri.path = getCurrentDir().splitFile().name

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

    #[
        Determine whether or not a repository exists by trying to list the remote
    ]#
    method exists*(): bool {. base .} =
        var
            error: int

        if this.cacheExists:
            result = true
        else:
            error = percy.execCmd(@[
                fmt "git ls-remote '{this.url}' 'null'"
            ])

            result = error == 0

    #[
        Execute commands within the context of a repository
    ]#
    method exec*(cmdParts: seq[string], output: var string): int {. base .} =
        var
            error: int
            safeOutput: string

        percy.execIn(
            ExecHook as (
                block:
                    error = percy.execCmdCaptureAll(safeOutput, @[cmdParts.join(" ")])
            ),
            this.cacheDir
        )

        result = error
        output = safeOutput

    #[
        Fetch the latest commits
    ]#
    method fetch*(quiet: bool = true): bool {. base .} =
        var
            error: int
            output: string

        if not quiet:
            print fmt "Repository: Getting Updates"
            print fmt "> URL: {this.url}"
            print fmt "> Hash: {this.shaHash}"

        error = this.exec(
            @[
                fmt "git fetch origin -f --prune",
                fmt "'+refs/tags/*:refs/{percy.name}/*'",
                fmt "'+refs/heads/*:refs/{percy.name}/head@*'",
                fmt "'HEAD'"
            ],
            output
        )

        if error != 0 or not fileExists(this.cacheDir / "FETCH_HEAD"):
            if output.len == 0:
                output = "unknown problem"

            raise newException(
                ValueError,
                fmt "failed fetching from {this.url} ({this.shaHash}): {output}"
            )

        setLastModificationTime(this.cacheDir / "FETCH_HEAD", getTime())

        this.stale = false
        result = output.len > 0

    #[
        Clone the repository into the local cache
    ]#
    method clone*(quiet: bool = true): RCloneStatus {. base .} =
        var
            error: int
            output: string

        if this.cacheExists:
            return RCloneExists

        if not this.exists:
            raise newException(
                ValueError,
                fmt "cannot clone {this.url} ({this.shaHash}), unable to connect to repository"
            )

        if not quiet:
            print fmt "Repository: Cloning"
            print fmt "> URL: {this.url}"
            print fmt "> Hash: {this.shaHash}"

        error = percy.execCmdCaptureAll(output, @[
            fmt "git clone --bare {this.url} {this.cacheDir}"
        ])

        if error:
            raise newException(
                ValueError,
                fmt "failed cloning {this.url}"
            )

        discard this.fetch()

        result = RCloneCreated

    #[
        Update the repository, taking into account existence, staleness, etc.
    ]#
    method update*(quiet: bool = true, force: bool = false): RUpdateStatus {. base .} =
        result = RUpdateSkip

        if not this.cacheExists:
            discard this.clone(quiet = quiet)
            return RUpdateCloned

        if force or this.stale:
            if this.fetch(quiet = quiet):
                result = RUpdated
            else:
                result = RUpdateNone

    #[
        Prune the repository worktrees
    ]#
    method prune*(): bool {. base .} =
        var
            error: int
            output: string

        error = this.exec(
            @[
                fmt "git worktree prune -v"
            ],
            output
        )

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed pruning {this.url} ({this.shaHash}): {output}"
            )

        result = output.len > 0

    #[
        Get the HEAD commit id
    ]#
    method head*(): string {. base .} =
        if fileExists(this.cacheDir / "FETCH_HEAD"):
            for line in readFile(this.cacheDir / "FETCH_HEAD").split("\n"):
                let
                    matchUrl = this.url.strip(leading = false, chars = {'/'}).toLower()
                if line.toLower().split("\t\t")[1].startsWith(matchUrl):
                    result = line[0..39]
                    break
        if not result:
            raise newException(
                ValueError,
                fmt "could not determine head on {this.url} ({this.shaHash})"
            )

    #[
        Get a list of all worktrees, indexed by their path
    ]#
    method worktrees*(): Table[string, WorkTree] {. base .} =
        var
            error: int
            output: string

        discard this.prune()

        error = this.exec(
            @[
                fmt "git worktree list --porcelain"
            ],
            output
        )

        if error != 0:
            raise newException(
                ValueError,
                fmt "could not list worktreess on {this.url} ({this.shaHash}): {output}"
            )

        for worktree in output.strip().split("\n\n"):
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

    method getCommit*(id: string): Option[Commit] {. base .} =
        var
            error: int
            output: string

        error = this.exec(
            @[
                fmt "git rev-parse {id}"
            ],
            output
        )

        if error == 0:
            result = some(Commit(
                id: output.strip(),
                version: ver(id),
                repository: this
            ))

    method getCommits*(newest: bool = false): OrderedSet[Commit] {. base .} =
        const
            tag  = "%(refname:short)"
            hash = "%(if:equals=tag)%(objecttype)%(then)%(*objectname)%(else)%(objectname)%(end)"
        let
            prefix = fmt "{percy.name}/"
        var
            error: int
            output: string
            head: string

        error = this.exec(
            @[
                fmt "git for-each-ref --omit-empty --format='{tag} {hash}'",
                fmt "'refs/{percy.name}/*'"
            ],
            output
        )

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed aggregating commits on {this.url} ({this.shaHash})"
            )

        output = fmt "HEAD {this.head}\n{output}"

        for reference in output.split('\n'):
            let
                parts = reference.split(' ', 1)
            var
                version: Version
            if parts.len == 2:
                try:
                    if parts[0] == "HEAD":
                        version = ver("head")
                    else:
                        version = ver(parts[0][prefix.len..^1])

                    result.incl(Commit(
                        id: parts[1],
                        repository: this,
                        version: version
                    ))

                except Exception as e:
                    raise newException(
                        ValueError,
                        fmt "failed loading '{reference}' on {this.url} ({this.shaHash}): {e.msg}"
                    )

    #[
        Make a reference path for ls-tree or show
    ]#
    method makePath*(path: string, reference: string = ""): string {. base .} =
        if reference == "":
            result = this.head & ":" & path
        else:
            result = reference & ":" & path

    #[
        List a directory at a given reference
    ]#
    method listDir*(path: string, reference: string = ""): seq[string] {. base .} =
        let
            directory = this.makePath(path.strip(chars = {'/'}), reference)
        var
            error: int
            output: string
        when debugging(2):
            print fmt "Listing directory {directory} on {this.url} ({this.shaHash})"

        error = this.exec(@[fmt "git ls-tree --name-only {directory}"], output)

        if error != 0:
            raise newException(
                ValueError,
                fmt "could not list directory {directory} on {this.url} ({this.shaHash})"
            )

        result = output.strip().split('\n')

    #[
        Read a file at a given reference
    ]#
    method readFile*(path: string, reference: string = ""): string {. base .} =
        let
            file = this.makePath(path, reference)
        var
            error: int
        when debugging(2):
            print fmt "Reading file {file} on {this.url} ({this.shaHash})"

        error = this.exec(@[fmt "git show {file}"], result)

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed to read file {file} on {this.url} ({this.shaHash})"
            )
