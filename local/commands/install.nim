import
    percy,
    basecli

type
    InstallCommand = ref object of BaseGraphCommand

begin InstallCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        this.settings.prepare()

#        for requirement in nimbleInfo.requires:
#            depgraph.addRequirement(requirement)

shape InstallCommand: @[
    Command(
        name: "install",
        description: "Install all dependencies (use lock file if exists)",
        opts: @[
            CommandFileOpt
        ]
    )
]