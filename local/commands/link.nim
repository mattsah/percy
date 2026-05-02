import
    percy,
    basecli,
    lib/links,
    lib/lockfile

type
    LinkCommand = ref object of BaseCommand

begin LinkCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            name = console.getArg("name")
            path = console.getArg("path")
            repository = this.settings.getRepository(name)
            url = repository.url
            targetDir = getVendorDir(this.settings.getWorkDir(url))
            absPath = expandTilde(path).absolutePath()

        let lockFile = LockFile.init(fmt "{percy.name}.lock")
        if not lockFile.exists() or not lockFile.commits().anyIt(it.repository.url == url):
            fail fmt "'{name}' is not a dependency of this project. Run 'percy install' first if needed."
            return 1
        elif not dirExists(absPath):
            fail fmt "Path does not exist or is not a directory: '{absPath}'"
            return 2
        elif symLinkExists(targetDir):
            fail fmt "Already linked. Run `percy unlink {name}` first."
            return 3

        if dirExists(targetDir):
            removeDir(targetDir)

        createDir(targetDir.parentDir())
        createSymlink(absPath, targetDir)

        var links = readLinks()
        links.links[url] = absPath
        writeLinks(links)

        print fmt "Linked '{name}' ({url}) → {absPath}"

shape LinkCommand: @[
    Command(
        name: "link",
        description: "Link a local workspace directory as a vendored package",
        opts: @[CommandConfigOpt, CommandVerbosityOpt],
        args: @[
            Arg(name: "name", description: "Package alias or name to link"),
            Arg(name: "path", description: "Local filesystem path to the workspace directory")
        ]
    )
]
