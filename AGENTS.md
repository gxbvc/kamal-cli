# kamal-cli

Pipe a local Ruby file into production `bin/rails runner` without quoting it through Kamal.

Run from the Rails app cwd.

## Commands

```bash
kamal-cli runner FILE.rb
kamal-cli redeploy [KAMAL ARGS...]   # e.g. -P --version abc123
kamal-cli deploy [KAMAL ARGS...]
```

`deploy` and `redeploy` run `bundle exec kamal deploy|redeploy ARGS`, save the whole log under `$TMPDIR/kamal-cli/`, and print plain text: the last 30 lines and the log path on success, the whole log on failure. The exit code is Kamal's. Use them instead of raw `bundle exec kamal deploy` so agent context stays small.

JSON: `{"ok":true,"data":{"exit":0,"stdout":"...","stderr":"...","host":"..."}}` or `{"ok":false,"error":"...","code":"..."}`.

Do not use `kamal app exec bin/rails runner '...'`. Do not scp a runner file. `cp` into the container is not in v1.

## Notes

- Bytes of FILE go on stdin to `bundle exec kamal app exec --interactive --reuse -- bin/rails runner -`.
- Needs `config/deploy.yml` in cwd.
- Kamal chatter is stripped from stdout. Script output is in `data.stdout`.
