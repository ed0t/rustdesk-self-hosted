# RustDesk Self-Hosted on AWS Lightsail

A private [RustDesk](https://rustdesk.com) server for remotely helping family and friends, on the smallest AWS Lightsail instance. One script (`./rd`) creates it, turns it on and off, and generates a double-click setup file for the Windows, Linux or Mac computer you support.

> Not affiliated with or endorsed by RustDesk. This repo only automates deploying the official open-source [RustDesk server](https://github.com/rustdesk/rustdesk-server) and [client](https://github.com/rustdesk/rustdesk).

## Installation

### Prerequisites

On your own computer: **macOS**, **Linux**, or **Windows with [WSL](https://learn.microsoft.com/windows/wsl/install)**. On Windows, run `wsl --install` in PowerShell, then follow the Linux steps inside the Ubuntu window. The person you support needs none of this.

- An **AWS account**.
- **Terraform** 1.5+, the **AWS CLI**, `jq` and `nc`. With [Homebrew](https://brew.sh), install them all from the repo folder:
  ```bash
  brew bundle
  ```
  Or install them however you prefer. `bash`, `ssh` and `curl` come with every system.
- The AWS CLI logged in: `aws configure`, or `aws configure sso`. To use a named profile, put it in a `.env` file in the repo folder (gitignored):
  ```bash
  echo 'AWS_PROFILE=<your-profile>' > .env
  ```
  The credentials need Lightsail permissions (`lightsail:*`).

### Create the server

1. Clone this repository and `cd` into it.
2. Optionally pick a region close to you and the people you support:
   ```bash
   cp terraform.tfvars.example terraform.tfvars   # then edit region
   ```
   Defaults are in [`variables.tf`](variables.tf) (`eu-west-2`, London).
3. Create the server:
   ```bash
   ./rd setup
   ```
   Terraform shows what it will create and asks you to confirm. The first boot installs Docker and RustDesk, which takes a few minutes; `setup` waits, prints the **server IP** and **key**, and turns on [auto-shutdown](#auto-shutdown) (60 idle minutes; set `AUTOSTOP_MINUTES=90 ./rd setup` to change it).
4. In RustDesk on your own computer, go to **Settings → Network → ID/Relay server**, enter the IP as the ID server and paste the key.
5. Turn the server off until you need it:
   ```bash
   ./rd off
   ```

> Terraform state is kept locally in `terraform.tfstate` (gitignored). Don't lose it: it's how `./rd` finds your server and how `./rd destroy` knows what to delete.

---

## Guide

### 1. Managing the server

The recommended workflow is to turn the server **on** only when someone needs help, and **off** when you're done. A stopped server isn't exposed to the internet, and auto-shutdown (below) catches the times you forget.

```bash
./rd on        # start the server and wait until RustDesk is reachable (1–3 min)
./rd off       # stop it when you're done
./rd status    # state, IP and remaining CPU burst capacity
```

**Cost:** the default plan (`nano_3_0`, 512 MB RAM, 2 vCPUs, public IPv4) is **$5/month**. The static IP is included, and the plan is billed the same whether the server is on or off. Prices are from [Lightsail pricing](https://aws.amazon.com/lightsail/pricing/) as of November 2026. `./rd destroy` stops all charges.

To see the server key again at any time (it's cached in `.rustdesk/`, so this works while the server is off):

```bash
./rd key
```

#### Auto-shutdown

If you forget `./rd off`, the server powers itself off after **60 minutes** with no relay or SSH connection. To change or disable it (the server must be on):

```bash
./rd autostop 120   # minutes
./rd autostop off
```

Sessions that RustDesk connects **directly** between the two computers don't pass through the server, so it can't see them. They keep working after it shuts down. Sessions going through the relay keep it awake.

### 2. Setting up the computer you support (Windows, Linux or Mac)

> 🧪 **Experimental.** The client setup files are new and haven't been tested on every system and version. If one fails or something is unclear, please [open an issue](../../issues): feedback is very welcome. If a file doesn't work, use the [manual steps](#doing-it-by-hand-instead) below.

You're usually not there in person, so you send them one file that they open. It installs RustDesk if it isn't there yet, points it at your server and sets a permanent password, so you can connect without them clicking "Accept".

**Step 1: generate the files (your machine)**

```bash
./rd client-setup
```

It asks for a permanent password for that computer and writes three files to `out/`, with the server IP, key and password filled in:

| File | For |
|---|---|
| `rustdesk-setup-windows.cmd` | Windows 10/11 |
| `rustdesk-setup-linux.sh` | Linux: Ubuntu, Debian, Mint, Fedora, openSUSE (anything with `apt`, `dnf` or `zypper`) |
| `rustdesk-setup-mac.command` | macOS |

> ⚠️ **Each file contains the password.** Send only the one they need, privately, and have them delete it afterwards.
>
> **Email often won't work:** Gmail and Outlook block `.cmd` attachments, even zipped. Use a shared Google Drive/Dropbox/OneDrive link, a messaging app or a USB stick.

**Step 2: they open it**

They save the file (Downloads is fine), then:

- **Windows:** double-click it and click **Yes** when Windows asks for permission. If a blue *"Windows protected your PC"* box appears, click **More info → Run anyway**. A window shows the progress and stays open at the end.
- **Linux:** right-click the file → **Properties** → turn on **Executable as Program** (wording varies). Then right-click → **Run as a Program**. It opens a terminal window and asks for their password. Linux file managers don't run downloaded files on a plain double-click; that's a security default. If that's fiddly, they can open a terminal (**Ctrl + Alt + T**) and paste `bash ~/Downloads/rustdesk-setup-linux.sh`.
- **Mac:** double-click it. macOS blocks downloaded files from unknown developers the first time: if it says the file can't be opened, they go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, and open the file again. Or they can open Terminal (**Cmd + Space**, type *Terminal*) and paste `bash ~/Downloads/rustdesk-setup-mac.command`. It runs in Terminal and asks for their password.

At the end it shows their **RustDesk ID** (9 digits). They tell you that number.

What else it does on each system:

- **Windows:** turns off sleep.
- **Linux:** enables the RustDesk background service and turns off screen blanking and automatic suspend (GNOME). It also switches the login session from Wayland to Xorg when Xorg is installed, because RustDesk can't reliably control the mouse on Wayland: that shows up as a black screen or no control. Newer distros such as Ubuntu 25.10+ no longer ship Xorg, so there they may have to approve a screen-sharing prompt instead. **They should restart the computer** afterwards.
- **Mac:** turns off system sleep, then opens **System Settings → Privacy & Security** twice. macOS only lets them grant these two permissions by hand: **Accessibility** (to control the mouse and keyboard) and **Screen Recording** (to see the screen). They switch RustDesk **on** in both. If RustDesk asks to install or start its service, they click **Install/Start**.

Running the file again is safe. It skips the install and just reapplies the settings, which is handy after you `./rd destroy` and `./rd setup` again (new key) or change the password.

#### Doing it by hand instead

If the file fails, or you'd rather do it yourself once you're connected:

1. Install RustDesk from the [releases page](https://github.com/rustdesk/rustdesk/releases/latest): `.exe` for Windows, `.dmg` for Mac, `.deb` or `.rpm` for Linux.
2. In RustDesk, **Settings → Network → ID/Relay server**: enter your server IP and key.
3. Set a permanent password: **Settings → Security → Permanent password**.
4. **Windows:** in **Settings → System → Power**, set sleep to **Never**.
5. **Linux:** enable the service with `sudo systemctl enable --now rustdesk`. If the login screen offers it, switch to Xorg: log out, click the username, click the **⚙️** in the bottom-right corner, choose **Ubuntu on Xorg** and log back in. In **Settings → Power**, set **Blank Screen** to **Never** and **Automatic Suspend** to **Off**.
6. **Mac:** in **System Settings → Privacy & Security**, enable RustDesk under **Accessibility** and **Screen Recording**. Under **Battery/Energy**, stop the Mac from sleeping automatically.

### 3. Connecting

1. `./rd on`.
2. Open RustDesk on your computer (already pointed at your server during installation).
3. Enter their RustDesk ID.
4. Enter the permanent password: you're connected without them having to accept.
5. `./rd off` when you're done.

### 4. Connecting from your phone

Saves typing the long key on a phone keyboard.

1. Install **RustDesk** from the App Store or Google Play.
2. On a computer that's already configured with your server, open **Settings → Network** and click the **QR code** icon next to the ID/Relay server fields.
3. On the phone, open the menu → **ID/Relay Server**, tap **Scan QR Code** and point the camera at the screen. The server IP and key are imported; tap **Save**.
4. On the home screen, enter their ID, tap **Connect** and enter the permanent password.

### 5. Controlling someone's Android phone (optional)

On iPhone, Apple only allows viewing the screen, not controlling it. On Android:

1. Install **RustDesk** from Google Play on their phone, go to **ID/Relay Server** and scan the QR code from your computer, as above.
2. Have them grant the two permissions RustDesk asks for:
   - **Screen recording:** tap "Start now" when Android warns that RustDesk will capture the screen.
   - **Input control (Accessibility):** tap the toggle in RustDesk, then in Android settings go to **Installed apps/services → RustDesk** and turn it on.
3. For unattended access: in RustDesk, **Settings → Security**, enable **Unattended access** and set a password. Make sure "Keep service running in the background" is on.

### 6. Removing everything

```bash
./rd destroy
```

This deletes the instance and static IP, so AWS stops billing you for them. The server key is gone too: if you set up again, every client needs the new IP and key.

---

## Reference

### All commands

| Command | What it does |
|---|---|
| `./rd setup` | Create the server with Terraform (safe to re-run: starts a stopped server and keeps your auto-shutdown setting) |
| `./rd on` | Start the server and wait until RustDesk is reachable |
| `./rd off` | Stop the server |
| `./rd status` | State, IP and remaining CPU burst capacity |
| `./rd key` | Print the server key (cached, works while off) |
| `./rd ssh [cmd]` | Shell on the server, using temporary Lightsail credentials (no key pair to manage) |
| `./rd client-setup` | Generate double-click setup files for the computer you support (Windows, Linux, macOS) |
| `./rd autostop <minutes\|off>` | Change or disable auto-shutdown |
| `./rd destroy` | Delete the server and static IP |

### How it works

[`main.tf`](main.tf) creates a Lightsail Ubuntu instance with a static IP and opens the RustDesk ports (TCP 21115–21117, UDP 21116) plus SSH. On first boot it runs `hbbs` (ID server) and `hbbr` (relay) from the official `rustdesk/rustdesk-server` Docker image. Their key pair lives in `/home/ubuntu/rustdesk/data` on the server.

Auto-shutdown is a systemd timer installed by [`server/install-autostop.sh`](server/install-autostop.sh). Every 5 minutes it checks for established connections on TCP 21117 (relay) or 22 (SSH), and runs `poweroff` once there have been none for the limit. Lightsail treats an OS poweroff as a normal stop, so the server needs no AWS credentials.

Edits to the boot script (`user_data`) are deliberately ignored after creation. Applying them would rebuild the instance and generate a new key, which would break every configured client.

### Using with Claude Code

The repo includes a [Claude Code](https://claude.com/claude-code) skill (`.claude/skills/rustdesk`). Open Claude Code in this folder and ask things like "turn on the server", "set up my mum's Mac" or "I get a black screen when I connect". It runs the right `./rd` commands, asks before anything that creates or deletes resources, and leaves password entry to you.

## License

[MIT](LICENSE)
