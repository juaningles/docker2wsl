# Use cases and requirements

Status: draft 4, 2026-11-16. Draft 2 recorded the operator's decisions on five open questions
(section 9). Draft 3 added the developer's workbench (4.15, R74 to R76) and named the container
engines (section 6). Draft 4 adds use cases 4.16 to 4.33 and requirements R77 to R102, covering
collection maintenance, trust, rollback, housekeeping, architecture, shared machines, team audit,
composition, the tool's own lifecycle and host diagnosis, and records three further decisions
(section 9). Needs that a base image, a strap, a recipe setting or a deploy template can meet are
not in this document; they are collected in [MODULAR_CONCEPTS.md](MODULAR_CONCEPTS.md), and only
the prerequisites the tool must provide for them appear here (section 5.12).

This document states what the tool is for and what it must do. It
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

### Met by parts, not by the tool

Some needs are real but belong to a base image, a strap, a recipe setting or a deploy template:
a corporate proxy and certificate, an offline mirror, an SSH server for an editor, drivers for a
GPU. The tool's job is to run those parts well. They are described, with example uses, in
[MODULAR_CONCEPTS.md](MODULAR_CONCEPTS.md). Where one of them needs something only the tool can
provide, that prerequisite is a requirement here (5.12).

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
- **Use case that ties these together:** 4.15.

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

### 4.15 Keep a separate environment for each kind of work

**Actors:** solo developer, team. **Goal:** have the right group of tools for the work at hand,
with nothing to look after between uses.

A developer's work changes from day to day: a data pipeline this week, a web service the next, a
one-off experiment in between. Each needs its own group of tools, and the groups should not be
mixed into one ever-growing environment. Each group is a recipe. The developer keeps a short
list of the environments they use, and runs the tool to (re)build whichever one the day needs.

Main flow:
1. The developer keeps a list of environments: a name, a recipe and a target for each.
2. When a kind of work comes up, the developer runs the tool to build or rebuild that
   environment, on the target they have on this machine (WSL, a local container engine, or a
   cluster).
3. The developer works in it. When the work is done, or the environment is stale or broken, they
   discard it. Nothing of lasting value was inside it (4.14), so nothing is lost.
4. Next time, step 2 again. The rebuilt environment has the current versions of the same tools.

Variations:
- Several environments exist side by side on one target, one per kind of work, and the
  developer moves between them.
- A new machine: the developer rebuilds every environment on the list in one command.
- A throwaway: an environment built for one task and removed at the end of it, never kept.
- The same list is used on a machine with a different target. Each environment lands on the
  target available there (4.3).
- The list is kept beside the developer's own straps and recipes, in a personal collection
  (4.6), and the rebuild is run on a schedule or by another program (4.10).

What can go wrong:
- Two environments built from different recipes collide on a name or a shared resource.
- A rebuild of one environment on the list fails and the others are left in doubt. The user needs
  to know which succeeded, which failed and which were not attempted.
- Removing an environment takes something that outlived it. Removal must say what it takes.

### 4.16 Test a collection before publishing

**Actors:** team maintainer, automated caller. **Goal:** a change to a collection is known to build
on every target it claims before members see it.

Main flow:
1. A maintainer changes a strap or recipe and proposes it to the team's repository.
2. A program runs the tool to build each affected recipe on each target it claims, and each
   changed strap alone against a throwaway environment (4.4).
3. The change is accepted only if every build succeeds. The maintainer sees which builds failed,
   at which strap, and why.

Variations:
- Only the recipes that use a changed strap are rebuilt.
- The same recipe is tried on more than one base.
- A solo developer runs the same check on their personal collection on one machine.
- The run leaves nothing behind: no environments, no saved builds, unless asked.

What can go wrong:
- A target the collection claims is not available where the check runs. That target must be
  reported as untested, never as passed.
- Test environments are left behind and collide with later runs.

### 4.17 Maintain a collection over time

**Actors:** team maintainer, solo developer. **Goal:** add, replace and retire straps and recipes
without breaking the people and programs that use them.

Main flow:
1. An author asks the tool for a new strap or recipe. The tool creates one in the required shape,
   with its metadata, target tags and a place for a check, so the author starts from something
   correct rather than a copy of a neighbour.
2. Later, the author marks a strap or recipe as superseded and names its replacement.
3. A build that uses a superseded item still works and says so, naming the replacement.
4. After a stated period the item is removed. A build that names it fails with the reason and
   the replacement.

Variations:
- An item is renamed and the old name becomes an alias for a time.
- A recipe is retired but build records that name it stay readable.

What can go wrong:
- A member's personal recipe names a retired strap, and they find out on a new laptop. The
  warning period is what gives them time.
- The warning is printed for a person and an automated caller never sees it. Warnings must be
  part of the parseable result (4.10).

### 4.18 Trust what runs

**Actors:** all, most of all the team. **Goal:** know what a strap will do and where it came from
before it runs with full privileges.

Main flow:
1. The user asks to see a strap: its source, its collection, the commit it came from, and what it
   declares (tags, settings, straps it needs, whether it runs privileged).
2. The user, or the team, names the collections they trust. The tool refuses straps from any
   other collection unless told otherwise for one build.
3. The tool verifies that a collection is what it claims to be, and the build record states what
   was verified and how.

Variations:
- An automated caller is given trusted collections only and can never override.
- A one-off exception for a build is recorded in that build's record.

What can go wrong:
- What the preview showed and what the build ran differ, because a file changed between. The
  record must identify the exact content that ran.
- A collection path is replaced on disk by something else with the same name.

### 4.19 Go back to an earlier build

**Actors:** all. **Goal:** the new environment is worse than the last; return to a known good one
quickly.

Main flow:
1. The user names the environment and an earlier build record or saved build.
2. The tool deploys that earlier build, replacing the current one and keeping storage that
   outlives it (4.14).
3. The tool states which build is now in place.

Variations:
- A saved build of the earlier version exists, so no build is needed.
- Only a record exists. The tool builds from it (4.7). If the record was not pinned, the result
  may differ from the original, and the user is told so beforehand.

What can go wrong:
- The earlier record names a version that can no longer be obtained.
- The user goes back and the current build's record is lost. Both must remain.

### 4.20 Inspect a failed build

**Actors:** solo developer, team maintainer. **Goal:** see the state a failing strap left behind.

Main flow:
1. A build fails at a strap.
2. The user asks that the half-built environment be kept, marked as failed.
3. The user starts it, looks around, fixes the strap and runs the build again.
4. The failed environment is removed by the user, or by housekeeping (4.23).

Variations:
- Keeping is the default for a person; discarding is the default for an automated caller.
- Only the log and the record are kept, not the environment.

What can go wrong:
- The failed environment is mistaken for a working one (4.1). It must be marked, and the
  marking must be visible wherever environments are listed.
- The retry collides with the kept failure on the same name.

### 4.21 Check whether a rebuild would change anything

**Actors:** all. **Goal:** know whether an environment is stale without building it.

Main flow:
1. The user asks whether an environment is current.
2. The tool compares the build record with the recipe as it stands now, the collections' current
   commits, the base, and, where it can know, the versions a rebuild would install.
3. The tool answers, for each input: unchanged, changed, or unknown.

Variations:
- The question is asked of the whole list of environments (4.15).
- A program asks and uses the answer to decide a rebuild.

What can go wrong:
- A strap installs "the latest" by its own logic, so the version cannot be known without running
  it. The tool must say unknown, never unchanged.

### 4.22 Expire a throwaway environment

**Actors:** automated caller, solo developer. **Goal:** an environment made for one task goes away
on its own.

Main flow:
1. The environment is created with a lifetime, or tied to the caller's session.
2. When the lifetime ends or the caller is gone, the tool removes the environment and keeps its
   record.
3. The removal states what was removed.

Variations:
- The lifetime is extended.
- Storage that outlives the environment (4.14) is kept.

What can go wrong:
- The environment is removed while still in use. Extending must be easy and removal announced.
- The tool was not running when the lifetime ended. The next run must remove it and say so.

### 4.23 Clean up what builds leave behind

**Actors:** all. **Goal:** reclaim space and remove leftovers with confidence.

Main flow:
1. The user asks what the tool holds on this machine: bases, download caches, temporary folders,
   failed builds, saved builds no environment uses, instances not on the user's list. Each has a
   size and an age.
2. The user chooses what to remove, or gives a rule (older than, unused by anything).
3. The tool removes it and reports the space freed.

Variations:
- A preview that removes nothing.
- A program runs it on a schedule.
- Only one target's leftovers.

What can go wrong:
- A base is removed while another build is using it.
- Storage that outlives an environment is removed. The tool must never take it without asking.

### 4.24 Give an instance limits and devices

**Actors:** all. **Goal:** an instance gets the processor, memory, disk and hardware its work needs,
stated once in terms that name no target.

Main flow:
1. The recipe, or the deploy request, states what the instance needs: limits, and devices such as
   a GPU or a USB device.
2. The tool fulfils the request in whatever way each target provides.
3. The tool reports what was granted. A need the target cannot meet is reported before the
   deploy, not discovered inside the environment.

Variations:
- A target meets a need only in part, for example a limit that applies to every environment on
  the host rather than this one. The tool says so.
- Drivers and libraries inside the environment are a strap (MODULAR_CONCEPTS.md); the tool's part
  ends at passing the device through.

What can go wrong:
- Less is granted than asked, silently.

### 4.25 Build for another processor architecture

**Actors:** all. **Goal:** the same recipe on amd64 and arm64 machines, with a saved build for each.

Main flow:
1. The user names the architecture, or the tool uses the host's.
2. Straps tagged for that architecture run; others are skipped and the user is told (4.3).
3. The saved build is identified by its architecture along with its other inputs, and the record
   states it.

Variations:
- A build for one architecture is run on a host of another through emulation, which is slower
  and must be stated.
- A cluster has nodes of both kinds and needs both saved builds.

What can go wrong:
- A saved build for the wrong architecture is deployed and fails to start.
- A strap downloads a binary for the host's architecture rather than the environment's.

### 4.26 Deploy several environments as one system

**Actors:** automated caller, team. **Goal:** a group of instances that belong together, for example
a database, a service and a worker, are deployed, named, connected and removed as one.

In scope by the operator's decision (section 9, decision 6). Single deploys (4.9) and the
parseable interface (4.10) remain the building blocks; this use case adds the grouping.

Main flow:
1. A system is described as a named group: which recipes or saved builds it is made of, how many
   of each, and how they reach each other, in terms that name no target.
2. The tool deploys the members on a target in the stated order, connects them, and runs each
   member's per-instance setup (4.9).
3. The tool reports the system: each member, how it is reached, and what it was made from.
4. The tool removes the system as one, keeping storage that outlives it (4.14).

Variations:
- One member is replaced with one from a newer saved build while the others keep running.
- The system is deployed on a different target and each member lands as that target provides.
- A program asks whether a system exists, which members are running, and what each came from.

What can go wrong:
- A member fails to deploy and the others are left running. The user needs to know which
  members exist, and removal of the partial system must be one command.
- Two systems collide on a member's name or a shared resource.
- A member is removed alone and the system is left inconsistent without a word.

### 4.27 Run without administrator rights

**Actors:** solo developer, team. **Goal:** build and deploy on a machine where the user cannot
elevate.

Main flow:
1. Before starting, the tool says which operations on this host and target need elevation, and
   why.
2. Where a target has an unprivileged path, for example a rootless engine, the tool uses it.
3. Where elevation cannot be avoided, it is asked for once, before the build, never silently in
   the middle of one.

What can go wrong:
- An unattended run hits an elevation prompt and hangs (4.10). Unattended means no elevation,
  or the run is refused up front.

### 4.28 Share a machine among several users

**Actors:** team. **Goal:** a build server or shared workstation where each user's environments,
saved builds and collections are their own.

Main flow:
1. Each user's instances and collections are listed and removed by that user alone. A shared
   cache of saved builds can be read by everyone.
2. Every record states who built.
3. Names do not collide across users.

What can go wrong:
- One user's private collection or secret can be read by another (4.11).
- Housekeeping (4.23) run by one user removes another's things.

### 4.29 Audit and remediate across the team

**Actors:** team. **Goal:** answer "what is installed where" for every environment the team has,
and act on the answer.

Main flow:
1. The records from every machine are gathered in one place. The tool emits them in a form a
   program can collect; where they are collected is the team's choice.
2. A maintainer asks which environments contain a given strap at a given version, were built from
   a given collection commit, or were built by a given tool version.
3. The maintainer asks for those environments to be rebuilt (4.2, 4.15) and sees each one's
   outcome.

Variations:
- A tool version with a known defect built some environments.
- An instance came from a saved build that has since been withdrawn.
- A member has left and their environments must be found.

What can go wrong:
- Records that were never gathered are not known. The answer must state its coverage.
- Changes made by hand are invisible (4.7).

### 4.30 Reproduce a colleague's environment

**Actors:** team. **Goal:** settle "it works in my environment" by building the identical thing.

Main flow:
1. A colleague shares their build record.
2. The tool builds from it on my target, fetching the collections at the commits the record
   names and the versions it pinned.
3. The tool compares my record with theirs and states every difference, and every input it could
   not compare.

What can go wrong:
- The record names a private collection I do not have.
- Versions that were not pinned have moved on, so the two are not identical. The comparison must
  show this rather than claim equality.

### 4.31 Build centrally and let members deploy

**Actors:** team, automated caller. **Goal:** pay for a build once on the team's pipeline; members
deploy from saved builds.

Main flow:
1. On each commit to the collection, a pipeline builds the affected recipes and saves them where
   the team can fetch them (4.8), identified by their inputs.
2. A member asks for a recipe. The tool finds the saved build for their target and architecture
   and deploys it (4.9), running per-instance setup.
3. If no saved build exists, the tool builds locally or refuses, as the team's setting says.

What can go wrong:
- The saved build contains something private (4.11).
- The store is unreachable and the tool silently builds locally. The fallback must be stated.

### 4.32 Install, update and keep the tool compatible

**Actors:** all. **Goal:** the tool itself is one command to install and one to update on each
platform, and recipes written for an earlier tool keep working or fail clearly.

Main flow:
1. The tool is installed with one command per platform, without administrator rights where the
   platform allows.
2. The tool is updated with one command. Every record states the tool version that built it.
3. A recipe or collection states the tool version it was written for. A newer tool builds it, or
   says precisely what must change. An older tool refuses and names the version it needs.

Variations:
- A team pins the tool version for everyone.
- An automated caller checks the version before relying on a behaviour.

What can go wrong:
- Behaviour changes between tool versions without a word. Changes to what a recipe means must be
  versioned.

### 4.33 Diagnose the host and recover the tool's state

**Actors:** all. **Goal:** when a target is missing or the tool is confused, the user gets a reason
and a way out.

Main flow:
1. The user asks for a check.
2. The tool reports each target as usable, or why not: WSL not enabled, an engine not running,
   no cluster credentials, no rights. It reports each collection as reachable, and at which
   commit.
3. The tool checks its own state: locks left by interrupted runs, records with no environment,
   environments with no record. It offers to repair each, and says what the repair does.

What can go wrong:
- A repair removes something real. Repairs must be previewed and never assumed.
- The check itself needs what is missing. It must degrade and still report.

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

Added in draft 2 from the decisions in section 9; R74 to R76 added in draft 3 from 4.15.

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
| R74 | Several environments, built from different recipes, can exist side by side on one target. | 4.15 | yes |
| R75 | A user-kept list of environments (name, recipe, target) can be built or rebuilt in one command, and the result names each one's outcome. | 4.15, 4.2 | no |
| R76 | Any environment the tool built can be removed by one command, and removal states what it takes with it. | 4.15, 4.2 | no |

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
| R82 | The record holds a content hash of every strap that ran and the commit of every collection. | Nothing verifies a collection against a stated identity before the build, and the record does not say what was verified. |
| R89 | The macOS and Linux runner takes an architecture flag and a recipe setting, both tested; both runners record the image's architecture. | No architecture in target tags or in a saved build's identity; the Windows runner cannot choose one. |
| R98 | Both runners write the tool's version and commit into the record. | No recipe or collection can state the tool version it needs, and nothing checks. |
| R102 | A base reference with a digest is passed through to the engine, untested; the record stores the digest that was pulled. | No local file or local registry as a base source; nothing tested. |

### 5.11 Collections, trust, lifecycle, team and the tool itself

Added in draft 4 from 4.16 to 4.33.

| ID | Requirement | From | Today |
|---|---|---|---|
| R77 | A collection's changes can be verified by building the affected recipes on every target they claim and each changed strap alone, leaving nothing behind; a target that cannot be tried is reported as untested. | 4.16 | no |
| R78 | The tool can create a new strap or recipe in the required shape, with its metadata and tags. | 4.17 | no |
| R79 | A strap or recipe can be marked superseded with a replacement; builds that use it warn, then after a stated period fail, in a form a program can read. | 4.17 | no |
| R80 | A strap's source, collection, commit and declarations can be shown before it runs. | 4.18, 4.12 | no |
| R81 | Builds can be restricted to named trusted collections; a one-off exception is recorded in the build record, and an automated caller can be denied exceptions. | 4.18 | no |
| R82 | The build record identifies the exact content of every strap and the identity of every collection used, and states how a collection was verified. | 4.18, 4.7 | partly |
| R83 | An environment can be returned to an earlier build, from a saved build or from a record, keeping storage that outlives it, and the user is told beforehand if the result may differ. | 4.19 | no |
| R84 | A failed build's environment can be kept, marked as failed wherever environments are listed. | 4.20 | no |
| R85 | The tool can say, per input, whether a rebuild would change anything, and says unknown where it cannot know. | 4.21 | no |
| R86 | An environment can be given a lifetime or tied to a caller, and is removed when that ends, by a later run if need be, keeping its record. | 4.22 | no |
| R87 | Everything the tool holds on a machine can be listed with size and age, previewed, and removed by choice or by rule; storage that outlives an environment is never removed without asking. | 4.23 | no |
| R88 | Resource limits and devices are stated without naming a target, fulfilled per target, and any shortfall is reported before the deploy. | 4.24 | no |
| R89 | Processor architecture is part of target tags, build records and saved-build identity, and the user can choose it. | 4.25 | partly |
| R90 | A named group of environments can be deployed, connected, reported and removed as one, with a partial failure leaving a state that one command removes. | 4.26 | no |
| R91 | Before a build, the tool states which operations need elevation and why; it uses unprivileged paths where a target has them; an unattended run never meets an elevation prompt. | 4.27 | no |
| R92 | On a shared machine every instance, saved build and collection has an owner; only the owner lists and removes it; nothing private to one user is readable by another. | 4.28 | no |
| R93 | Build records can be emitted for collection in one place and queried by strap, version, collection commit and tool version, and an answer states its coverage. | 4.29 | no |
| R94 | Every environment matching such a query can be rebuilt in one command, with each outcome named. | 4.29, 4.15 | no |
| R95 | A record from another machine can be the input to a build here, fetching collections at the commits it names; the two records are then compared, with differences and incomparable inputs stated. | 4.30, 4.7 | no |
| R96 | A build request can be satisfied from a shared store of saved builds without a local build; what happens when none exists is a stated setting, never a silent fallback. | 4.31 | no |
| R97 | The tool installs and updates with one command per platform. | 4.32 | no |
| R98 | The build record states the tool's version; a recipe or collection can state the tool version it needs, and a mismatch is reported with both versions. | 4.32 | partly |
| R99 | A check reports each target as usable or why not, each collection as reachable and at which commit, and inconsistencies in the tool's own state, with each repair previewed. | 4.33 | no |

### 5.12 Prerequisites for needs met by parts

These come from [MODULAR_CONCEPTS.md](MODULAR_CONCEPTS.md). Each is the one thing a base, strap,
recipe or deploy template cannot do for itself. R100 is in phase 1 (section 6, decision 8 in
section 9).

| ID | Requirement | From | Today |
|---|---|---|---|
| R100 | A strap can declare a check; the tool runs it after the strap and reports pass or fail per strap, in the record and in the result. | MODULAR 1 | no |
| R101 | The tool honours proxy and certificate settings when it fetches a base or a collection, since this happens before any strap runs. | MODULAR 2, 3 | no |
| R102 | A base can be named by digest, or given as a local file or a local registry, and the record states which was used. | MODULAR 3, 4 | partly |

---

## 6. Targets and phasing

All six are in scope. The order is a proposal.

| Target | Build | Save | Deploy | Proposed phase | Today |
|---|---|---|---|---|---|
| WSL distribution | yes | yes | yes | 1 | build only |
| Local container (docker, podman, Apple `container`) | yes | yes | yes | 1 | build and save |
| Kubernetes | from a saved build | to a registry | yes | 2 | no |
| Proxmox container | yes | yes | yes | 2 | no |
| Proxmox virtual machine | yes | yes | yes | 3 | no |
| Cloud instance | yes | yes | yes | 3 | no |

"Local container" is one target with several engines: docker and podman on Windows, macOS and
Linux, and Apple's `container` on macOS. Kubernetes is the remote-container target. The
developer's workbench (4.15) needs the first three rows: WSL, local containers and Kubernetes.

Processor architecture (amd64, arm64) is a dimension of every target, not a target of its own
(4.25, R89). A saved build exists per target and per architecture.

A target added later must not require changes to existing straps or recipes.

Requirements are not phased in this document, with one exception: a strap's declared check, run
and reported by the tool (R100), is in phase 1 beside the WSL and local container targets, so
that every strap written from then on can prove it worked.

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

Decided by the operator, 2026-11-16, on draft 4:

6. **Composing environments into a system is in scope.** Deploying, connecting and removing a
   named group of environments as one is the tool's job, built on single deploys and the
   parseable interface. See 4.26, R90.
7. **No capture of hand-made environments.** Proposing a recipe from an existing environment was
   considered and dropped: the result could only approximate, and the founding idea is that
   environments come from recipes, not the other way round. Users who have a hand-made
   environment write a recipe for it.
8. **Strap checks are phase 1.** A strap can declare a check and the tool runs and reports it
   (R100). This is small and makes every later strap more trustworthy, so it is built with the
   first targets (section 6).

### Still open

1. **The name.** "docker2wsl" describes one path out of many.
2. **Distribution.** How the tool itself is installed and updated on each platform.
3. **Names the tool enforces.** Two lists the tool will check things against, decided together
   because both are governance of shared names. First, the tag vocabulary: the platform,
   product and architecture names that target tags use (R6, R89), and who may add to it.
   Second, how a collection is verified: what "this collection is what it claims" means in R81
   and R82, whether a repository and commit, a signature, a hash, or some of each. The second
   part was added in draft 4.
4. **Start and stop on shared targets.** Whether stopping means the same thing on every target,
   given that some discard everything outside persistent storage when stopped.
