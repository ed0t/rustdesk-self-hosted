---
name: rustdesk
description: Operate this repo's self-hosted RustDesk server on AWS Lightsail with ./rd. Use when the user wants to create, start, stop, check or delete the server, set up a computer they support (Windows, Linux or macOS), get the server key, change auto-shutdown, or troubleshoot a RustDesk connection (can't connect, black screen, no mouse control, server unreachable).
---

# RustDesk server operations

Everything goes through `./rd` in the repo root. Run `./rd` with no arguments for usage. It uses the user's normal AWS credentials; if a command fails with an auth error, ask which `AWS_PROFILE` to use rather than guessing.

## Map requests to commands

| The user says | Run |
|---|---|
| "turn on / start the server", "someone needs help" | `./rd on` (waits until RustDesk is reachable) |
| "turn off / stop it", "I'm done" | `./rd off` |
| "is it running?", "how much burst is left?" | `./rd status` |
| "what's the key?" | `./rd key` |
| "keep it on longer", "stop auto shutdown" | `./rd autostop <minutes>` / `./rd autostop off` (server must be on) |
| "run X on the server" | `./rd ssh '<command>'` |

After helping with a session, remind the user to run `./rd off`, or offer to run it. Auto-shutdown covers them after the idle limit anyway.

## Ask before running

- **`./rd setup`** creates billable AWS resources. Confirm first. It runs `terraform apply`, which prompts interactively, so ask the user to run it themselves with `! ./rd setup`, or pass the confirmation explicitly only if they asked you to.
- **`./rd destroy`** deletes the server **and its key**: every configured client stops working until reconfigured. Confirm explicitly and say that.
- **Never** apply a Terraform change that replaces `aws_lightsail_instance` (watch for "must be replaced" in `terraform plan`). A new instance means a new key. `user_data` is in `ignore_changes` for this reason; don't remove it.

## Setting up a computer someone else uses

`./rd client-setup` prompts for a permanent password. **Don't type or handle the password yourself.** Ask the user to run `! ./rd client-setup`. It writes three double-click files to `out/`: `rustdesk-setup-windows.cmd`, `rustdesk-setup-linux.sh` and `rustdesk-setup-mac.command`. Tell the user which one to send and how the other person opens it (README section 2). Points worth repeating:

- **Windows:** double-click, then Yes. On "Windows protected your PC", click More info → Run anyway.
- **Linux:** right-click → Properties → Executable, then right-click → Run as a Program. Or `bash ~/Downloads/rustdesk-setup-linux.sh` in a terminal.
- **Mac:** double-click. The first time, they need System Settings → Privacy & Security → Open Anyway.
- **Sending:** Gmail and Outlook block `.cmd` attachments, so suggest a Drive/Dropbox link, a messaging app or USB instead.

Every file contains the password. Never print, commit or paste their contents. Re-running a file is safe: it skips the install and reapplies the settings, which is the fix after a server rebuild (new key).

## Troubleshooting

Work through these in order:

1. **Server state:** `./rd status`. If it's stopped, it may have auto-shut down, so `./rd on`.
2. **Ports:** `nc -z -w 3 <ip> 21116` and `21117`. If the instance is running but the ports are closed, check the containers with `./rd ssh 'sudo docker ps -a'` and logs with `./rd ssh 'sudo docker logs hbbs --tail 50'`.
3. **Client config:** in RustDesk's **Settings → Network**, the ID server must be the IP from `./rd status` and the key must match `./rd key` exactly. A "key mismatch" error means the server was rebuilt.
4. **Black screen or no mouse on Linux:** the session is on Wayland. Have them pick "Ubuntu on Xorg" at login (⚙️ icon), or approve the screen-sharing prompt on distros without Xorg.
5. **Windows, can't control admin prompts (UAC):** expected unless RustDesk runs as the installed service. Check that `RustDesk` appears in `services.msc`.
6. **Can see but can't control on Mac:** Accessibility and/or Screen Recording isn't granted to RustDesk in **System Settings → Privacy & Security**.
7. **Remote computer offline:** it's asleep, or the RustDesk service isn't running (`systemctl status rustdesk` on Linux).
8. **Auto-shutdown misbehaving:** `./rd ssh 'systemctl list-timers rustdesk-autostop.timer; journalctl -t rustdesk-autostop'`.
