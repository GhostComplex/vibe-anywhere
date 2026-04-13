import { createServer, type IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { Config } from './config.js';
import { isClientMessage, type ClientMessage, type DaemonMessage } from './types.js';

export interface ServerOptions {
  config: Config;
  onMessage: (ws: WebSocket, msg: ClientMessage) => void;
  onDisconnect?: (ws: WebSocket) => void;
}

export interface Server {
  close(): Promise<void>;
}

export function startServer(opts: ServerOptions): Server {
  const { config, onMessage, onDisconnect } = opts;

  const httpServer = createServer((_req, res) => {
    res.writeHead(404);
    res.end();
  });

  const wss = new WebSocketServer({ noServer: true });

  // Auth on upgrade
  httpServer.on('upgrade', (req: IncomingMessage, socket, head) => {
    const token = extractToken(req);

    if (token !== config.token) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      console.log(`[auth] Rejected connection from ${req.socket.remoteAddress}`);
      return;
    }

    // Extract protocol version from header
    const version = parseInt(req.headers['x-protocol-version'] as string, 10) || 2;
    if (version < 2) {
      socket.write('HTTP/1.1 426 Upgrade Required\r\nX-Protocol-Version: 2\r\n\r\n');
      socket.destroy();
      console.log(`[auth] Rejected v${version} client from ${req.socket.remoteAddress} — v2 required`);
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    const addr = req.socket.remoteAddress ?? 'unknown';
    console.log(`[ws] Client connected: ${addr}`);

    // Send hello so client knows the connection is fully established
    send(ws, { type: 'hello', version: 2 });

    ws.on('message', (data) => {
      const raw = data.toString();
      console.log(`[ws] Received from ${addr}: ${raw.substring(0, 200)}`);
      let parsed: unknown;
      try {
        parsed = JSON.parse(raw);
      } catch {
        sendError(ws, 'Invalid JSON');
        return;
      }

      if (!isClientMessage(parsed)) {
        sendError(ws, `Unknown message type: ${(parsed as { type?: string })?.type ?? 'missing'}`);
        return;
      }

      onMessage(ws, parsed);
    });

    ws.on('close', () => {
      console.log(`[ws] Client disconnected: ${addr}`);
      onDisconnect?.(ws);
    });

    ws.on('error', (err) => {
      console.error(`[ws] Error from ${addr}:`, err.message);
    });

    // Ping/pong keepalive
    ws.on('pong', () => {
      (ws as WebSocket & { isAlive: boolean }).isAlive = true;
    });
    (ws as WebSocket & { isAlive: boolean }).isAlive = true;
  });

  // Keepalive interval — ping every 30s, drop dead connections
  const pingInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
      const client = ws as WebSocket & { isAlive: boolean };
      if (!client.isAlive) {
        client.terminate();
        return;
      }
      client.isAlive = false;
      client.ping();
    });
  }, 30_000);

  httpServer.listen(config.port, config.bind, () => {
    console.log(`[ws] Listening on ${config.bind}:${config.port}`);
  });

  return {
    async close(): Promise<void> {
      clearInterval(pingInterval);
      // Force-close all WebSocket clients
      for (const client of wss.clients) {
        client.terminate();
      }
      return new Promise((resolve, reject) => {
        wss.close(() => {
          httpServer.close((err) => {
            if (err) reject(err);
            else resolve();
          });
        });
      });
    },
  };
}

export function send(ws: WebSocket, msg: DaemonMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

export function sendError(ws: WebSocket, message: string): void {
  send(ws, { type: 'error', message });
}

function extractToken(req: IncomingMessage): string | null {
  const auth = req.headers.authorization;
  if (!auth) return null;
  const parts = auth.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') return null;
  return parts[1];
}
