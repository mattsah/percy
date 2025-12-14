import
    mininim,
    mininim/cli

type
    RemoveCommand = ref object of Class

begin RemoveCommand:
    method execute(console: Console): int {. base .} =
        discard

shape RemoveCommand: @[
    Command(
        name: "remove",
        description: "Remove a package from the dependencies"
    )
]