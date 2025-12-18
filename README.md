# Percy
Are you sick and tired of terrible package managers for Nim?

Percy is a different approach to package management for Nim.  Short for Perseus, _**the greek hero that turned Atlas into stone**_, Percy came out frustrations with both `nimble` and `atlas`, neither of which do particularly well in early stages of dynamic development or seemingly with fast moving HEADs.

The goal of Percy is to actually make package management for nim that "just works."  Performance is a secondary concern, although it still aims to be fast.  Additional key goals are:

- Make adding custom/private package repositories easy and central
- Abandon package names for everything other than local working copies (in `vendor`), fulfilling the promise that everything is _actually_ a URL.
- Use a hybrid cached/centralized storage approach, with git work trees for local working copies.

## Limitations

- Only works with `git` (no `hg`) packages/repositories
- Assumed `git` is in your path and is a fairly recent version (at least having worktree support)
- Dependency solver is work in progress (currently doesn't actually validate a solution) and just effectively uses highest versions.
- Nim >= 2.2.6

## Getting Started

Percy aims to work with official nim packages and the use of existing `.nimble` files.  In fact, unlike some other solutions, there's no intention of getting rid of the `.nimble` file at all, rather just limiting it's use/purpose.  

> Keeping **the limitations above** in mind, we're asking people to test other initial aspects of Percy by:
>
> - Installing it
> - Trying to install project dependencies with it
> - Perhaps trying to build off the result

### Installation

Although Percy is currently self-hosting (i.e. can manage its own dependencies and build itself), chances are you don't have it installed and there are no binary distributed files yet, so, ironically, you need to use Atlas:

```bash
git clone https://github.com/mattsah/percy
cd percy
atlas install
nim build
```

Assuming it built fine:

```bash
cp bin/percy <somewhere in your path>
```

### Usage

#### Initialization

You can initialize Percy rather easily.  Simply execute the following in your project directory:

```bash
percy init
```

The `init` command will add something like the following to your `config.nims` file:

```nim
# <percy>
when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    include "vendor/percy.paths"
# </percy>
```

If you want to make use of Percy's build/test tasks you can **alternatively** run the following:

```
percy init -w
```

> **NOTE:** this will add an more extensive and opinionated code to your `config.nims` to enable the use of the following commands:
>
> - `nim build`
> - `nim test`

If you want to know what gets added take a look [here](https://github.com/mattsah/percy/blob/master/local/commands/init.nim) at the `gettasks()` method.  It may not work for your build requirements, so you should **check first** to make sure.

##### The `percy.json` file

Once your project is initialized, you should have a `percy.json` file in the root of the project.  This file tracks package sources and provides a placeholder for some meta information.  To add more packages, see the section below on [adding packages](#adding-packages).

##### The `vendor` directory

In addition to the `percy.json` file, initialization should have created a `vendor` directory along with a file called `index.percy.json`.  This file contains a list of the resolved URLs for all packages available with your current configuration.

#### Installation

To install your dependencies you run:

```bash
percy install
```

Or, as is definitely suggested for first-use and testing:

```bash
percy install -v
```

The `-v` option will give a lot of output as dependencies are collected and the graph is built.  Without it, you'll only see the messages coming from select git commands.  At the end of an install with `-v` you should get report such as:

```
Graph: Graph Completed With Usable Versions
  https://github.com/nim-lang/Nim:
    2.2.6
  https://github.com/nim-lang/checksums:
    0.2.1
  https://github.com/primd-cooperative/mininim-core:
    0.0.0-branch.main
    0.0.1
  https://github.com/primd-cooperative/mininim-cli:
    0.0.0-branch.main
    0.0.1
  https://github.com/euantorano/semver.nim:
    1.2.3
    1.2.2
    1.2.1
    1.2.0
```

This report shows usable versions which have not been excluded by top-level project requirements and is prior to solving (which again doesn't actually really solve anything right now).

#### Adding Packages

You can add packages in two distinct ways.

- **Sources** are entire package repositories, such as the official nim packages repository.
- **Packages** are one off packages which can point to an arbitrary git URL.

Upon initialization, your `percy.json` file will only contain the official Nim packages repository:

```json
{
  "meta": {},
  "sources": {
    "nim-lang": "gh://nim-lang/packages"
  },
  "packages": {}
}
```

##### Sources

You can add a source via:

```bash
percy set source <name> <url>
```

The `<url>` must point to a git repository containing a `packages.json` file in its root that is schema-compatible with the one found in `nim-lang/packages`.  Note, however, the only two required fields are `name` and `url` .  As an example, let's take a look at the [Mininim](https://github.com/primd-cooperative/mininim) framework's package repository's file, located [here](https://github.com/primd-cooperative/mininim-packages/blob/main/packages.json).  Note it only the two fields are added:

```json
[
	{
        "name": "mininim_core",
        "url": "https://github.com/primd-cooperative/mininim-core"
    },
    ...
]
```

To add this repository to your own Percy configuration, you would execute:

```bash
percy set source mininim gh://primd-cooperative/mininim-packages
```

If you wanted to remove it:

```bash
percy unset source mininim
```

> Note:  The example above to add the mininim repository uses `gh://` forge-style URLs.  You are **not** required to use this style of URL, and standard `https://` or even `git@` URLs should be viable, although in our experience `https://` is significantly faster than git over SSH.

##### Packages

Adding individual packages is also possible via the `set` command.  The only distinction here is that instead of pointing at a repository that contains a `packages.json` file, you're pointing at the repository for the package itself.

```bash
percy set package neo https://github.com/xTrayambak/neo.git
```

> **NOTE:**  When packages added via the `set package` command or as part of a source repository added with `set source` have a conflicting name, the latter defined URL is _always used_ and with package URLs overwriting URLs provided by source repositories.

In the example above, `neo` would now refer to to the URL provided in the example, instead of the one defined in the nim official repository.  The recommended approach is to retain the nim official repository as your first source, add sources after which constitute private repositories and/or overloads to the official, while using package entries to resolve any conflicts.  Also **stop** using short package names.

##### Additional Notes on Naming Packages

Because of the way Percy resolves package names (and because they no longer need to be valid identifiers in Nim), you can actually have packages with any name.  It should be noted, however, that if you do this, adding named packages to your `.nimble` files will obviously break any compatibility with other package manager.  For example it is completely possible to do the following:

```bash
percy set package mininim/core gh://primd-cooperative/mininim-core
```

> **NOTE:** The package name contains a slash (`/`)

It is then possible to define in a nimble file:

```nim
requires "mininim/core"
```

In fact, package names with Percy can pretty much contain any character except those required by version constraints, e.g `=`, `<`, `>`, `~`, `^` and `#`.

In the event you **use a slash**, you will additionally notice that your packages will appear in your `vendor` directory as a sub-directory structure.  Indeed, it should be further noted that **if you have non-named URL-based requirements those will be installed to vendor based on the "path" component of their URL**, thereby avoiding potential conflicts.

All non-namespaced packages (official packages and non-slash named packages) will be installed into `vendor/+global`.

Using our previous example of `neo`, were we to require the URL directly in our `.nimble` file, then instead of being instead of overloading the name, it would be located in `vendor/xTrayambak/neo`.  Allowing for both the official `neo` package and that one to be installed:

```
vendor
├── +global
│  └── neo
├── xTrayambak
│  └── neo
└── index.percy.json
```



## More to Come

- Require
- Remove
- Update
- Hooks
