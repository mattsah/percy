import
    percy,
    std/uri,
    std/paths,
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
        url: string
        hash: string
        origin: string

begin Repository:
    proc `$`*(): string =
        result = this.hash

    proc `%`*(): JsonNode =
        result = newJString(this.hash)

    proc qualifyUrl*(url: string): string {. static .} =
        var
            uri = parseUri(url)

        if not uri.scheme:
            if dirExists(uri.path / ".git"):
                uri.path = $absolutePath(Path uri.path)
        else:
            if uri.scheme notin ["http", "https"]:
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

            if uri.path.endsWith(".git"):
                uri.path = uri.path[0..^5]

        result = $uri

    proc validateUrl*(url: string): void {. static .} =
        discard self.qualifyUrl(url)

    method init*(url: string): void {. base .} =
        this.url = self.qualifyUrl(url)
        this.hash = toLower($secureHash(toLower(this.url)))
        this.origin = url

    method clone*(): RCloneStatus {. base .} =
        var
            status: RCloneStatus
            error: int

        percy.execIn(
            ExecHook as (
                block:
                    if not dirExists(this.hash):
                        echo fmt "Downloading {this.url} into central caching"

                        error = percy.execCmd(@["git clone --bare", this.url, this.hash])

                        if error:
                            raise newException(ValueError, fmt "failed cloning {this.url}")
                        else:
                            status = RCloneCreated
                    else:
                        status = RCloneExists
            ),
            percy.getAppCacheDir()
        )

        result = status

    method update*(): RUpdateStatus {. base .} =
        var
            status: RUpdateStatus
            output: string
            error: int
        let
            cacheDir = percy.getAppCacheDir(this.hash)

        if not dirExists(cacheDir):
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
                cacheDir
            )
            result = status

    method list*(pattern: string, reference: string = "HEAD"): string {. base .} =
        var
            output: string
            error: int
        percy.execIn(
            ExecHook as (
                block:
                    error = percy.execCmdEx(
                        output,
                        @[
                            fmt "git grep -l '' {reference} -- '{pattern}'"
                        ]
                    )
            ),
            percy.getAppCacheDir(this.hash)
        )

        if not error:
            let
                lines = output.split('\n')
            if lines.len > 0:
                result = lines[0]

    method read*(pattern: string, reference: string = "HEAD"): string {. base .} =
        var
            output: string
            error: int
        let
            file = this.list(pattern, reference)

        if file.len:
            percy.execIn(
                ExecHook as (
                    block:
                        (output, error) = execCmdEx(fmt "git show {file}")
                ),
                percy.getAppCacheDir(this.hash)
            )

            if not error:
                result = output

    method exec(callback: proc(repository: self): void): void {. base .} =
        percy.execIn(
            ExecHook as (
                block:
                    callback(this)
            ),
            percy.getAppCacheDir(this.hash)
        )

    method origin*(): string {. base .} =
        result = this.origin

    method url*(): string {. base .} =
        result = this.url
