import
    percy,
    mininim/cli

type
    UpdateCommand = ref object of Class

begin UpdateCommand:
    method execute(console: Console): int {. base .} =
        discard

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update package(s) and corresponding version constraints"
    )
]