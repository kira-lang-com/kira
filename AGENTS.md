# AGENTS.md

This is the repo for Kira in KLFD.

Uncommited work means nothing. Prefer working than checking Git, running test suites result in nothing, just run a single test that you are working against making it green then move on to the next one, while doing this you will write code, avoid checking git, running test suites, unrelated commands.

The roadmap and informations are in roadmap/, docs are in docs/

This repo is written entirely in klfd which stands for Kira Language Framework Definition, it is based in a subset of kira but written in rust.

KLFD is as good as rust when it comes to syntax. Avoid falling back to generic bad code patterns, here is a list of such:
- var index, while index < x; use for
- if (.x), if (.y); use match

This is a non exhaustive list, if you see any global bad pattern such as stuffing everything in one function, avoid this going forward.

Everytime you encounter one of the described problems you are allowed to start a new goal that is to rewrite enormous parts of the codebase in the goal to make this cleaner.

# Specs

Any spec is the rule. Read it before changing what it covers and do exactly what it says. If the spec does not say it, it does not exist: never invent a layout, encoding, convention or meaning to make a case work, and never route around a limit the spec sets. When the spec does not cover a case, take the natural way that follows from what the spec does say, and keep going without asking.
