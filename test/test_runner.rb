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

ENV.delete("KAMAL_CLI_TEST_FAIL")
ENV["KAMAL_CLI_TEST_LINES"] = "100"
out, _err, code = run_cli(cli, "redeploy", "-P", "--version", "abc")
abort out unless code == 0
abort out unless File.read(File.join(dir, "argv")).split == %w[exec kamal redeploy -P --version abc]
abort out if out.include?("line 70\n")
abort out unless out.include?("line 71\n") && out.include?("line 100\n")
abort out unless out.include?("redeploy ok") && out.include?("Full log: ")
log = out[/Full log: (\S+)/, 1]
abort out unless File.readlines(log).size == 100

ENV["KAMAL_CLI_TEST_FAIL"] = "1"
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 17
abort out unless out.include?("line 1\n") && out.include?("boom") && out.include?("deploy FAILED (exit 17)")
ENV.delete("KAMAL_CLI_TEST_FAIL")
ENV.delete("KAMAL_CLI_TEST_LINES")

Dir.chdir(dir)
out, _err, code = run_cli(cli, "deploy")
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"

out, _err, code = run_cli(cli, "runner", File.join(app, "script.rb"))
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"
