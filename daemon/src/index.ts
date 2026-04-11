import { loadConfig, rotateToken } from './config.js';

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

  // TODO: start WebSocket server (M1.2)
  console.log('Server starting...');

  const shutdown = (): void => {
    console.log('\nShutting down...');
    process.exit(0);
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main();
