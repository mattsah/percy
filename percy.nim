import
    mininim/loader,
    mininim/dic,
    mininim/cli,
    std/os

loader.scan(currentSourcePath().parentDir / "local")

var
    app = App.init()
    console = app.get(Console)

quit(console.run())
