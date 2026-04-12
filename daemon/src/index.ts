import { loadConfig, rotateToken } from './config.js';
import { startServer, type Server } from './server.js';
import { SessionManager } from './sessions.js';

const VERSION = '0.2.0';

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
  console.log(`  Default agent: ${config.defaultAgent}`);
  console.log(`  ACP path: ${config.acpx.path}`);
  console.log(`  Permission mode: ${config.acpx.permissionMode}`);

  const sessions = new SessionManager(config);

  const server = startServer({
    config,
    onMessage: (ws, msg) => sessions.handleMessage(ws, msg),
    onDisconnect: (ws) => sessions.handleDisconnect(ws),
  });

  let shuttingDown = false;

  const shutdown = async (): Promise<void> => {
    if (shuttingDown) {
      console.log('Force exit.');
      process.exit(1);
    }
    shuttingDown = true;
    console.log('\nShutting down...');
    sessions.destroyAll();
    await server.close();
    process.exit(0);
  };

  // Fallback force exit after 5s
  const forceExit = (): void => {
    setTimeout(() => {
      console.error('Shutdown timed out, forcing exit.');
      process.exit(1);
    }, 5000).unref();
  };

  process.on('SIGTERM', () => { forceExit(); void shutdown(); });
  process.on('SIGINT', () => { forceExit(); void shutdown(); });
}

main();
