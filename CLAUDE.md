# CLAUDE.md

Self-hosted RustDesk server on AWS Lightsail, driven by Terraform and a bash CLI. See README.md for user-facing docs; the `rustdesk` skill in `.claude/skills/` covers operating it.

## Layout

- `rd`: the CLI that users run on their own machine (macOS or Linux). It reads `region`, `instance_name` and `rustdesk_server_ip` from `terraform output`, so new commands should call `load_outputs` rather than hardcoding values.
- `main.tf`, `variables.tf`: Lightsail instance, static IP and firewall. `user_data` installs Docker and runs `hbbs`/`hbbr`.
- `client/client-setup.sh`: the body of the macOS/Linux setup. `rd client-setup` prepends `SERVER_IP`, `SERVER_KEY` and `RD_PASSWORD` to it and writes it out as `rustdesk-setup-linux.sh` and `rustdesk-setup-mac.command`. When it's started from a file manager with no terminal, it reopens itself in one.
- `client/client-setup.ps1`: the body of the Windows setup. `rd client-setup` (`write_windows_setup`) wraps it in a `.cmd` with a batch header that elevates through UAC, then runs the PowerShell after the `##PS#` marker. Output has CRLF line endings. It runs on Windows PowerShell 5.1, so no PowerShell 7-only syntax (`??`, `?.`, ternary operators).
- Neither body may define `SERVER_IP`/`$ServerIp`, `SERVER_KEY`/`$ServerKey` or `RD_PASSWORD`/`$RdPassword` itself.
- `Brewfile`: the tools `rd` needs. Keep it in sync with the prerequisite check in `cmd_setup`.
- Servers created before Compose v2 run the old `docker-compose` (v1), which crashes with `KeyError: 'ContainerConfig'` when recreating a container. Remove the container first: `sudo docker rm -f hbbr && sudo docker-compose up -d hbbr`.
- `server/install-autostop.sh`: piped over SSH by `rd autostop` and run as root on the server. It installs a systemd timer that powers off after N idle minutes.

## Rules

- **Never cause the instance to be replaced.** A replacement regenerates the RustDesk key and breaks every configured client. `user_data` is in `lifecycle.ignore_changes` for this reason. Check `terraform plan` for "must be replaced" on `aws_lightsail_instance` after any Terraform change. New variable defaults must equal the values of existing deployments.
- **Shell compatibility.** `rd` runs on macOS's bash 3.2: no `mapfile`, associative arrays, `;;&`, `${var,,}` or GNU-only flags (`sed -i` without a suffix, `date -d`, `stat -c`). `client-setup.sh` must work on bash 3.2 (macOS) and on Linux. `install-autostop.sh` only runs on the Ubuntu server.
- **SSH** goes through `ssh_server`, which uses short-lived credentials from `get-instance-access-details`. Don't add key-pair management.
- **Secrets:** generated files in `out/` contain passwords, and `.rustdesk/` and `terraform.tfstate` are local state. All are gitignored; keep it that way.
- Never run `./rd setup`, `./rd destroy` or `terraform apply` without the user asking. They create or delete billable resources.

## Checking changes

- `bash -n rd client/client-setup.sh server/install-autostop.sh`
- `terraform validate` and `terraform plan` (needs AWS credentials)
- `shellcheck` if available
