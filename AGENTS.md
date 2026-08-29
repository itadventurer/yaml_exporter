# yaml_exporter — agent & developer notes

A Ruby gem that serializes an ActiveRecord record and everything it owns to a
human-readable YAML file and imports it back in one transaction. A three-method
DSL (`attributes`, `one`, `many`) declares the mapping. It is a library: no
server, no database service, nothing to boot.

`README.md` is the front door and the reference for the DSL; `RELEASING.md`
describes how a version reaches RubyGems.

## Layout

| Where | What |
| --- | --- |
| `lib/yaml_exporter/` | the DSL, the export and import passes, type inference, schema generation |
| `test/` | one concern per file — `dsl_validation_test`, `type_inference_test`, `schema_test`, the `one_*` / `many_*` files for each association shape, `full_integration_test` for the round trip |
| `test/support/`, `test/fixtures/` | the throwaway models and YAML the suite builds against |

## Commands

| Command | What |
| --- | --- |
| `bundle install` | once; the gem targets the current stable Ruby and requires >= 3.2 |
| `bundle exec rake test` | the whole suite |
| `gem build yaml_exporter.gemspec` | build the gem |

The gemspec picks its files with `git ls-files`, so a new file has to be tracked
by git before it lands in a build. Runtime dependencies are activerecord,
activesupport and json-schema; `sqlite3` is what the tests run against.

## This repository is public

It is on GitHub and RubyGems. **Nothing from a private project may appear here** —
not in code, comments, tests, docs, the CHANGELOG, commit messages or pull
request descriptions. No private domain models or method names, no production
error messages, no internal hostnames or repository paths. Describe a bug that
arrived from a private application in terms of this gem's own vocabulary and its
test models. Grep the diff and the description for leaks before pushing.

## Conventions

- Every association shape the DSL accepts has its own test file, and every
  raising DSL combination has a case in `dsl_validation_test.rb`. A new shape
  arrives with both.
- A behaviour change updates `README.md` in the same commit — for this gem the
  README is the reference, not an introduction.
- Everything inside a repository file is English: code, comments, docs, and here
  also commit messages and pull request prose, since the audience is public.

## Pull requests

- Work on a branch off current `origin/main`, one topic per pull request.
- **Never merge a pull request yourself and never enable auto-merge.** Prepare it
  to the point of merging — conflicts resolved, branch pushed, CI green — then
  say it is ready and stop.
- Never force-push a branch that is under review; merge the parent branch upward
  or open a follow-up pull request instead.
- Answer review comments, do not resolve the threads.
- Stacked pull requests merge along the chain, base into head, pair by pair.
  Merging the same commit into each branch separately makes the trees diverge and
  creates conflicts between neighbours that had none. A pull request reporting
  **"no checks reported"** is the tell: GitHub cannot build `refs/pull/N/merge`
  for a conflicting branch and never starts the workflow — no red cross, just
  nothing. Check with `gh pr view N --json mergeable,mergeStateStatus`.
- Releases go through `RELEASING.md`: publishing a GitHub Release for tag
  `vX.Y.Z` triggers the trusted-publishing workflow. Do not push a gem by hand,
  and do not create the release without being asked.
