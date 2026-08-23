import
    percy


proc controlled*(targetDir: string): bool =
    var
        error: int
        output: string

    percy.execIn(
        ExecHook as (
            block:
                error = percy.execCmdCapture(output, @[
                    fmt "git rev-parse --git-dir"
                ])
        ),
        targetDir
    )

    return error == 0

proc commonDirectory*(targetDir: string): string =
    var
        error: int
        output: string

    percy.execIn(
        ExecHook as (
            block:
                error = percy.execCmdCapture(output, @[
                    fmt "git rev-parse --path-format=absolute --git-common-dir"
                ])
        ),
        targetDir
    )

    result = output

proc currentChanges*(targetDir: string): string =
    var
        error: int
        output: string

    percy.execIn(
        ExecHook as (
            block:
                error = percy.execCmdCapture(output, @[
                    fmt "git status --porcelain"
                ])
        ),
        targetDir
    )

    result = output

proc currentHead*(targetDir: string): string =
    var
        error: int
        output: string

    percy.execIn(
        ExecHook as (
            block:
                error = percy.execCmdCapture(output, @[
                    fmt "git rev-parse HEAD"
                ])
        ),
        targetDir
    )

    result = output

proc origin*(targetDir: string): string =
    var
        error: int
        output: string

    percy.execIn(
        ExecHook as (
            block:
                error = percy.execCmdCapture(output, @[
                    fmt "git remote get-url origin"
                ])
        ),
        targetDir
    )

    result = output
