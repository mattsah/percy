import
    percy,
    basecli

type
    InitCommand = ref object of BaseCommand

begin InitCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            reset = console.getOpt("reset", "r")

        if reset:
            this.settings.data.sources.clear()
            this.settings.data.packages.clear()

            this.settings.data.meta = newJObject()
            this.settings.data.sources["nim-lang"] = Source.init(
                this.settings.getRepository("gh://nim-lang/packages")
            )
        else:
            if fileExists(this.config):
                this.settings.index()

        this.settings.save()

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize as a percy package",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
            Opt(
                flag: "r",
                name: "reset",
                description: "Force re-initialization (resetting sources/packages)"
            )
        ]
    )
]