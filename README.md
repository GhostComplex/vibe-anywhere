# Vibe Anywhere

Control Claude Code from your phone. Lightweight daemon + iOS app.

```
[iOS App] ←WebSocket→ [TS Daemon] ←ACP/stdio→ [claude --acp]
```

## What

- Start Claude Code sessions in any project directory from your iPhone
- Stream responses and tool use in real-time
- Secure: Tailscale + bearer token, no cloud relay
- Tiny: ~1500 LOC total

## Structure

```
daemon/    # TypeScript, Node.js — WebSocket server + ACP bridge
app/       # Swift, SwiftUI — iOS client
docs/      # Design documents and PRDs
```

## Status

🚧 Under development — see [docs/prd/PRD-mvp.md](docs/prd/PRD-mvp.md) for the design spec.

## License

MIT
