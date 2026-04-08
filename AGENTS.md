# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

`yaml_exporter` is a Ruby gem that provides YAML serialization/deserialization for ActiveRecord models with JSON schema generation. It is a library (not a runnable application) — there are no servers, databases, or background services to run.

### Ruby version management

Ruby is managed via **rbenv** (installed at `~/.rbenv`). The project targets the latest stable Ruby — currently **4.0.2**.

If a future Ruby version is needed and `rbenv install <version>` fails with "definition not found", update ruby-build first:

```bash
cd ~/.rbenv/plugins/ruby-build && git pull
rbenv install <version>
rbenv global <version>
```

Then re-run `bundle install` in the workspace.

### Key commands

| Task | Command |
|------|---------|
| Install dependencies | `bundle install` |
| Build the gem | `gem build yaml_exporter.gemspec` |
| Verify the gem loads | `ruby -e 'require_relative "lib/yaml_exporter"; puts "OK"'` |

### Notes

- There is no test suite (`spec/` or `test/`) in this repo, and no linter configuration. Validation is done by building the gem and running it against an in-memory SQLite ActiveRecord setup.
- The gem depends on `activerecord`, `activesupport`, and `json-schema` at runtime. For manual testing, `sqlite3` is also needed (`gem install sqlite3`).
- The gemspec uses `git ls-files` to determine included files — new files must be tracked by git to be included in builds.
