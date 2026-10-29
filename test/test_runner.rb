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

ENV["KAMAL_CLI_REGISTRY_LOGOUT"] = "0" # the early tests check plain deploy output; logout is tested below

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

# runner -c: the config flag goes to kamal app exec; a missing config file is refused
File.write("config/deploy.production.yml", "service: x\n")
out, _err, code = run_cli(cli, "runner", "-c", "config/deploy.production.yml", "script.rb")
abort out unless code == 0 && JSON.parse(out)["ok"] == true
parts = File.read(File.join(dir, "argv")).split
abort parts.inspect unless parts[0, 8] == %w[exec kamal app exec -c config/deploy.production.yml --interactive --reuse]
out, _err, code = run_cli(cli, "runner", "-c", "config/deploy.nope.yml", "script.rb")
abort out unless code == 1 && JSON.parse(out)["code"] == "NOT_FOUND"
out, _err, code = run_cli(cli, "runner", "-c", "config/deploy.production.yml")
abort out unless code == 1 && JSON.parse(out)["code"] == "USAGE"
File.delete("config/deploy.production.yml")

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

# Registry logout after a good deploy/redeploy/rollback (Security, Oct 28)
logout_argv = File.join(dir, "logout-argv")
logout_calls = lambda do
  calls = File.exist?(logout_argv) ? File.read(logout_argv).split("\n") : []
  FileUtils.rm_f(logout_argv)
  calls
end
abort "logout ran with KAMAL_CLI_REGISTRY_LOGOUT=0" unless logout_calls.call.empty? # the tests above ran with 0

# Only "0" turns it off
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 0 && logout_calls.call.empty? && !out.include?("registry_logout")
# On by default (Security, Oct 29): no env, "1" or anything else but "0" logs out, the Mac too (no -L)
[nil, "1", "true"].each do |val|
  val ? ENV["KAMAL_CLI_REGISTRY_LOGOUT"] = val : ENV.delete("KAMAL_CLI_REGISTRY_LOGOUT")
  out, _err, code = run_cli(cli, "deploy")
  abort out unless code == 0 && logout_calls.call == %w[exec kamal registry logout] && out.include?("registry_logout")
end
ENV.delete("KAMAL_CLI_REGISTRY_LOGOUT")

no_registry_text = ->(o) { abort o if o.include?("ghcr.io") || o.include?("REGISTRY-SECRET") || o.include?("docker logout") }

%w[deploy redeploy rollback setup accessory].each do |cmd|
  out, _err, code = run_cli(cli, cmd, "-d", "staging", "--version", "abc")
  abort out unless code == 0
  calls = logout_calls.call
  abort calls.inspect unless calls == %w[exec kamal registry logout -d staging]
  abort out unless out.include?('kamal-cli: registry_logout: {"status":"ok","hosts":["104.131.24.46","10.0.0.2"],"mac":"logged out"}')
  no_registry_text.call(out)
end


# -c and --destination= pass through
out, _err, code = run_cli(cli, "deploy", "-c", "config/other.yml", "--destination=prod")
abort out unless code == 0
calls = logout_calls.call
abort calls.inspect unless calls == %w[exec kamal registry logout -c config/other.yml --destination=prod]

# A failed logout is reported and the deploy still counts as ok
ENV["KAMAL_CLI_TEST_LOGOUT_FAIL"] = "1"
out, _err, code = run_cli(cli, "redeploy")
abort out unless code == 0 && out.include?("redeploy ok")
abort out unless logout_calls.call == %w[exec kamal registry logout] # one call, no retry
abort out unless out.include?('kamal-cli: registry_logout: {"status":"failed","hosts":["104.131.24.46","10.0.0.2"],"mac":"logged out","exit":1,"failed_hosts":["10.0.0.2"]}')
no_registry_text.call(out)
ENV.delete("KAMAL_CLI_TEST_LOGOUT_FAIL")

# A failed deploy still logs out (a failed run may have logged in), and keeps its exit code
ENV["KAMAL_CLI_TEST_FAIL"] = "1"
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 17 && logout_calls.call == %w[exec kamal registry logout] && out.include?("registry_logout")
ENV.delete("KAMAL_CLI_TEST_FAIL")

# Another kamal running on this Mac: hosts only (-L), Mac login kept
ENV["KAMAL_CLI_TEST_OTHER_KAMAL"] = "1"
out, _err, code = run_cli(cli, "deploy")
abort out unless code == 0 && logout_calls.call == %w[exec kamal registry logout -L] && out.include?(%q{"mac":"kept (another kamal running)"})
ENV["KAMAL_CLI_TEST_OTHER_KAMAL"] = "0"

# redeploy and rollback log in first (they do not log in themselves); deploy does not get an extra login
login_argv = File.join(dir, "login-argv")
login_calls = lambda { c = File.exist?(login_argv) ? File.read(login_argv).split("\n") : []; FileUtils.rm_f(login_argv); c }
login_calls.call # drop the logins of the runs above
%w[deploy redeploy rollback].each do |cmd|
  out, _err, code = run_cli(cli, cmd, "-d", "staging")
  abort out unless code == 0 && login_calls.call == %w[exec kamal registry login -d staging]
  logout_calls.call
end
out, _err, code = run_cli(cli, "setup")
abort out unless code == 0 && login_calls.call.empty?
logout_calls.call
# a failed login stops before the redeploy runs
ENV["KAMAL_CLI_TEST_LOGIN_FAIL"] = "1"
FileUtils.rm_f(File.join(dir, "argv"))
out, _err, code = run_cli(cli, "redeploy")
abort out unless code == 1 && out.include?("registry login before redeploy FAILED") && !File.exist?(File.join(dir, "argv"))
ENV.delete("KAMAL_CLI_TEST_LOGIN_FAIL")
login_calls.call; logout_calls.call

# law app: no login-first (Gov logs in with the read-only token itself)
File.write("config/deploy.yml", "servers:\n  web:\n    - 65.108.76.113\n")
out, _err, code = run_cli(cli, "redeploy")
abort out unless code == 0 && login_calls.call.empty? && out.include?("registry_logout: skipped (law)")
File.write("config/deploy.yml", "")
logout_calls.call

# Law: no logout when the law server shows up in deploy.yml, the destination
# file, the args or the deploy log
law = "65.108.76.113"
[
  -> { File.write("config/deploy.yml", "servers:\n  web:\n    - #{law}\n"); [] },
  -> { File.write("config/deploy.law.yml", "servers:\n  - #{law}\n"); %w[-d law] },
  -> { ["--hosts", law] },
  -> { ENV["KAMAL_CLI_TEST_HOST"] = law; [] }
].each do |setup_case|
  args = setup_case.call
  out, _err, code = run_cli(cli, "deploy", *args)
  abort out unless code == 0 && out.include?("kamal-cli: registry_logout: skipped (law)")
  abort out unless logout_calls.call.empty?
  File.write("config/deploy.yml", "")
  FileUtils.rm_f("config/deploy.law.yml")
  ENV.delete("KAMAL_CLI_TEST_HOST")
end

# Another destination's file with the law IP does not block a non-law deploy
File.write("config/deploy.law.yml", "servers:\n  - #{law}\n")
out, _err, code = run_cli(cli, "deploy", "-d", "staging")
abort out unless code == 0 && logout_calls.call == %w[exec kamal registry logout -d staging]
FileUtils.rm_f("config/deploy.law.yml")
ENV["KAMAL_CLI_REGISTRY_LOGOUT"] = "0"

# gxbee builder guard (Security, Oct 28 #4700): refuse before kamal runs.
allow = File.join(dir, "app-allowlist.md")
ENV["KAMAL_CLI_GXBEE_ALLOWLIST"] = allow
File.write(allow, "| App | PHI or law | Check result | Status | Security OK |\n|---|---|---|---|---|\n| roadmap | no | PASS | ALLOWED | yes |\n| other | no | PASS | NOT YET | |\n")
argv_file = File.join(dir, "argv")
guard = lambda do |deploy_yml|
  File.write("config/deploy.yml", deploy_yml)
  FileUtils.rm_f(argv_file)
  out, _err, code = run_cli(cli, "deploy")
  [out, code, File.exist?(argv_file)]
end
out, code, ran = guard.call("service: other\nbuilder:\n  arch: amd64\n  remote: ssh://gxbbuild@gxbee.tail478d01.ts.net\n")
abort "not-allowed app: #{out}" unless code == 1 && out.include?("GXBEE_BUILDER_REFUSED") && out.include?("not ALLOWED") && !ran
out, code, ran = guard.call("service: roadmap\nbuilder:\n  remote: ssh://gxbbuild@gxbee\n")
abort "allowed app refused: #{out}" unless code == 0 && ran
out, code, ran = guard.call("service: roadmap\nservers:\n  - 65.108.76.113\nbuilder:\n  remote: ssh://gxbbuild@gxbee\n")
abort "law app ran: #{out}" unless code == 1 && out.include?("law app") && !ran
out, code, ran = guard.call("service: roadmap\nbuilder:\n  remote: ssh://gxbbuild@gxbee-evil.example\n")
abort "lookalike host treated as gxbee: #{out}" unless code == 0 && ran
ENV["KAMAL_CLI_GXBEE_ALLOWLIST"] = File.join(dir, "missing-allowlist.md")
out, code, ran = guard.call("service: roadmap\nbuilder:\n  remote: ssh://gxbbuild@gxbee\n")
abort "unreadable allowlist did not fail closed: #{out}" unless code == 1 && out.include?("check failed") && !ran
out, code, ran = guard.call("service: roadmap\nbuilder:\n  remote: ssh://root@104.131.24.46\n")
abort "non-gxbee remote blocked: #{out}" unless code == 0 && ran
ENV["KAMAL_CLI_GXBEE_ALLOWLIST"] = allow
ENV["DOCKER_HOST"] = "ssh://gxbbuild@gxbee.tail478d01.ts.net"
out, code, ran = guard.call("service: roadmap\n")
abort "DOCKER_HOST=gxbee not refused: #{out}" unless code == 1 && out.include?("DOCKER_HOST names gxbee") && !ran
ENV.delete("DOCKER_HOST")
ENV.delete("KAMAL_CLI_GXBEE_ALLOWLIST")
File.write("config/deploy.yml", "")

# Dirty tree (Security, Oct 29): deploy, redeploy and setup refuse; rollback does not build, so it runs.
system("git", "init", "-q", ".") || abort("git init")
system("git", "add", "-A") && system("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base") || abort("git commit")
run_dirty = lambda do |cmd|
  FileUtils.rm_f(argv_file)
  out, _err, code = run_cli(cli, cmd)
  [out, code, File.exist?(argv_file)]
end
out, code, ran = run_dirty.call("deploy")
abort "clean tree refused: #{out}" unless code == 0 && ran
File.write("uncommitted.rb", "x")
%w[deploy redeploy setup].each do |cmd|
  out, code, ran = run_dirty.call(cmd)
  abort "dirty #{cmd} ran: #{out}" unless code == 1 && JSON.parse(out)["code"] == "DIRTY_TREE" && out.include?("1 changed or untracked") && !ran
end
out, code, ran = run_dirty.call("rollback")
abort "rollback refused on a dirty tree: #{out}" unless code == 0 && ran
ENV["KAMAL_CLI_ALLOW_DIRTY"] = "1"
out, code, ran = run_dirty.call("deploy")
abort "override did not run: #{out}" unless code == 0 && ran
soc2_last = File.readlines(File.join(dir, "soc2-argv")).map(&:chomp) rescue []
abort "override not in the soc2 line: #{soc2_last.inspect}" unless soc2_last.any? { |a| a.include?("+dirty dirty-override") }
ENV.delete("KAMAL_CLI_ALLOW_DIRTY")
File.delete("uncommitted.rb")
FileUtils.rm_rf(".git")

Dir.chdir(dir)
out, _err, code = run_cli(cli, "deploy")
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"

out, _err, code = run_cli(cli, "runner", File.join(app, "script.rb"))
payload = JSON.parse(out)
abort payload.inspect unless code == 1 && payload["code"] == "NOT_RAILS_APP_CWD"
