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
- Nim >= 2.2.6 (May actually work on earlier versions, but it's on you to custom build)

## Skip To

- [Full User Guide](#user-guide)
- [Nimble File Support](#nimble-file-support)
- [Versioning](#versioning)

... or see the next section for a more general introduction.

## 

## Quick Start

### Installing Percy

```bash
nimble install https://github.com/mattsah/percy
```

### Initializing a Project

Initializing a project (in the project dir):

```bash
percy init
```

Initializing a project (from a repository):

```bash
percy init cb://mininim/app
```

Or

```bash
percy init cb://mininim/app my-new-app
```

### Installing Dependencies

Installing (from a lock file), if no lock file is present this is equivalent to `update -n`:

```bash
percy install
```

With verbose output:

```bash
percy install -v
```

### Updating Dependencies

Update to latest compatible versions (write a lock file):

```bash
percy update
```

Update ensuring latest is in cache (fetching from remotes):

```bash
percy update -n
```

Force updating in an unclean `vendor` directory:

```bash
percy update -f
```

### Package Availability

Adding a source (a git repository with `packages.json` providing a list of packages)

```bash
percy set source mininim cb://mininm/packages
```

Add a package (such as overloading to a fork or working with one still in development)

```bash
percy set package semver gh://myforks/semver
```

Removing a source:

```bash
percy unset source mininim
```

Removing a package:

```bash
percy unset semver
```

### Working with Dependencies

Set a dependency or change the required versions (updates the project's *.nimble):

```bash
percy require dotenv ">= 2.0.0"
```

Or add by URL instead:

```bash
percy require gh://euantorano/dotenv ">= 2.0.0"
```

Remove a dependency (by name):

```
percy remove dotenv
```

Remove a dependency (by URL)

```
percy remove gh://euantorano/dotenv
```

> **NOTE:** It doesn't matter how the dependency was added, you can remove it by either so long as the package name resolves to the same URL.

## User Guide

Percy aims to work with official nim packages and the use of existing `.nimble` files.  In fact, unlike some other solutions, there's no intention of getting rid of the `.nimble` file at all, rather just limiting its use/purpose.

> Keeping **the limitations above** in mind, we're asking people to test other initial aspects of Percy by:
>
> - Installing it
> - Trying to install project dependencies with it
> - Perhaps trying to build off the result

### Installation

Although Percy is currently self-hosting (i.e. can manage its own dependencies and build itself), chances are you don't have it installed and there are no binary distributed files yet, so, ironically, you need to use to install it using Nimble or Atlas.

#### Installing with Nimble (Recommended for Ease -- if it works)

```bash
nimble install https://github.com/mattsah/percy
```

Assuming Nimble's `bin` path is in your `PATH`, then you should simply be able to type `percy` to see the help.

#### Installing with Atlas (Recommended for Reliability)

```bash
git clone https://github.com/mattsah/percy
cd percy
atlas install
nim build
```

Assuming it built fine:

```bash
cp bin/percy <somewhere in your path(s)>
```

### Usage

#### Initialization

You can initialize Percy rather easily.  Simply execute the following in your project directory:

```bash
percy init
```

The `init` command will add three distinct percy sections to your `config.nims`:

1. Conditional inclusion of `vendor/percy.paths` (see code below)
2. A `build` task **if** no current `build` task is identified.
3. A `test` task **if** no current `test` task is identified.

```nim
# <percy>
when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    include "vendor/percy.paths"
# </percy>
```

> **NOTE:** the build and test tasks are more opinionated, and how they work might change over time.  As of this writing, the build task is pretty solid, but the test task is using `testament` and making some assumptions.
>
> - `nim build`
> - `nim test`
>
> When newer versions of `percy` are released, you can simply re-run `percy init` to get the latest tasks.


If you want to explicitly exclude the addition of the tasks you can **alternatively** run the following:

```
percy init -w
```

If you want to know the gritty details of what gets added take a look [here](https://github.com/mattsah/percy/blob/master/local/commands/init.nim) at the `*Task()` method(s).

##### The `percy.json` file

Once your project is initialized, you should have a `percy.json` file in the root of the project.  This file tracks package sources and packages and provides a placeholder for some meta information.  To add more packages, see the section below on [adding packages](#adding-packages).

##### The `vendor` directory

In addition to the `percy.json` file, initialization should have created a `vendor` directory along with a file called `index.percy.json`.  This file contains a list of the resolved URLs for all packages available with your current configuration.

#### Installing Dependencies (from a lock file)

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
  https://codeberg.org/mininim/core:
    0.0.0-branch.main
    0.0.1
  https:/codeberg.org/mininim/cli:
    0.0.0-branch.main
    0.0.1
  https://github.com/euantorano/semver.nim:
    1.2.3
    1.2.2
    1.2.1
    1.2.0
```

This report shows usable versions which have not been excluded by top-level project requirements and is prior to solving (which again doesn't actually really solve anything right now).

> **NOTE:** Installation will always install from a `percy.lock` file if one exists.  If not it is effectively equivalent to a `percy update -n` which will pull the newest versions matching your `.nimble` requirements and write the lock file.

#### Updating Dependencies

To update your dependencies you can run:

```bash
percy update
```

This command will ignore the `percy.lock` file and pull the latest compatible versions of your dependencies based on your requirement.  It will additionally install any newly required or delete any removed dependencies.

It's **important** to note, however, this will only fetch newer versions or more recent heads from remote repositories if your local cache has gone stale (after an hour or so).  If you're trying to update to versions which are newer in the remote repository, add the `-n` flag:

```bash
percy update -n
```

> **NOTE**: Percy is designed to provide more seamless development _within_ your `vendor` directory.  Accordingly, it takes great care not to destroy things there.  You may see `Skip` warnings during the installation or update process.  This generally indicates that your `vendor` directory is in an unclean state.  You should check the indicated directories based on the error and clean them up manually or, if you know there's nothing important:
>
> `percy update -nf`
>
> The addition of the `-f` flag will force resolution of paths.

##### Locking

The `percy.lock` file is automatically written after a successful update.  If for whatever reason your build is not functional you should simply discard its changes via your VCS.  There is no explicit `lock` command.

#### Adding Packages

Percy resolves all known dependency/requirement names to their URL.  In order to lookup a package's URL by its name, it needs to be in either a configured package repository (what we call a **_source_**) or as an individual **_package_**.  URL based dependencies/requirements should just work.

A default initialization will always include the official Nim language package repository at (https://github.com/nim-lang/packages) in your `percy.json`.  This should allow most well-known packages to resolve by name out of the box:

```json
{
  "meta": {},
  "sources": {
    "nim-lang": "gh://nim-lang/packages"
  },
  "packages": {}
}
```

If you want to be more explicit, you can reset your configuration to empty via:

```bash
percy init -r
```

> **NOTE**: This will reset the entire configuration and remove any other additions you have made.

To add more packages by name, you'll need to add either a _source_ or a _package_.  You can also create your own sources quite easily, share them publicly as curated lists or keep them in a private git repository for internal of private packages.

##### Sources

You can add a source via:

```bash
percy set source <name> <url>
```

The `<url>` must point to a git repository containing a `packages.json` file in its root that is schema-compatible with the one found in `nim-lang/packages`.  Note, however, the only two required fields are `name` and `url` .  As an example, let's take a look at the [Mininim](https://github.com/primd-cooperative/mininim) framework's package repository's file, located [here](https://github.com/primd-cooperative/mininim-packages/blob/main/packages.json).  Note it only the two fields are added:

```json
[
	{
        "name": "mininim/core",
        "url": "cb://mininim/core"
    },
    ...
]
```

To add the official mininim repository to your own Percy configuration, you would execute:

```bash
percy set source mininim cb://mininim/packages
```

If you wanted to remove it:

```bash
percy unset source mininim
```

> Note:  The example above to add the mininim repository uses `gh://` forge-style URLs.  You are **not** required to use this style of URL, and standard `https://` or even `git@`-style addresses should be viable, although in our experience `https://` is significantly faster than git over SSH.  Forge style URLs and even `git@`-style URLs are always resolved to their _actual_ URL internally, e.g. `https://github.com/...` and `git+ssh://...` styles.
>
> Forge style currently supports:
>
> - `gh://` or `github://` for GitHub 
> - `gl://` or `gitlab://` for GitLab
> - `cb://` or `codeberg://` for Codeberg 

##### Packages

Adding individual packages is also possible via the `set` command.  The only distinction here is that instead of pointing at a repository that contains a `packages.json` file, you're pointing the package name directly at the git repository.

```bash
percy set package neo https://github.com/xTrayambak/neo.git
```

> **NOTE:**  When packages added via the `set package` command or as part of a source repository added with `set source` have a conflicting name, the latter defined URL is _always used_ and with package URLs overwriting URLs provided by sources.

In the example above, `neo` would now refer to to the URL provided in the example, instead of the one defined in the nim official repository.  The recommended approach is to retain the nim official repository as your first source, add sources after which constitute private repositories and/or overloads to the official, while using package entries to resolve any conflicts.  Also **stop** using short package names.

##### Additional Notes on Naming Packages

Because of the way Percy resolves package names (and because they no longer need to be valid identifiers in Nim), you can actually have packages with any name.  It should be noted, however, that if you do this, adding named packages to your `.nimble` files will obviously break any compatibility with other package manager.  For example it is completely possible to do the following:

```bash
percy set package mininim/core gh://myfork/mininim-core
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

## Nimble File Support

Percy uses a naive Nimble file parser and mapper which supports common fields that define project structure, e.g. `binDir`, `srcDir`, etc to enable the `nim build` task when initialized with `percy init -w`.  Main exceptions to this at this time is is the `namedBin` field and `paths`.

> **NOTE**: For any line that Percy does not know how to interpret, it simply leaves it alone.

### Requirements

Additionally, it obviously supports the `requires` keyword.  In the case of conditional requires such as the following, Percy constructs a space sensitive map of the file to remember their positions:

```nim
when defined windows:
    requires ...
```

It **should be noted**, however, that it does not take into account these conditions when determining which packages to install.  All requires will be used to determine the dependency graph, which means all dependencies may be installed irrespective of conditions.  Obviously whether or not they're used is up to your code.  While this may be sub-optimal, it's a good middle-ground solution whic:

1. Does not necessitate more complex processing (or compiler based processing) of `.nimble` files
2. Ensures your existing `.nimble` file is not wholly mangled when using `percy require` to add a dependency.

There is still a question of how `percy remove` will be handled, but we will likely remove any matching `requires` and then scan for dangling conditions without a body and remove those.

### Version Constraints

Version constraints should be well supported along with the ability to add `|` to provide "or" operations, and `,` to provide "and" operations, for example:

```nim
requires "nim >=2.2.6 | >=2.2.0, <=2.2.4"
```

This is equivalent to:

Nim version greater than or equal *[gte]* to 2.2.6 ** or ** **(** *[gte]* 2.2.0 **and** _*[lte]* 2.2.4 **)**, effectively skipping 2.2.5.  In short, constraints are first split by `|` creating a sequence of "or" constraints, then each constraint therein is split by `,` creating a sequence of "and" constraints.  Internally these are called "Any" and "All".  Although not actually the code, you can roughly imagine something like the following pseudo-Nim (hah, punny) code:

```nim
type
	Constraint
		package: string
		condition: string
	AllConstraint
		items: seq[Constraint]
	AnyConstraint
		items: seq[AllConstraint]
```

Parenthesis to be more explicit are not yet supported though may be in the future with a `GroupConstraint` or something similar.  To understand more about what versions can actually look like and how they work, see the next section.

## Versioning

Versioning in Percy relies heavily on `semver` (https://github.com/euantorano/semver.nim).  There's some "alteration" and wrapping which is useful to understand because the library itself absolutely requires a `0.0.0`-style string.

#### Incomplete Versions

Versions which are incomplete will have `0`'s appended, e.g. `1.2` becomes `1.2.0` in Percy, however using a single number is not supported, e.g. `1` cannot become `1.0.0` because 1 is ambiguous and may be used in other parts.  Like if you tag something as:  `test-1`.  Accordingly, you should stick to at least 2 numbers for best results.

#### Branch Support

It's also possible to track a branch using a `#` style constraint:

```nim
requires "mypack#dev"
```

The logic for whether or not another version conflicts with a branch has yet to be determined, but when used at the top-level `.nimble` file this ensures the "usable" version of that package is tracked solely to the head of that branch in the remote repository.  Most likely resolution for logic is simply that a branch will yield no conflicts at all and will only be recommended for use at the top-level, which would enable, for example to add a development branch overload at the project level and have all other packages further down the tree simply accept it.

Branches in Percy are identified with a version that looks like `0.0.0-branch.[branch]` where `[brance]` is the name of the branch with most non-alpha-dash symbols replaced with a dash.  This is predominantly due to constraints placed on the version parsing by the `semver` package.  There is no way to get a "newer version" for the branch or a lesser version.

#### Build Support

Versioned build tags like `1.0.0-alpha` and `1.0.0-alpha.1` should be supported, although the logic for these is deferred to `semver`.  It's not clear how that library deconstruction and compares the build portion of the version, though we would hope that `-alpha.1` would be less than `-alpha.2` and greater than `-alpha`, alone, for example.

#### HEAD Support

The remote HEAD (regardless of which branch it maps to) is always included in the total available commits as `0.0.0-HEAD` when versions are not otherwise defined.

```nim
requires "package"
```

Whether or not raises a conflict with other requirements and in what circumstances is currently undefined but will be clarified later.  Use at your own risk (although we know it's probably very common).

#### Exclusion, Inclusion, and Precedence

Although the solver for Percy is not currently completed, the graph that is passed to it orders "usable" versions in roughly this manner if the match basic exclusion/inclusion requirements which are as follows:

1. All versions of a package which do not match top-level `.nimble` file `requires` constraints are excluded from the usable versions.
2. Those remaining and all subsequent versions which match any constraint across the entire graph are included in the usable versions.

The final usable versions takes on a form such as:

```nim
OrderedTable[Repository, OrderedSet[Commit]]
```

This is the `tracking` property on the `DepGraph` class and is what ultimately will be used by the solver to actually solve.  At the end of building the dependency graph, this tracking table is then ordered by the following logic (at present):

```nim
this.tracking = this.tracking.pairs.toSeq()
    .sortedByIt(it[1].len)
    .toOrderedTable()

for repository, commits in this.tracking:
    this.tracking[repository] = commits.toSeq()
        .sorted(
            proc (x, y: Commit): int {. closure .} =
                let
                    xIsBranch = x.version.build.startsWith("branch.")
                    yIsbranch = y.version.build.startsWith("branch.")
                if x.version.build == "HEAD":
                    result = 1
                elif y.version.build == "HEAD":
                    result = -1
                elif xIsBranch and yIsBranch:
                    result = cmp(x.version.build, y.version.build)
                elif xIsBranch:
                    result = 1
                elif yIsBranch:
                    result = -1
                else:
                    result = cmp(x.version, y.version)
            ,
            Descending
        )
        .toOrderedSet()
```

This basically means that repositories are first sorted by the total number of "usable" versions, and then their "usable" versions are sorted as:

1. HEAD 
2. Branches and other non-semver styled tags (Alphabetically)
3. Version numbers and corresponding build/meta info (Per the `semver` package) for all semver styled tags.

## More to Come

- Hooks
