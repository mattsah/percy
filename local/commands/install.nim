import
    percy,
    mininim/cli,
    lib/settings

type
    InstallCommand = ref object of Class
        settings: Settings

begin InstallCommand:
    method execute(console: Console): int {. base .} =
        let
            nimbleInfo = percy.getNimbleInfo()

        this.settings.prepare()

        for requirement in nimbleInfo.requires:
            echo requirement

        discard

shape InstallCommand: @[
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                result.settings = this.app.get(Settings)
        )
    ),
    Command(
        name: "install",
        description: "Install all dependencies (use lock file if exists)"
    )
]