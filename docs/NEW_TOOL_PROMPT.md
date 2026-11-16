# Prompt: requirements for the new tool

Handoff prompt for the session that starts the new repository. Reforged 2026-11-16 (v3) and
updated for USE_CASES.md draft 4. Give it to an agent sitting in this repo.

## Context

You are in C:\code\docker2wsl, the repo of container2wsl: a Windows batch script (plus a bash
runner, container2x.sh) that builds a WSL distribution or a running container from any OCI image,
then runs "straps" (bootstraps as root, poststraps as the user) chosen by a "recipe", and writes a
build manifest. I am going to replace it with a new product in a compiled, cross-platform language.
The language is NOT chosen yet and this task does not choose it; this task produces the
requirements that a design, and the language choice, will be made against.

docs/USE_CASES.md already holds the agreed use cases, a numbered requirements list (R1...), the
target phasing (section 6), the qualities (7), and the operator's decisions and open questions (9).
Treat it as the source of truth for scope. If that file is missing or has no numbered requirements, stop and report; do not reconstruct it. Your job is to deepen it with what the current
implementation knows, not to rewrite it.

## Step 1: inventory the current tool (read, do not modify)

Read, in this order: README.md, CLAUDE.md, TESTING.md, docs/RUNNERS.md, docs/USE_CASES.md,
container2wsl.bat (argument parsing and the :label subroutines), container2x.sh, lib/*, every file
under bootstraps/, poststraps/, recipes/, and the test files under tests/ (the asserts tell you
what behaviour is relied on). Run `container2wsl.bat --help` and `bash container2x.sh --help` if
they exist; do not run a real build.

Write docs/CURRENT_TOOL_INVENTORY.md in the new repo (location below) with:
- every command-line option and environment variable, with its meaning and default;
- the build flow per target as it runs today, step by step;
- the strap and recipe file formats, the rendering rules, and the variables a strap can use;
- the manifest format and the c2w-manifest report;
- a table of the "hard-won quirks" from CLAUDE.md, each classified as: a behaviour the new tool
  must keep (and why), a platform fact the new tool must still handle, or an artifact of batch /
  bash that disappears with the new implementation;
- a list of what the tests assert, grouped by feature, as the seed of the parity test list.

## Step 2: write the requirements

Create the new repo as a sibling folder: C:\code\c2w-next (placeholder; the product name is open
question 1 in USE_CASES.md section 9, do not pick one). Run `git init` there and commit the three
documents at the end. Put the requirements in docs/REQUIREMENTS.md. Copy docs/USE_CASES.md and
docs/MODULAR_CONCEPTS.md into the new repo unchanged, under docs/, so the requirements can cite
them by section; R100 to R102 in USE_CASES.md refer to the second document.

Rules for REQUIREMENTS.md:
1. Keep the R-numbers from USE_CASES.md. Every existing R appears either as is, refined (same
   number, sharper text, with "refined from" noted), or split (R12 -> R12a, R12b). New
   requirements continue the numbering after the last existing one.
2. Each requirement is one testable sentence: a reader can say how they would check it. "Should be
   fast" is not one; "a dry run of any recipe finishes in under 2 seconds on the reference machine"
   is.
3. Each requirement carries: the use case(s) it serves (4.x), its phase (the phase of the earliest target in section 6 it applies to, or "all" for target-neutral requirements), and a
   parity tag: KEEP (current behaviour the new tool reproduces), CHANGE (current behaviour,
   deliberately different; say what and why), NEW (no counterpart today), DROP (current behaviour
   the new tool will not have; say why).
4. Group by area, following USE_CASES.md section 5, and add these areas: command-line interface
   and output (including machine-readable output for use case 4.10); configuration and discovery
   of recipes and strap collections; error handling and recovery (qualities "Recoverable" and
   "Transparent"); installation and update of the tool itself (already use case 4.32 and R97,
   R98; open question 2 covers only how it is distributed, so refine, do not duplicate); test strategy
   (what a parity test suite against the current tool must cover, from the inventory).
5. Non-functional requirements get their own section: platforms the tool runs ON (Windows, macOS,
   Linux) versus targets it builds FOR, single-binary or not, no runtime dependency on a scripting
   language on the host, startup time, size of the install, telemetry (none unless stated).
6. A section "Constraints the implementation language must satisfy": derive each from a
   requirement (for example: must spawn and stream from wsl.exe and docker with correct handling
   of UTF-16 output; must ship as one file per platform; must be maintainable by a small team).
   List constraints and the requirement each comes from. Do not rank or pick languages.
7. A section "Open questions" that carries forward the four open questions from USE_CASES.md
   section 9 and adds any new ones the inventory raised. For each, say what decision it blocks.
8. Where USE_CASES.md and the current code disagree, record the disagreement under the
   requirement; do not resolve it silently.

Do not write any design: no module layout, no data model, no language comparison. If you find
yourself describing how, move it to a "Notes for the design" appendix in one line each.

## Done

Done means: all three documents exist in C:\code\c2w-next\docs, every R from USE_CASES.md is accounted
for, every requirement has a use case, phase, and parity tag, and there is one commit. Finish with
a short summary: the counts of KEEP / CHANGE / NEW / DROP, the new open questions, and anything in
the current tool you could not classify.
