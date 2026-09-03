# kamal-cli

Pipe a local Ruby file into production `bin/rails runner` without quoting it through Kamal.

Run from the Rails app cwd.

## Commands

```bash
kamal-cli runner FILE.rb
```

JSON: `{"ok":true,"data":{"exit":0,"stdout":"...","stderr":"...","host":"..."}}` or `{"ok":false,"error":"...","code":"..."}`.

Do not use `kamal app exec bin/rails runner '...'`. Do not scp a runner file. `cp` into the container is not in v1.

## Notes

- Bytes of FILE go on stdin to `bundle exec kamal app exec --interactive --reuse -- bin/rails runner -`.
- Needs `config/deploy.yml` in cwd.
- Kamal chatter is stripped from stdout. Script output is in `data.stdout`.
