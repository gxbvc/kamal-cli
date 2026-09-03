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
```

`cp` into the container is deferred. If you need a non-runner file on the host, scp to the server then `docker cp` on the host. `docker cp host:container` is not valid.
