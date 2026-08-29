import
    percy,
    basecli,
    lib/links

type
    UnlinkCommand = ref object of BaseCommand

begin UnlinkCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            name = console.getArg("name")
            repository = this.settings.getRepository(name)
            url = repository.url
            workDir = this.settings.getWorkDir(url)
            targetDir = getVendorDir(workDir)

        var links = readLinks()

        if links.links.len == 0:
            fail fmt "No linked packages found ('{linksFile}' does not exist)"
            return 1
        elif url notin links:
            fail fmt "Package '{name}' is not linked"
            info fmt "> Hint: Run `percy link {name} <path>` to link it"
            return 2

        if symLinkExists(targetDir):
            removeFile(targetDir)

        links.links.del(url)
        writeLinks(links)

        print fmt "Unlinked '{name}'"
        info fmt "> Hint: Run `percy install` to restore the vendored version"

shape UnlinkCommand: @[
    Command(
        name: "unlink",
        description: "Unlink a workspace directory, restoring normal vendor management",
        opts: @[CommandConfigOpt, CommandVerbosityOpt],
        args: @[
            Arg(name: "name", description: "Package alias or name to unlink")
        ]
    )
]
