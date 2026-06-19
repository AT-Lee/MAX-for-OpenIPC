# MAX for OpenIPC
### Integration of video clip sending from OpenIPC cameras to the MAX messenger (script + web interface)

#### ! Created with the help of GLM-5.x by Z.ai<br>based on the Telegram and ntfy scripts from the OpenIPC project

![OpenIPC](https://img.shields.io/badge/OpenIPC-firmware-blue) ![MAX](https://img.shields.io/badge/MAX-Platform%20API-orange) ![shell](https://img.shields.io/badge/sh-POSIX-grey) ![size](https://img.shields.io/badge/size-7.8%20KB-green)

---

## Description

The script captures a video clip from an OpenIPC camera and sends it to a [MAX](https://max.ru) messenger chat via the official [Platform API](https://dev.max.ru/docs-api). Designed to work with a motion detector: when `max` is triggered, it records a video segment and sends it to MAX. If motion continues — subsequent segments are recorded **without pauses** between them (upload runs in a background process while the next segment is being recorded).

---

## Features

* Protection against simultaneous launches of multiple `max` instances. If a duplicate launch is attempted while recording is in progress — automatic extension (extend) occurs without duplicating frames.

* Capture and upload work in parallel via a file queue. The gap between segments is **less than 1 second**.

* Automatic interruption of recording if free space in `/tmp` drops below a specified percentage (default 10%).

* Configuration of all parameters through the standard OpenIPC web interface (Extensions → MAX).

---

## Files

| File | Path on camera | Size | Purpose |
|------|----------------|------|---------|
| `max` | `/usr/sbin/max` | 3.1 KB | Capture and sending script |
| `max.conf` | `/etc/webui/max.conf` | 147 B | Configuration |
| `ext-max.cgi` | `/var/www/cgi-bin/ext-max.cgi` | 4.6 KB | Web form + webhook |

---

### Required `majestic.yaml` settings
```
hls:
  enabled: true
motionDetect:
  enabled: true
```

---

## Installation

##### 1. Copy files

Copy the files to the camera (e.g., via WinSCP or `scp`):

```
max         ->  /usr/sbin/max
max.conf    ->  /etc/webui/max.conf
ext-max.cgi ->  /var/www/cgi-bin/ext-max.cgi
```

##### 2. Set permissions

Connect to the camera via SSH and run:

```sh
chmod +x /usr/sbin/max
chmod +x /var/www/cgi-bin/ext-max.cgi
```

##### 3. Add to menu (optional)

To add a menu item to the "Extensions" tab, edit the file `/var/www/cgi-bin/p/header.cgi` by adding a new line after line 76:

```html
<li><a class="dropdown-item" href="ext-max.cgi">MAX</a></li>
```
<img width="1568" height="274" alt="image" src="https://github.com/user-attachments/assets/7e4b95d2-898a-435d-9370-b4a1c8033d7e" />

---

## Configuration

All parameters are stored in `/etc/webui/max.conf`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_enabled` | `true` | Main toggle. `false` disables without removing files. |
| `max_token` | — | **Required.** Bot token from MAX BotFather. |
| `max_chat_id` | — | **Required.** Target chat ID (negative for groups). |
| `max_caption` | `%hostname, %datetime` | Caption template. Supports `%hostname`, `%datetime`, `%soctemp`. Segment index `(#N)` is added automatically. |
| `max_video_duration` | `10` | Duration of a single segment in seconds. Range 1–30. Long motion = more segments, not longer segments. |
| `max_min_free_pct` | `10` | Interrupt recording if free space in `/tmp` falls below this percentage. Protects the camera's flash memory. |
| `max_proxy` | (none) | `true` — use SOCKS5 from `/etc/webui/proxy.conf`. |
| `max_interval` | `15` | Interval in minutes for cron-based sending (only when `max_crontab=true`). |
| `max_crontab` | `true` | Add `*/N * * * * /usr/sbin/max` to `/etc/crontabs/root`. |

---

## Usage

### Via motion detector

Add the following to `/usr/sbin/motion.sh`:

```sh
#!/bin/sh
/usr/sbin/max
```

Now, every time the motion detector triggers, the camera launches `max`. If motion continues and the detector fires again — the repeated launch **extends** the already running instance (via the `/tmp/max.extend` flag), and no segments are lost.

### Schedule (cron)

In the web interface, enable **"Add to crontab"** and select the interval.

### Webhook (external trigger)

```sh
curl 'http://<login>:<password>@<camera_ip>/cgi-bin/ext-max.cgi?send=test'
# → OK    (capture and send completed successfully)
# → FAIL  (something went wrong — check the output of /usr/sbin/max via SSH)
```

This is the same endpoint that the **"Send test video"** button in the web interface calls.

### Web interface

Open `http://<camera_ip>/cgi-bin/ext-max.cgi` in your browser. The page includes:

- A yellow warning if `hls` is not enabled in `majestic.yaml`.
- A form with all `max.conf` parameters.
- A **"Send test video"** button.
- A clickable webhook URL (copied on click).
<img width="1153" height="1288" alt="image" src="https://github.com/user-attachments/assets/8abe0f9b-a4d9-4281-846f-7ddab417adfe" />

---

## How It Works

### Architecture

```
┌──────────────── MAIN PROCESS ──────────────────┐
│                                                 │
│  loop:                                          │
│    1. check df /tmp (abort if < %)              │
│    2. curl /video.mp4?duration=N → /tmp/seg     │
│    3. add "path|caption" to queue               │
│    4. if /tmp/max.extend exists:                │
│         delete, repeat loop                     │
│       else:                                     │
│         exit, send DONE signal to worker        │
│                                                 │
└────────────────────┬────────────────────────────┘
                     │ queue file
                     ▼
┌──────────────── UPLOAD WORKER (background) ────┐
│                                                 │
│  loop:                                          │
│    1. read first line from queue                │
│    2. POST /uploads?type=video → {url, token}   │
│    3. POST multipart with file → url            │
│    4. POST /messages with video attachment      │
│    5. retry on attachment.not.ready             │
│    6. remove line from queue, repeat            │
│                                                 │
└─────────────────────────────────────────────────┘
                     ▲
                     │ touch /tmp/max.extend
┌────────────────────┴────────────────────────────┐
│  SECOND CALL to max (while first is running)    │
│    → sets the extend flag, exits immediately    │
└─────────────────────────────────────────────────┘
```

## Credits

- [OpenIPC project](https://github.com/OpenIPC) — the open-source firmware that makes all of this possible.
- [MAX Platform API](https://dev.max.ru/docs-api) — the bot API.
