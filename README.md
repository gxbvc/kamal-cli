# kamal-cli

Run a local `.rb` on the production app container. The file is piped to `bin/rails runner -` so nested quotes and SQL do not go through Kamal's exec quoting.

Ruby stdlib only. Requires the app's bundled Kamal.

## Setup

```bash
ln -sf ~/tools/kamal-cli/kamal-cli ~/bin/kamal-cli
```

## Usage

From a Rails app checkout:

```bash
kamal-cli runner /tmp/count.rb
kamal-cli redeploy      # quiet bundle exec kamal redeploy
kamal-cli deploy        # quiet bundle exec kamal deploy
```

`deploy` and `redeploy` keep the whole log in a file. On success they print the last 30 lines and the log path; on failure, the whole log.

With `KAMAL_CLI_REGISTRY_LOGOUT=1` set (off by default until the first live use on one app), after a good `deploy`, `redeploy` or `rollback`, kamal-cli runs `kamal registry logout -L` (with the same `-d`/`-c` flags), so the hosts do not keep the registry password in `~/.docker/config.json`. `-L` keeps this Mac logged in for the next push. It prints one line with only the status and host names, for example `kamal-cli: registry_logout: {"status":"ok","hosts":["104.131.24.46"]}`. A failed logout does not change the exit code and is not retried. Apps on the law server (65.108.76.113) are skipped: `registry_logout: skipped (law)`.

`cp` into the container is deferred. If you need a non-runner file on the host, scp to the server then `docker cp` on the host. `docker cp host:container` is not valid.
