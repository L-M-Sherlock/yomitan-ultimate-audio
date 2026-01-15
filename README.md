# Local Yomitan Audio Server

**!! Japanese Only !!**

This project runs a fully local Yomitan audio source. It serves audio and optional TTS from your machine without Cloudflare or other hosted services.

## Requirements

- Node.js 18+ and npm
- Local audio data (see below)
- Build tools for native modules (macOS: Xcode Command Line Tools, Windows: Build Tools)

## Setup

### 1) Install dependencies

```
npm install
```

### 2) Prepare audio data

Download the audio data and place it under `data/`. You should have folders like `nhk16_files`, `daijisen_files`, etc. in that directory.

### 3) Initialize the local database

Ensure `data/entry_and_pitch_db.sql` exists, then run:

```
npm run db:init
```

This creates `data/yomitan-audio.db` (configurable via `DB_PATH`).

### 4) Configure environment

Copy `.env.example` to `.env` and update values:

- `AUTHENTICATION_ENABLED` and `API_KEYS`
- `AUDIO_DATA_PATH` and `DB_PATH`
- Optional AWS Polly settings if you want TTS

### 5) Start the server

```
npm run dev
```

Default URL: `http://127.0.0.1:8787`

## Yomitan configuration

Set the Audio Source URL to:

```
http://127.0.0.1:8787/audio/list?term={term}&reading={reading}&apiKey=yourApiKey
```

If authentication is disabled, omit the `apiKey` parameter.

## Notes

- TTS is optional. Set `AWS_POLLY_ENABLED=false` to disable it.
- You can override the SQL path used for initialization with `SQL_PATH`.

## macOS background service (launchd)

Create and load the agent (one-time setup):

```
cat <<'EOF' > ~/Library/LaunchAgents/com.yomitan.audio.local.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.yomitan.audio.local</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>-lc</string>
      <string>cd /Users/jarrettye/Codes/yomitan-ultimate-audio && npm run dev</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/yomitan-audio.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/yomitan-audio.err.log</string>
  </dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yomitan.audio.local.plist
```

Stop the service:

```
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.yomitan.audio.local.plist
```

Logs:

```
tail -n 200 /tmp/yomitan-audio.out.log
tail -n 200 /tmp/yomitan-audio.err.log
```
