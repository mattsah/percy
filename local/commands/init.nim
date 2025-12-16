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

        if fileExists(this.config) and reset of false:
            stdout.write fmt "Percy is already initialized in {this.config}."
            stdout.write fmt " You can use set/unset commands to modify it"
            stdout.write '\n'

            result = -1
        else:
            this.settings.data.sources.clear()
            this.settings.data.packages.clear()

            this.settings.data.meta = newJObject()
            this.settings.data.sources["nim-lang"] = Source.init(
                this.settings.getRepository("gh://nim-lang/packages")
            )

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