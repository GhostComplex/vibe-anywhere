import { loadConfig, rotateToken } from './config.js';
import { startServer, sendError, type Server } from './server.js';
import type { ClientMessage } from './types.js';
import type { WebSocket } from 'ws';

const VERSION = '0.1.0';

function printHelp(): void {
  console.log(`vibe-anywhere v${VERSION}

Usage: vibe-anywhere [options]

Options:
  --help           Show this help message
  --version        Print version
  --rotate-token   Generate a new auth token and exit`);
}

function main(): void {
  const args = process.argv.slice(2);

  if (args.includes('--help')) {
    printHelp();
    process.exit(0);
  }

  if (args.includes('--version')) {
    console.log(VERSION);
    process.exit(0);
  }

  if (args.includes('--rotate-token')) {
    const token = rotateToken();
    console.log(`New token: ${token}`);
    console.log('Update this token in your iOS app.');
    process.exit(0);
  }

  const config = loadConfig();

  console.log(`vibe-anywhere v${VERSION}`);
  console.log(`  Port: ${config.port}`);
  console.log(`  Bind: ${config.bind}`);
  console.log(`  Allowed dirs: ${config.allowedDirs.join(', ')}`);
  console.log(`  Claude path: ${config.claudePath}`);

  const server = startServer({
    config,
    onMessage: (ws: WebSocket, msg: ClientMessage) => {
      // TODO: dispatch to session manager (M1.3, M1.4)
      console.log(`[dispatch] ${msg.type}`);
      sendError(ws, `Not implemented: ${msg.type}`);
    },
  });

  const shutdown = async (): Promise<void> => {
    console.log('\nShutting down...');
    await server.close();
    process.exit(0);
  };

  process.on('SIGTERM', () => void shutdown());
  process.on('SIGINT', () => void shutdown());
}

main();
