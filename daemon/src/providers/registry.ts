import type { AgentClient } from './types.js';

export type ProviderEventListener = (event: unknown) => void;

/**
 * Registry mapping agent names to provider implementations.
 * Allows multiple providers (ACP, Copilot, etc.) to coexist.
 *
 * Supports an optional onRegister callback so that event listeners
 * are automatically wired for providers registered after construction.
 */
export class ProviderRegistry {
  private providers = new Map<string, AgentClient>();
  private onRegisterListeners: Array<(name: string, client: AgentClient) => void> = [];

  /** Subscribe to be notified when a new provider is registered. */
  onRegister(listener: (name: string, client: AgentClient) => void): void {
    this.onRegisterListeners.push(listener);
  }

  register(name: string, client: AgentClient): void {
    this.providers.set(name, client);
    for (const listener of this.onRegisterListeners) {
      listener(name, client);
    }
  }

  get(name: string): AgentClient | undefined {
    return this.providers.get(name);
  }

  getOrThrow(name: string): AgentClient {
    const client = this.providers.get(name);
    if (!client) {
      throw new Error(`No provider registered for agent "${name}"`);
    }
    return client;
  }

  has(name: string): boolean {
    return this.providers.has(name);
  }

  all(): Map<string, AgentClient> {
    return new Map(this.providers);
  }

  async shutdownAll(): Promise<void> {
    const shutdowns = [...this.providers.values()].map((client) =>
      client.shutdown().catch((err) => {
        console.error(`[registry] Shutdown error for provider "${client.provider}":`, err);
      }),
    );
    await Promise.all(shutdowns);
  }
}
