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
        RUpdateNone
        RUpdated

    Repository* = ref object of Class
        hash: Hash
        dirty: bool
        shaHash: string
        cacheDir: string
        origin: string
        url: string

    Commit* = ref object of Class
        id*: string
        version*: Version
        repository*: Repository

begin Commit:
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
                    else:
                        raise newException(ValueError, fmt "invalid scheme {uri.scheme}")
                uri.scheme = "https"

        if uri.scheme and uri.path.endsWith(".git"):
            uri.path = uri.path[0..^5]

        result = $uri

    proc validateUrl*(url: string): void {. static .} =
        discard self.qualifyUrl(url)

    method init*(url: string): void {. base .} =
        this.url = self.qualifyUrl(url)
        this.hash = hash(toLower(this.url))
        this.shaHash = toLower($secureHash(this.url))
        this.cacheDir = percy.getAppCacheDir(this.shaHash)
        this.origin = url
        this.dirty = true

    method url*(): string {. base .} =
        result = this.url

    method origin*(): string {. base .} =
        result = this.origin

    method shaHash*(): string {. base .} =
        result = this.shaHash

    method cacheDir*(): string {. base .} =
        result = this.cacheDir

    method clone*(): RCloneStatus {. base .} =
        var
            error: int

        if not dirExists(this.cacheDir):
            echo fmt "Downloading {this.url} into central caching"

            error = percy.execCmd(@[
                fmt "git clone --bare {this.url} {this.cacheDir}"
            ])

            if error:
                raise newException(ValueError, fmt "failed cloning {this.url}")
            else:
                result = RCloneCreated
        else:
            result = RCloneExists

    method update*(): RUpdateStatus {. base .} =
        var
            status: RUpdateStatus
            output: string
            error: int
        if this.dirty:
            if not dirExists(this.cacheDir):
                discard this.clone()
                result = RUpdateCloned
            else:
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmdEx(
                                output,
                                @[
                                    "git fetch origin -f --prune",
                                    "'+refs/heads/*:refs/heads/*'",
                                    "'+refs/tags/*:refs/tags/*'"
                                ]
                            )

                            if error:
                                raise newException(ValueError, fmt "failed updating {this.url}")
                            elif not output.len:
                                status = RUpdateNone
                            else:
                                echo fmt "Fetched new references from {this.url}"
                                status = RUpdated
                    ),
                    this.cacheDir
                )
                result = status
            this.dirty = false

    method list*(path: string, reference: string = "HEAD"): seq[string] {. base .} =
        var
            output: string
            error: int
        percy.execIn(
            ExecHook as (
                block:
                    error = percy.execCmdEx(
                        output,
                        @[
                            fmt "git ls-tree --name-only {reference} --name-only :{path}"
                        ]
                    )
            ),
            this.cacheDir
        )

        if not error:
            result = output.strip().split('\n')

    method read*(path: string, reference: string = "HEAD"): string {. base .} =
        let
            file = reference & ":" & path.strip("/")
        var
            output: string
            error: int
        percy.execIn(
            ExecHook as (
                block:
                    (output, error) = execCmdEx(fmt "git show {file}")
            ),
            this.cacheDir
        )

        if not error:
            result = output

    method exec(callback: proc(repository: self): void): void {. base .} =
        percy.execIn(
            ExecHook as (
                block:
                    callback(this)
            ),
            this.cacheDir
        )

    method tags*(): seq[Commit] {. base .} =
        const
            tag  = "%(refname:short)"
            hash = "%(if:equals=tag)%(objecttype)%(then)%(*objectname)%(else)%(objectname)%(end)"
        var
            output: string
            error: int

        discard this.update()

        percy.execIn(
            ExecHook as (
                block:
                    error = percy.execCmdEx(output, @[
                        fmt "git for-each-ref --format='{tag} {hash}' 'refs/tags/?*[0-9]*.*'"
                    ])

                    if error:
                        raise newException(ValueError, fmt "failed getting tags for {this.url}")
            ),
            this.cacheDir
        )

        for tag in output.split('\n'):
            let
                parts = tag.split(' ', 1)
            if parts.len == 2:
                result.add(Commit(
                    id: parts[1],
                    repository: this,
                    version: v(parts[0].replace(re"^[^0-9]*", ""))
                ))
