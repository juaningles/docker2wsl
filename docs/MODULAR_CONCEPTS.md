# Concepts of use met by bases, straps, recipes and deploy templates

Status: draft 1, 2026-11-16. Companion to [USE_CASES.md](USE_CASES.md) draft 4.

Not every need a user brings is a use case of the tool. Many are met by choosing a different base
image, writing a strap, adding a setting to a recipe, or supplying a deploy template for a target.
The tool's job is to run those parts well. This document collects such needs so they are not lost
and not mistaken for tool features. Each entry is a concept, not a full use case: who has the
need, which part meets it, a few example uses, and the one thing, if any, that only the tool can
provide. Those prerequisites are requirements R100 to R102 in USE_CASES.md section 5.12.

Terms (strap, recipe, base, target, deploy template, instance) are as defined in USE_CASES.md
section 2. "Deploy template" is the per-target shape of an instance that a user may supply
(R37).

---

## 1. A strap proves it worked

**Who:** every strap author; the team that wants "built" to mean "works".

**Met by:** the strap itself. A strap ends with a check: the tool it installed answers a version
query, a file it wrote exists, a service it configured responds. The check is part of the strap,
written by the person who knows what success looks like.

Example uses:
- The `uv` strap ends by asking `uv --version` and fails if the answer is empty.
- A shell-configuration strap starts a login shell and confirms the prompt it set is in place.
- A strap that links a folder to outside storage (USE_CASES 4.14) writes a file through the link
  and reads it back.

**What only the tool can provide:** running the check after the strap and reporting pass or fail
per strap, in the build record and in the parseable result (R100). Today a strap can only exit
non-zero, which stops the build; a check that is reported but not fatal needs the tool. This is
the one prerequisite in this document that is in phase 1 (USE_CASES section 6).

## 2. Build behind a corporate network

**Who:** the team and the solo developer on an employer's machine. The most common reason a build
that works at home fails at work.

**Met by:** a strap that runs first in every recipe and sets the proxy for the package manager,
the shell and the common tools, and installs the corporate certificate authority into the
environment's trust store. Its settings (proxy address, certificate file) come from the recipe or
from the building machine, never from the strap's own text.

Example uses:
- A team recipe begins with `corp-network` and every other strap downloads through it.
- A member working from home builds the same recipe with the strap's proxy setting empty; the
  strap does nothing and says so.
- A certificate rotates. The strap's setting points at the new file and the next rebuild picks
  it up. Nothing else changes.

**What only the tool can provide:** the base is fetched, and collections are cloned, before any
strap runs. The tool must honour proxy and certificate settings for its own fetches (R101).

## 3. Build offline or air-gapped

**Who:** teams in restricted networks; anyone on a plane.

**Met by:** a base image from a local mirror or a local file, and a strap that points package
managers and language tool installers at internal mirrors. A recipe meant for such a network
names only sources that exist inside it.

Example uses:
- A recipe's base is `mirror.internal/ubuntu:24.04` and its first strap rewrites apt and pip
  sources to the mirror.
- A saved build made where the network is open is carried in as a file and deployed where it is
  not (USE_CASES 4.8, 4.9). No build happens inside.
- A preview (USE_CASES 4.12) is run before travelling to see what a build would try to download.

**What only the tool can provide:** accepting a base as a local file or from a local registry,
and making no network calls of its own that the user did not ask for (R101, R102).

## 4. Pin and trust the base

**Who:** the team that pins versions (USE_CASES 4.6); anyone who needs builds weeks apart to be the
same.

**Met by:** naming the base by digest instead of by tag in the recipe, and taking it from a
registry the team controls. The decision of when to move to a newer base is a change to the
recipe, reviewed like any other.

Example uses:
- A team recipe names `ubuntu@sha256:...`; a tag that moves cannot change their build.
- A private registry holds approved bases only, and recipes may name no other.
- Two build records differ only in base digest, which explains a difference in behaviour.

**What only the tool can provide:** passing a digest reference through to every target, and
recording which base was actually used (R102). Restricting which registries a recipe may name is
a trust question (USE_CASES 4.18, R81).

## 5. Reach the environment from an editor or an agent

**Who:** the solo developer who lives in an editor; the AI agent that needs a shell in the
environment it was given.

**Met by:** straps that install and configure what the editor or agent connects to: an SSH
server, an editor's remote server, devcontainer metadata. The tool's existing promise is to say
how to reach an instance once it exists (USE_CASES 4.9).

Example uses:
- A `sshd` strap, run per instance, gives every deployed instance an SSH endpoint the editor's
  remote extension can open.
- A `devcontainer` strap writes the metadata that lets an editor treat the instance as a dev
  container.
- An agent workflow deploys an instance, reads the "how to reach it" line from the parseable
  result (USE_CASES 4.10), and connects.

**What only the tool can provide:** nothing beyond 4.9 and 4.10. If a target needs a port or an
address published for the connection to work, that is a deploy template setting (section 7).

## 6. Give the environment host resources

**Who:** the solo developer. Keys, drives, the clipboard, a display and the engine's socket are
the things that make an environment feel like part of the machine.

**Met by:** deploy template settings for the mounts and sockets a target can offer, and straps for
the environment's side: pointing the SSH client at the forwarded agent, linking a folder in the
home directory to a mounted drive, installing a clipboard bridge.

Example uses:
- A WSL recipe's strap links `~/work` to a shared drive on the Windows side (USE_CASES 4.14).
- A container deploy template mounts the host's SSH agent socket, and a strap sets the variable
  that points at it, so git inside the environment uses the user's keys without copying them
  (USE_CASES 4.11).
- A strap installs a bridge so a terminal editor inside the environment can paste from the host.

**What only the tool can provide:** per-target deploy templates (R37) and target tags so a strap
written for one target's kind of mount is never run on another (R6, R20). Both are already
required.

## 7. Expose a service and let instances find each other

**Who:** the automated caller that deploys several workers; the developer testing a web service.

**Met by:** per-instance deploy template settings on each target: a published port and a hostname
for a container, a service for a cluster, a port forward for a WSL distribution. The environment
itself needs nothing special.

Example uses:
- A web-service recipe's deploy template publishes port 8080, so the instance is reachable from
  the host's browser as soon as it is deployed.
- Five workers from one saved build are deployed with names worker-1 to worker-5 and reach a
  coordinator by hostname, all within one template.
- The same recipe is deployed on a cluster, where the template becomes a service definition.

**What only the tool can provide:** deploy templates (R37) and instance names the caller chooses
(USE_CASES 4.9). Deploying a group of different environments as one connected system is a
different matter and is the tool's own job (USE_CASES 4.26, R90).

## 8. Use hardware inside the environment

**Who:** the developer doing data or model work who needs a GPU; anyone who needs a USB device.

**Met by:** a base image that already carries the vendor's runtime, or a strap that installs
drivers, libraries and the toolkits the work needs, tagged for the architectures and targets it
supports.

Example uses:
- A `cuda` strap installs the toolkit on a base that the vendor publishes with the driver
  libraries, and ends with a check that the GPU is visible (section 1).
- A data recipe extends the team recipe (R10) with the GPU strap, so only the people who need
  it pay the download.
- An embedded project's strap installs the tools that talk to a device over USB.

**What only the tool can provide:** passing the device through to the instance and saying
beforehand if the target cannot (USE_CASES 4.24, R88). Everything inside the environment is a
strap.

## 9. Documentation for a new joiner

**Who:** the team that wants a new member to know what is in their environment on day one
(USE_CASES 3.2).

**Met by:** a strap that writes a readable summary of the build record into the environment, or
a recipe setting that names a document to install beside it. The record already holds what was
installed and from where (USE_CASES 4.7).

Example uses:
- A `motd` strap shows the build summary at every login, so a new joiner sees what they have.
  This exists today.
- A strap writes a `README` in the home directory from the record: each strap, what it installed,
  where to ask about it.
- The team recipe installs a short guide to the team's conventions, kept in the team's
  collection and versioned with it.

**What only the tool can provide:** a build record readable inside the environment (R39), which
already exists.

---

## Summary

| Concept | Base | Strap | Recipe setting | Deploy template | Tool prerequisite |
|---|---|---|---|---|---|
| 1. Strap proves it worked | | yes | | | R100 |
| 2. Corporate network | | yes | settings | | R101 |
| 3. Offline or air-gapped | yes | yes | | | R101, R102 |
| 4. Pin and trust the base | yes | | digest | | R102, R81 |
| 5. Reach from editor or agent | | yes | | port | none new |
| 6. Host resources | | yes | | mounts | R37, R6, R20 (existing) |
| 7. Expose a service | | | | yes | R37 (existing); 4.26 open |
| 8. Hardware inside | yes | yes | | device | R88 |
| 9. New joiner documentation | | yes | yes | | R39 (existing) |

When a concept here grows a need that no part can meet, it moves to USE_CASES.md as a use case.
When a use case there turns out to be a strap, it moves here.
