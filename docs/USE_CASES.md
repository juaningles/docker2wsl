# Use cases and requirements

Status: draft 2, 2026-11-16. Draft 2 records the operator's decisions on five open questions
(section 9). This document states what the tool is for and what it must do. It
does not say how. It is the input to a redesign, so nothing here should be read as a description of
the current scripts except the "Today" column in section 5.

"The tool" means this project under its working name, docker2wsl. The name is expected to change
(section 9).

---

## 1. Purpose

The tool builds working environments from small, reusable parts and puts them on whatever
platform the user has.

- A **strap** is one unit of setup: install a toolchain, configure a shell, add a command-line tool.
- A **recipe** is a named pattern: a starting point plus an ordered group of straps and settings.
- A **target** is a place an environment can live: a WSL distribution, a container, a Kubernetes
  cluster, a Proxmox guest, a cloud instance.

The same recipe should give an equivalent environment on any target that can hold it. Rebuilding
should be one command, so bringing in a new tool or a newer version is routine. Recipes and straps
should be shareable, so a team builds the same thing, and regular enough that another program can
drive the tool without a person present.

**Environments are commodities: cheap and replaceable.** An environment is never updated in place.
The way to change one is to deploy a fresh one and discard the old. This is a founding idea of the
tool, not a limitation to be lifted later.

### In scope

- Building an environment from a recipe.
- Saving a built environment so it can be reused without building again.
- Deploying an environment onto a target, from a recipe or from a saved build.
- Rebuilding and updating.
- Writing, composing, sharing and discovering straps and recipes.
- Recording what every environment was built from.
- Starting and stopping an environment, as far as building, setting up, testing and replacing
  one require it (section 4.13).

### Out of scope

- Operating an environment day to day. The tool can start and stop what it built, but it does not
  own that process; users are expected to use the platform's own tools, or another product, to
  run and look after an environment in everyday use.
- Updating an environment in place.
- Running work inside an environment after it is deployed.
- Scheduling, scaling decisions, monitoring and cost tracking. A calling tool may do these; this
  tool gives it the operations to do them with.
- Storing or managing secrets. The tool has needs around secrets (section 4.11) but is not a
  secret store.
- Managing the platforms themselves (installing WSL, a container engine, a cluster, a hypervisor).

---

## 2. Terms

| Term | Meaning |
|---|---|
| **Strap** | A unit of setup that runs inside an environment while it is built or deployed. |
| **Recipe** | A named, saved pattern: a base, an ordered list of straps, and settings. |
| **Base** | What a build starts from, for example a stock operating system image. |
| **Target** | A kind of place an environment can be built or deployed (section 6). |
| **Platform** | The operating system family of the environment itself, for example Linux or Windows. |
| **Product** | The technology that holds the environment, for example WSL, a container engine, Kubernetes, Proxmox. |
| **Target tag** | A strap's statement of which platforms and products it works with. |
| **Build** | Turning a recipe into an environment. |
| **Saved build** | A built environment kept in a reusable form, so more can be made without building again. |
| **Instance** | One running or runnable environment on a target. |
| **Deploy** | Creating an instance on a target, from a recipe or from a saved build. |
| **Collection** | A folder or repository of straps and recipes: the public ones, a team's, a person's. |
| **Build record** | What the tool writes down about a build: inputs, versions, outcome. |

---

## 3. Actors

### 3.1 The solo developer

One person looking after their own environments, usually on one or two machines, often with
whatever platform their employer or their hardware gives them.

- **Wants:** a development environment that matches a pattern they chose, on the platform they
  have today, and the same pattern on a different platform tomorrow.
- **Cares about:** speed from nothing to a usable shell; not having to remember a long command;
  being able to throw an environment away and get it back; picking up new tools and versions
  without a day of setup.
- **Typical moments:** a new laptop; a broken environment; a new project that needs another
  toolchain; a tool they use has a new version; a move from one platform to another.
- **Brings:** personal preferences (shell, prompt, aliases) and personal identity (keys, logins)
  that must not end up in anything shared.
- **Success:** "I ran one command and I am working again, and I know what is in this environment."

### 3.2 The team

A group that wants everyone, and their automation, on the same built environments. Within it,
some people maintain the team's straps and recipes and most people only consume them.

- **Wants:** one definition of "our environment" that every member builds from; a place to add the
  team's own tooling beside the public straps; a way to roll a change out to everyone.
- **Cares about:** two members' environments being the same when built from the same recipe;
  onboarding a new member quickly; knowing which version of the team recipe someone is on;
  keeping team-internal tooling private; letting a member add personal touches without forking
  the team's recipe.
- **Typical moments:** a new joiner; a toolchain upgrade across the team; "it works in my
  environment" disputes; an audit of what is installed where.
- **Brings:** private collections, mixed platforms across members (Windows with WSL, macOS,
  Linux), and shared infrastructure (a registry, a cluster, a hypervisor).
- **Success:** "A new joiner had our standard environment on day one, and I can prove what is in it."

### 3.3 The automated caller

A program that uses the tool with no person watching: an orchestration tool, an AI agent workflow,
a continuous-integration job. It builds, saves and deploys environments as modular parts of a
larger solution, sometimes many at a time.

- **Wants:** to ask "does a build of this recipe already exist?", build it if not, and deploy as
  many instances as the work needs, on the targets it has been given.
- **Cares about:** never being asked a question; results it can parse; errors it can tell apart;
  the same request giving the same result; not rebuilding what already exists; being able to
  build and deploy several things at once; instances that carry no identity until the caller
  gives them one.
- **Typical moments:** a workflow needs five identical workers; a recipe changed and the saved
  build is stale; an instance is no longer needed; a build fails halfway and must be cleaned up.
- **Brings:** its own state and scheduling. It treats the tool as a dependable component.
- **Success:** "The call returned a result I could act on, every time, without a person."

---

## 4. Use cases

Each use case lists its actors, the goal, the main flow, variations and what can go wrong. Flows
describe what the user does and gets, not how the tool does it.

### 4.1 Build an environment from a recipe

**Actors:** all. **Goal:** go from a recipe name to a usable environment on a chosen target.

Main flow:
1. The user names a recipe and, if they wish, a target and a name for the result.
2. The tool shows what it is about to do.
3. The tool obtains the base, creates the environment and runs the recipe's straps in order.
4. The tool reports the result and how to start using the environment.

Variations:
- No recipe: the user gives a base and a list of straps directly.
- The user overrides parts of the recipe for this build only (name, user, extra straps, target).
- A default target is chosen from what is available on the machine.

What can go wrong:
- The base cannot be obtained; the target is unavailable; a name is already taken.
- A strap fails. The user needs to know which one, at which command, and what state was left.
- The build is interrupted. Nothing half-built should be mistaken for a finished environment.

### 4.2 Rebuild to bring in new tools and versions

**Actors:** solo developer, team. **Goal:** make an existing environment current.

Main flow:
1. The user asks to rebuild an environment by name.
2. The tool builds a fresh one from the same recipe, as it stands now, and replaces the old one.
3. The tool reports what changed compared with the previous build.

A rebuild is always a fresh environment. There is no update in place (section 1).

Variations:
- The recipe itself changed (a strap added or removed).
- Only versions changed (the same straps now install newer tools).
- The user wants the old environment kept until the new one is proven.
- The user wants to repeat an earlier build exactly, not pick up newer versions.

What can go wrong:
- Work that lived only inside the old environment is lost. The user needs to know beforehand
  what a rebuild discards and what it keeps. Data meant to outlive an environment belongs outside
  it (section 4.14).
- The new build fails and the old one is already gone.

### 4.3 Put the same pattern on a different target

**Actors:** all. **Goal:** use one recipe on whichever platform is available.

Main flow:
1. The user builds a recipe on one target.
2. Later, or on another machine, the user builds the same recipe on a different target.
3. Both environments contain the same tools, configured the same way.

Variations:
- A strap makes no sense on one target. It is skipped there, and the user is told.
- A strap needs something only one target has. The user learns this before the build, not during.
- The target is on another machine from the one the tool runs on.

What can go wrong:
- A recipe silently produces a lesser environment on one target. Differences must be visible.

### 4.4 Write a strap

**Actors:** solo developer, team maintainer. **Goal:** package one piece of setup for reuse.

Main flow:
1. The author writes the setup steps once.
2. The author tries the strap alone against a throwaway environment.
3. The author adds it to a collection, where recipes can name it.

Variations:
- The strap runs with full privileges, or as the environment's ordinary user.
- The strap takes settings (a version to install, a choice of variant).
- The strap depends on another strap having run first.
- The strap carries target tags: the platforms and products it works with. The tool uses them as
  guardrails, so a strap is never run where it does not belong.
- A strap exists in more than one version under one name, for example one for a Linux target and
  one for a Windows target, and the tool picks the one whose tags match.
- The strap is meant for a saved build, or for each instance at deploy time (4.8, 4.9).

What can go wrong:
- The strap works on the author's platform and breaks on another. Authors need one set of rules
  that holds everywhere, and a way to test against more than one target.
- The strap waits for input and the build hangs.

### 4.5 Write and compose a recipe

**Actors:** all. **Goal:** capture a pattern so it can be built by name.

Main flow:
1. The author chooses a base and an ordered group of straps and settings.
2. The author saves it under a name in a collection.
3. Anyone with that collection can build it by name.

Variations:
- A recipe starts from another recipe and adds or changes a little ("the team recipe, plus my
  shell").
- A recipe is checked for mistakes without building it.
- A recipe is turned into a build record's exact inputs, and a build record back into a recipe.
- An automated caller generates a recipe, or supplies one that is not stored in any collection.

What can go wrong:
- Two collections define the same name. Which one wins must be predictable and visible.
- A recipe names a strap that cannot be found, or that conflicts with another.

### 4.6 Share straps and recipes in a team

**Actors:** team. **Goal:** everyone builds from the same definitions.

Main flow:
1. A maintainer publishes straps and recipes to the team's collection.
2. Members obtain the collection and build the team's recipes by name.
3. A maintainer changes a recipe; members rebuild and are on the new version.

Variations:
- Public, team and personal collections are used together, layered, with personal last.
- A member adds personal straps on top without changing the team's recipe.
- A member checks whether their environment matches the team's current recipe.
- A team pins a recipe to fixed versions so that builds made weeks apart are the same.
- The current recipes are whatever is committed in the team's shared repository. A member or a
  caller asks for the collection as it was at a named commit, which is the team's way of saying
  "this version".

What can go wrong:
- Members are on different versions of the collection without knowing.
- Something private to one member or team leaks into a shared recipe or a shared build.

### 4.7 Know what an environment was built from

**Actors:** all. **Goal:** answer "what is this, and how was it made?" for any environment.

Main flow:
1. The user asks an environment, or the tool, for its build record.
2. The record shows the recipe, base, every strap and its version, when and where it was built,
   and whether the build succeeded.

Variations:
- The record is read without starting the environment.
- The record is read by a program.
- Two records are compared.
- The record is used to build the same environment again.

What can go wrong:
- The environment was changed by hand after the build. The record cannot know; this limit must be
  stated plainly.

### 4.8 Build once, save, and reuse

**Actors:** all, most of all the automated caller. **Goal:** pay the build time once.

Main flow:
1. The user builds a recipe and asks for the result to be saved.
2. Later, the user asks whether a saved build of that recipe exists.
3. If it does, it is used. If not, it is built and saved.

Variations:
- "Exists" means "built from exactly these inputs", so a changed strap or base is a miss, never a
  stale hit.
- The saved build is kept on one machine, or somewhere a team or a cluster can fetch it.
- Old saved builds are listed and removed.
- Each target has its own saved form; the user asks for the one their target needs.

What can go wrong:
- A saved build contains something that should differ per instance or must not be shared.
- Two callers build the same thing at once.

### 4.9 Deploy instances from a saved build

**Actors:** all. **Goal:** get one or many instances quickly.

Main flow:
1. The user names a saved build, a target and an instance name.
2. The tool creates the instance and runs any setup that belongs to each instance.
3. The tool reports the instance and how to reach it.

Variations:
- Many instances from one saved build.
- Per-instance settings: a name, a user, storage that outlives the instance.
- The instance is described by a template the user supplies for that target.
- The user removes an instance, or replaces it with one from a newer saved build while keeping
  its stored data.
- The user asks which instances exist and what each was made from.

What can go wrong:
- The deploy half-succeeds and leaves something behind.
- Instance setup fails after the instance exists.

### 4.10 Drive the tool from another program

**Actors:** automated caller. **Goal:** use every operation above with no person present.

Main flow:
1. The caller asks a question (does this exist, what would this do) or requests an action.
2. The tool answers in a form the caller can parse, and never waits for input.
3. The caller decides what to do next from the answer.

Variations:
- The caller repeats a request; the second call does no harm and reports the same state.
- The caller runs several builds or deploys at the same time.
- The caller cancels an operation and asks the tool to clean up.
- The caller needs progress while a long build runs.

What can go wrong:
- An operation hangs. Every operation needs a bound.
- An error is reported only as text meant for a person.

### 4.11 Give an environment its secrets and identity

**Actors:** all. **Goal:** an environment can authenticate where it needs to, without secrets
spreading. This section records needs only; the mechanism is undecided.

Needs:
1. Secrets and identity never end up in a saved build, a shared recipe or a shared collection.
2. They are supplied to an instance, not to a build, and can differ for every instance.
3. A recipe can declare what an instance will need, without containing it, so a user or caller
   knows before deploying.
4. A person can supply them interactively; an automated caller can supply them with no prompt.
5. They do not appear in the build record, in output, in logs, or in any copy of the steps the
   tool keeps.
6. The tool refuses to read a secret from a source that is open to other users, and says why.
7. A secret can be replaced or withdrawn without rebuilding.
8. An instance can be created with no identity at all.
9. The tool can show which instances were given which kind of secret, without showing the secret.

### 4.12 Look before building

**Actors:** all. **Goal:** find out what is available and what a command would do.

Main flow:
1. The user lists recipes, straps, targets available on this machine, saved builds or instances.
2. The user asks for a preview of a build or deploy and sees every step, with nothing changed.

Variations:
- The listing says where each item comes from (which collection).
- The preview is given to a program.
- The user asks what a strap does before using it.

### 4.13 Start, stop and test an environment

**Actors:** all. **Goal:** bring an environment up or down when building, setting up, testing or
replacing it needs that. The tool is able to do these things; it is not where users go to operate
an environment every day.

Main flow:
1. The user or the tool starts an environment the tool built.
2. Setup that runs as the environment's user is run in it, or the user tests that it works.
3. The user or the tool stops it.

Variations:
- An existing environment is stopped so that it can be replaced, when the user asks for
  replacement.
- A build leaves the environment running, or stopped, as the user chooses.
- The user asks whether an environment is running.

What can go wrong:
- The environment will not start after a build. The user needs the reason, not only a failure.
- Stopping loses work in progress. Replacement must be asked for, never assumed.

### 4.14 Keep data that outlives an environment

**Actors:** all. **Goal:** because environments are replaced, not updated, anything worth keeping
lives outside them and is connected again after each deployment.

Now:
1. A strap connects the environment to storage that already exists outside it. For example, a
   strap for a WSL environment links a folder in the user's home to a shared drive on the
   Windows side.
2. After a rebuild the same strap makes the same connection.

Later:
1. A recipe states what storage the environment needs, in terms that name no target.
2. The tool fulfils that request in whatever way each target provides: a link to a shared drive,
   a container volume, cluster storage, and so on.

What can go wrong:
- The storage is missing or belongs to another environment.
- A strap written for one target's kind of storage is used on another. Target tags (4.4) guard
  against this until the tool handles storage itself.

---

## 5. Requirements

Derived from section 4. "Today" says whether the current scripts meet the requirement on
2026-11-16: **yes**, **partly** or **no**. It is there to size the redesign, not to constrain it.

Basis for "Today": the test suites are taken as the statement of what works. **yes** means a test
exercises it, in `tests\test_01` to `test_08` (Windows runner, mocked) or `tests/sh/run.sh` and
`tests/sh/real.sh` (macOS and Linux runner). **partly** means tests cover some of it, or only one
runner, or it is documented but untested; section 5.10 gives the reason for each. **no** means
nothing in the tests or the documentation provides it.

### 5.1 Recipes and straps

| ID | Requirement | From | Today |
|---|---|---|---|
| R1 | A recipe can be built by name with one short command. | 4.1 | yes |
| R2 | Any recipe setting can be overridden for a single build. | 4.1 | yes |
| R3 | A build can be made without a recipe, from a base and straps given directly. | 4.1 | yes |
| R4 | Straps run in a stated order, either privileged or as the environment's user. | 4.4 | yes |
| R5 | A strap can take settings. | 4.4 | partly |
| R6 | A strap carries target tags (platforms and products it works with) and can name other straps it needs. | 4.3, 4.4 | no |
| R7 | A strap can declare whether it belongs in a saved build or runs per instance. | 4.4, 4.8 | no |
| R8 | One set of authoring rules holds for every target and every platform the tool runs on. | 4.4 | partly |
| R9 | A strap can be run alone against a throwaway environment. | 4.4 | partly |
| R10 | A recipe can extend another recipe. | 4.5 | no |
| R11 | A recipe can be checked without building. | 4.5, 4.12 | yes |
| R12 | A recipe can pin versions so that later builds are the same. | 4.2, 4.6 | no |
| R13 | A strap never waits for input. | 4.4, 4.10 | yes |

### 5.2 Collections and sharing

| ID | Requirement | From | Today |
|---|---|---|---|
| R14 | Public, team and personal collections can be used together. | 4.6 | yes |
| R15 | When names collide, the winner is predictable and shown. | 4.5 | yes |
| R16 | A collection can be private. | 4.6 | yes |
| R17 | A member can tell whether an environment matches the current recipe. | 4.6 | no |
| R18 | Recipes, straps, targets, saved builds and instances can be listed, with their source. | 4.12 | partly |

### 5.3 Building and rebuilding

| ID | Requirement | From | Today |
|---|---|---|---|
| R19 | The same recipe gives an equivalent environment on every target that supports it. | 4.3 | yes |
| R20 | A strap whose tags do not match the target is never run there; this is visible, and known before the build. | 4.3, 4.4 | partly |
| R21 | A build can run against a target on another machine. | 4.3 | partly |
| R22 | A failed build names the strap and step, and is never left looking finished. | 4.1 | partly |
| R23 | An environment can be rebuilt by name. | 4.2 | yes |
| R24 | A rebuild states beforehand what it discards and what it keeps. | 4.2 | no |
| R25 | A rebuild can keep the old environment until the new one succeeds. | 4.2 | no |
| R26 | A rebuild reports what changed. | 4.2 | no |
| R27 | A preview shows every step and changes nothing. | 4.12 | yes |

### 5.4 Saved builds and deployment

| ID | Requirement | From | Today |
|---|---|---|---|
| R28 | A built environment can be saved in the form each target needs. | 4.8 | partly |
| R29 | A saved build is identified by its inputs, so a changed input is never a stale match. | 4.8 | no |
| R30 | The tool can answer whether a saved build for given inputs exists. | 4.8 | no |
| R31 | A saved build can be stored where others, or a target, can fetch it. | 4.8 | no |
| R32 | Saved builds can be listed and removed. | 4.8 | no |
| R33 | An instance can be deployed from a saved build without building. | 4.9 | partly |
| R34 | Per-instance setup runs at deploy and is never part of a saved build. | 4.9 | no |
| R35 | Many instances can come from one saved build. | 4.9 | partly |
| R36 | An instance can be removed, or replaced while keeping its stored data. | 4.9 | partly |
| R37 | The shape of an instance on a target can be supplied by the user as a template. | 4.9 | no |

### 5.5 Build records

| ID | Requirement | From | Today |
|---|---|---|---|
| R38 | Every build writes a record of its inputs, versions, place, time and outcome. | 4.7 | yes |
| R39 | The record is readable inside the environment and without starting it. | 4.7 | yes |
| R40 | The record is readable by a program. | 4.7 | yes |
| R41 | Two records can be compared. | 4.7 | no |
| R42 | A record can be used to build the same environment again. | 4.7 | partly |
| R43 | Each instance records which saved build it came from. | 4.9 | no |

### 5.6 Automation

| ID | Requirement | From | Today |
|---|---|---|---|
| R44 | Every operation can run with no person present. | 4.10 | partly |
| R45 | Every operation can give its result in a form a program can parse. | 4.10 | no |
| R46 | Failures are distinguishable by kind without reading prose. | 4.10 | no |
| R47 | Repeating a request is safe and reports the same state. | 4.10 | partly |
| R48 | Several operations can run at once without interfering. | 4.10 | partly |
| R49 | Every operation is bounded in time and can be cancelled and cleaned up. | 4.10 | no |
| R50 | A long operation reports progress. | 4.10 | partly |

### 5.7 Secrets and identity

The nine needs of section 4.11 are requirements R51 to R59, in the same order. Today: R56 is
**yes** (both suites test that a key source open to others is refused). R54 is **partly** (keys are
copied from a private collection with no prompt, but nothing covers other kinds of secret). The
rest are **no**; R51 holds only when the user chooses not to save a build that ran an identity
strap.

### 5.8 Platforms

| ID | Requirement | From | Today |
|---|---|---|---|
| R60 | The tool runs on Windows, macOS and Linux as first-class platforms. | 3.1, 3.2 | partly |
| R61 | The same commands, recipes and straps behave the same on each platform it runs on. | 3.2 | partly |
| R62 | The tool needs little beyond the platform and the target's own software. | 3.1 | yes |
| R63 | Behaviour is covered by tests that need no real target, plus real runs per target. | 4.4 | yes |

Windows is first-class because WSL is a main target. Today the Windows runner and the macOS and
Linux runner are separate programs kept in step by a written contract, and each supports targets
the other does not.

### 5.9 Lifecycle, storage, versions and variants

Added in draft 2 from the decisions in section 9.

| ID | Requirement | From | Today |
|---|---|---|---|
| R64 | The tool can start and stop an environment it built, and say whether it is running. | 4.13 | partly |
| R65 | The tool can start an environment in order to run user-level setup in it or to test it. | 4.13 | partly |
| R66 | An existing environment is stopped and replaced only when replacement is asked for. | 4.13, 4.2 | yes |
| R67 | An environment is never updated in place; a change is always a fresh deployment. | 4.2 | yes |
| R68 | A strap can connect an environment to storage that outlives it. | 4.14 | partly |
| R69 | Later: a recipe states storage needs without naming a target, and each target fulfils them. | 4.14 | no |
| R70 | A collection can be requested as it was at a named commit. | 4.6 | no |
| R71 | The build record states the commit of every collection used. | 4.6, 4.7 | yes |
| R72 | Several versions of a strap can share one name, and the one whose tags match the target is used. | 4.4 | partly |
| R73 | Nothing in the tool assumes every environment is Linux, so other platforms can be added. | 4.4 | no |

### 5.10 Why each "partly"

| ID | What the tests show | What is missing |
|---|---|---|
| R5 | Straps honour settings given as environment variables on the building machine. | Settings cannot be written in a recipe. |
| R8 | Both runners render straps the same way, and a test compares them. | The Windows runner adds its own authoring limits on certain characters. |
| R9 | A build with one strap and a stock base is tested. | No command exists for trying a strap on its own. |
| R18 | Recipes are listed with their collection and base. | No listing of straps, targets, saved builds or instances. |
| R20 | Straps that do not apply skip themselves with a message during the build, by their own checks. | No tags, so nothing is known before the build and nothing stops a strap that lacks its own check. |
| R21 | Not tested. The documentation describes one working arrangement with shared paths. | A general way to build on another machine. |
| R22 | A failed strap is named, the exit is non-zero and the record says failed. | The failing command is not named, and the half-built environment stays in place. |
| R28 | A container build is saved as an image on all three engines. | No saved form for a WSL build. |
| R33 | A saved image can be used as the base of a new build with no straps. | No deploy operation as such, and no test of this path. |
| R35 | The same build can be repeated under different names. | Each repeat is a full build unless the base is a saved image. |
| R36 | An existing environment is refused, or replaced when asked. | Nothing keeps data across a replacement. |
| R42 | The record holds the command line, recipe and versions of every input. | Nothing turns a record back into a build. |
| R44 | Straps get no input, and the macOS and Linux runner never prompts. | The Windows runner needs an elevated prompt and has no unattended test. |
| R47 | A repeated build is refused unless replacement is asked for. | A repeat reports an error, not the existing state. |
| R48 | Each build uses its own temporary folder. | No test runs two builds at once. |
| R50 | Numbered steps are printed as a build proceeds. | Nothing a program can follow. |
| R64 | A container build is left running; a WSL build is restarted during setup; replacement stops the old one. | No start, stop or status operation the user can call. |
| R65 | Every build starts the environment and runs user-level straps in it. | It cannot be done for an environment that already exists. |
| R68 | Straps may run any command, and a WSL environment sees the Windows drives. | No strap or test does this, and a container's connections to the host are not part of a saved build. |
| R72 | Some straps hold two versions in one file and choose by their own checks (package manager, target). | No separate versions under one name, and no selection by the tool. |
| R60, R61 | Both runners share straps, recipes and the build record, each with its own suite. | They are separate programs, and each supports targets and options the other lacks. |

---

## 6. Targets and phasing

All six are in scope. The order is a proposal.

| Target | Build | Save | Deploy | Proposed phase | Today |
|---|---|---|---|---|---|
| WSL distribution | yes | yes | yes | 1 | build only |
| Local container (several engines) | yes | yes | yes | 1 | build and save |
| Kubernetes | from a saved build | to a registry | yes | 2 | no |
| Proxmox container | yes | yes | yes | 2 | no |
| Proxmox virtual machine | yes | yes | yes | 3 | no |
| Cloud instance | yes | yes | yes | 3 | no |

A target added later must not require changes to existing straps or recipes.

---

## 7. Qualities

- **Simple first use.** One command and no configuration gives a working environment.
- **Predictable.** The same inputs give the same result; differences between targets are stated.
- **Transparent.** The user can always see what will run and what did run.
- **Modular.** Straps are small and independent; recipes are compositions; targets are additions.
- **Safe by default.** Nothing existing is replaced, and nothing private is shared, unless asked.
- **Recoverable.** A failure leaves a state the user can understand and clean up.
- **Replaceable.** Any environment can be discarded and deployed again without loss, because
  nothing of lasting value lives only inside it.

---

## 8. Assumptions

- Environments are Linux for now. Windows environments are possible later, since Windows images
  exist; target tags (R6, R72, R73) are what keeps that door open.
- The user has, or is given, the right to create things on the target.
- A target's own software (WSL, a container engine, a cluster, a hypervisor) is already installed.
- An environment that was changed by hand after its build is the user's responsibility.

---

## 9. Decisions and open questions

### Decided by the operator, 2026-11-16

1. **Where deploy ends.** The tool must be able to start and stop an environment: to test it, to
   run user-level setup, and to stop an existing one when replacing it. It does not own day-to-day
   operation; users use something else for that. See 4.13, R64 to R66.
2. **No updating in place.** Updating through a fresh deployment is part of the reason the tool
   exists. Environments are cheap and replaceable. See section 1, R67.
3. **Data that outlives an environment.** For now, straps take care of it. In a later version the
   tool takes a target-neutral storage request and fulfils it per target. See 4.14, R68, R69.
4. **Versioning of collections.** Assume the current recipes are those committed in a shared
   repository. Being able to request a collection at a commit is enough for now. See R70, R71.
5. **Non-Linux environments.** Linux only for now, with Windows possible later. Straps must be
   tagged with the platforms and products they work with, as guardrails and as the way to hold
   several versions of one strap. See R6, R20, R72, R73.

### Still open

1. **The name.** "docker2wsl" describes one path out of many.
2. **Distribution.** How the tool itself is installed and updated on each platform.
3. **Tag vocabulary.** The list of platform and product names that target tags use, and who may
   add to it.
4. **Start and stop on shared targets.** Whether stopping means the same thing on every target,
   given that some discard everything outside persistent storage when stopped.
