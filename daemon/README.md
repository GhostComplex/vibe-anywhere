# vibe-anywhere daemon

WebSocket daemon that bridges mobile clients to Claude Code via ACP.

## Setup

```bash
npm install
```

## Development

```bash
npm run dev
```

## Build & Run

```bash
npm run build
npm start
```

## Configuration

On first run, a config file is created at `~/.vibe-anywhere/config.yaml` with a generated auth token.

```yaml
port: 7842
bind: "0.0.0.0"
token: "<generated>"
allowedDirs:
  - "~/projects"
claudePath: "claude"
```

## Token Management

Rotate the auth token:

```bash
npm start -- --rotate-token
```
