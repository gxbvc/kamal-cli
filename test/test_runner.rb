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

# SOC 2 deploy line (ok), approval ref from env, kept log copy 0600 in a 0700 folder
abort out unless out.include?("kamal-cli: recorded deploy event")
soc2 = File.read(File.join(dir, "soc2-argv")).split("\n")
abort soc2.inspect unless soc2[0, 5] == ["add", "--kind", "deploy", "--system", "app"] # no service: line, so the folder name
summary = soc2[soc2.index("--summary") + 1]
abort summary unless summary.match?(/\Aredeploy ok commit \S+ log \d{8}-\d{6} \d+s\z/)
abort soc2.inspect unless soc2[soc2.index("--approved-by") + 1] == "none" && soc2[soc2.index("--by") + 1] == "kamal-cli"
kept_dir = ENV.fetch("KAMAL_CLI_KEEP_LOG_DIR")
kept = File.join(kept_dir, File.basename(log))
abort kept unless File.read(kept) == File.read(log)
abort kept unless (File.stat(kept).mode & 0o777) == 0o600 && (File.stat(kept_dir).mode & 0o777) == 0o700

File.write("config/deploy.yml", "# app\nservice: fake-svc\nimage: x\n")
ENV["KAMAL_APPROVAL_REF"] = "card 4093"
out, _err, code = run_cli(cli, "rollback", "abc")
abort out unless code == 0 && File.read(File.join(dir, "argv")).split == %w[exec kamal rollback abc]
soc2 = File.read(File.join(dir, "soc2-argv")).split("\n")
abort soc2.inspect unless soc2[soc2.index("--approved-by") + 1] == "card 4093"
abort soc2.inspect unless soc2[soc2.index("--summary") + 1].start_with?("rollback ok commit ")
abort soc2.inspect unless soc2[soc2.index("--system") + 1] == "fake-svc"
File.write("config/deploy.yml", "")
ENV.delete("KAMAL_APPROVAL_REF")

# A broken event call never changes the exit code
ENV["KAMAL_CLI_TEST_SOC2_FAIL"] = "1"
out, _err, code = run_cli(cli, "redeploy")
abort out unless code == 0 && out.include?("kamal-cli: event NOT recorded (soc2-event: refused: approved_by contains a long token-like string)")
ENV.delete("KAMAL_CLI_TEST_SOC2_FAIL")
ENV["KAMAL_CLI_SOC2_EVENT"], saved = File.join(dir, "no-such-soc2-event"), ENV["KAMAL_CLI_SOC2_EVENT"]
out, _err, code = run_cli(cli, "redeploy")
abort out unless code == 0 && out.include?("kamal-cli: event NOT recorded")
ENV["KAMAL_CLI_SOC2_EVENT"] = saved

ENV["KAMAL_CLI_TEST_FAIL"] = "1"
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 17
abort out unless out.include?("line 1\n") && out.include?("boom") && out.include?("deploy FAILED (exit 17)")
abort out unless out.include?("kamal-cli: recorded deploy event")
summary = File.read(File.join(dir, "soc2-argv")).split("\n").then { |a| a[a.index("--summary") + 1] }
abort summary unless summary.start_with?("deploy FAILED exit 17 commit ")
ENV["KAMAL_CLI_TEST_SOC2_FAIL"] = "1"
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 17 && out.include?("kamal-cli: event NOT recorded")
ENV.delete("KAMAL_CLI_TEST_SOC2_FAIL")
ENV.delete("KAMAL_CLI_TEST_FAIL")
ENV.delete("KAMAL_CLI_TEST_LINES")

Dir.chdir(dir)
out, _err, code = run_cli(cli, "deploy")
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"

out, _err, code = run_cli(cli, "runner", File.join(app, "script.rb"))
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"
