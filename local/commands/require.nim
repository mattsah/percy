import
    percy,
    basecli

type
    RequireCommand = ref object of BaseGraphCommand

begin RequireCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        echo $this.nimbleFile
        echo $this.nimbleInfo
        echo $this.nimbleMap

        # get original requires count
        # loop through all existing requires
        #   parse the package out and resolve to URL
        #   if parsed package URL matches the resolved URL of the [package arg]
        #       replace the version constraints
        #   else
        #       add a new requires to the map e.g. >> {%requires-{requires.len}%}

        # replace placeholder tokens

        # re-run dependency graph with update contents without executing solution to make sure everything works
        # if it works
        #       write the file
        #       execute the solution
        # else
        #       do error and do not write file

shape RequireCommand: @[
    Command(
        name: "require",
        description: "Add a requirement to the project",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ]
    )
]