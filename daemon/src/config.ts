import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import YAML from 'yaml';

export interface Config {
  port: number;
  bind: string;
  token: string;
  allowedDirs: string[];
  defaultAgent: string;
  claudePath?: string;
  permissionMode: 'prompt' | 'approve-all' | 'deny-all';
  timeout: number;
}

const CONFIG_DIR = path.join(os.homedir(), '.vibe-anywhere');
const CONFIG_PATH = path.join(CONFIG_DIR, 'config.yaml');

export function expandTilde(p: string): string {
  if (p.startsWith('~/') || p === '~') {
    return path.join(os.homedir(), p.slice(1));
  }
  return p;
}

function generateToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function writeDefaultConfig(): Config {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });

  const config: Config = {
    port: 7842,
    bind: '0.0.0.0',
    token: generateToken(),
    allowedDirs: ['~/projects'],
    defaultAgent: 'claude',
    permissionMode: 'prompt',
    timeout: 120,
  };

  fs.writeFileSync(CONFIG_PATH, YAML.stringify(config), { mode: 0o600 });
  return config;
}

function validate(raw: Record<string, unknown>): Config {
  if (typeof raw.token !== 'string' || raw.token.length === 0) {
    throw new Error('config: "token" must be a non-empty string');
  }
  if (!Array.isArray(raw.allowedDirs) || raw.allowedDirs.length === 0) {
    throw new Error('config: "allowedDirs" must be a non-empty array of paths');
  }

  const port = typeof raw.port === 'number' ? raw.port : 7842;
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('config: "port" must be an integer between 1 and 65535');
  }

  const bind = typeof raw.bind === 'string' ? raw.bind : '0.0.0.0';
  const defaultAgent = typeof raw.defaultAgent === 'string' ? raw.defaultAgent : 'claude';

  const rawAcpx = (raw.acpx ?? raw) as Record<string, unknown>;
  const permissionMode = (['prompt', 'approve-all', 'deny-all'].includes(rawAcpx.permissionMode as string)
    ? rawAcpx.permissionMode as 'prompt' | 'approve-all' | 'deny-all'
    : 'prompt');
  const timeout = typeof rawAcpx.timeout === 'number' ? rawAcpx.timeout : 120;

  const allowedDirs = (raw.allowedDirs as string[]).map(
    (dir) => path.resolve(expandTilde(dir)),
  );

  const claudePath = typeof raw.claudePath === 'string' ? expandTilde(raw.claudePath) : undefined;

  return { port, bind, token: raw.token, allowedDirs, defaultAgent, claudePath, permissionMode, timeout };
}

export function loadConfig(): Config {
  if (!fs.existsSync(CONFIG_PATH)) {
    const config = writeDefaultConfig();
    console.log(`Created config at ${CONFIG_PATH}`);
    console.log(`Your auth token: ${config.token}`);
    console.log('Copy this token to your iOS app. It will not be shown again.');
    return { ...config, allowedDirs: config.allowedDirs.map((d) => path.resolve(expandTilde(d))) };
  }

  const raw = YAML.parse(fs.readFileSync(CONFIG_PATH, 'utf-8')) as Record<string, unknown>;
  return validate(raw);
}

export function rotateToken(): string {
  const raw = fs.existsSync(CONFIG_PATH)
    ? (YAML.parse(fs.readFileSync(CONFIG_PATH, 'utf-8')) as Record<string, unknown>)
    : {};

  const newToken = generateToken();
  raw.token = newToken;

  fs.mkdirSync(CONFIG_DIR, { recursive: true });
  fs.writeFileSync(CONFIG_PATH, YAML.stringify(raw), { mode: 0o600 });

  return newToken;
}

/** v0.2 placeholder — will concatenate soul + agent + memory + skills */
export function buildSystemPrompt(): string {
  return '';
}
