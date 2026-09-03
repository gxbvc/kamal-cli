#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"

root = File.expand_path("..", __dir__)
cli = File.join(root, "kamal-cli")
dir = ENV.fetch("KAMAL_CLI_TEST_DIR")
app = File.join(dir, "app")
FileUtils.mkdir_p(File.join(app, "config"))
File.write(File.join(app, "config", "deploy.yml"), "")
FileUtils.cp(File.join(root, "test", "script.rb"), File.join(app, "script.rb"))
Dir.chdir(app)

def run_cli(cli, *args)
  stdout, stderr, status = Open3.capture3(cli, *args)
  [stdout, stderr, status.exitstatus]
end

out, _err, code = run_cli(cli, "runner", File.join(dir, "missing.rb"))
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["ok"] == false && payload["code"] == "NOT_FOUND"

out, _err, code = run_cli(cli, "runner", "script.rb")
payload = JSON.parse(out)
abort payload.inspect unless code == 0 && payload["ok"] == true
abort payload.inspect unless payload["data"]["exit"] == 0
abort payload.inspect unless payload["data"]["stdout"] == "ok-stdout\n"
abort payload.inspect unless payload["data"]["host"] == "10.0.0.1"
abort payload.inspect if payload["data"]["stdout"].include?("Get current version")

argv = File.read(File.join(dir, "argv"))
parts = argv.split
abort argv unless parts[0, 6] == %w[exec kamal app exec --interactive --reuse]
abort argv unless parts.include?("bin/rails") && parts.include?("runner")
got = File.read(File.join(dir, "stdin"))
want = File.read("script.rb")
abort [got, want].inspect unless got == want

ENV["KAMAL_CLI_TEST_FAIL"] = "1"
out, _err, code = run_cli(cli, "runner", "script.rb")
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["ok"] == false && payload["code"] == "RUNNER_FAILED"

Dir.chdir(dir)
out, _err, code = run_cli(cli, "runner", File.join(app, "script.rb"))
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"
