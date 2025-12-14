import
    mininim/loader,
    mininim/dic,
    mininim/cli

loader.scan("./local")

var
    app = App.init()
    console = app.get(Console)

quit(console.run())
