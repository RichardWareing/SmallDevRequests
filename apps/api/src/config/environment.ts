// Environment Configuration Management for SDR Management System
// Supports Key Vault for production and alternatives for development/testing

import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';

export interface EnvironmentConfig {
  environment: 'development' | 'testing' | 'staging' | 'production';
  azure: {
    subscriptionId: string;
    tenantId: string;
    region: string;
  };
  azureDevOps: {
    organization: string;
    projects: {
      general: string;
      critical: string;
      external: string;
    };
    patToken: string; // From Key Vault in prod, env var in dev
  };
  ai: {
    openAiEndpoint: string;
    openAiKey: string;
    formRecognizerEndpoint: string;
    formRecognizerKey: string;
  };
  storage: {
    accountName: string;
    connectionString: string;
    containers: {
      attachments: string;
      processing: string;
      exports: string;
    };
  };
  teams: {
    appId: string;
    appPassword: string; // From Key Vault in prod
  };
  monitoring: {
    applicationInsightsKey: string;
    logLevel: 'Debug' | 'Information' | 'Warning' | 'Error';
    enableTelemetry: boolean;
  };
  features: {
    enableAiProcessing: boolean;
    enableTeamsBot: boolean;
    enableAdvancedAnalytics: boolean;
    maxFileUploadSize: number;
    approvalThresholdHours: number;
  };
}

// Secret Manager class with fallback strategies
export class SecretManager {
  private keyVaultClient: SecretClient | null = null;
  private environment: string;
  private keyVaultName?: string;

  constructor(environment: string) {
    this.environment = environment;
    this.keyVaultName = process.env.KEY_VAULT_NAME;

    if (this.environment === 'production' && this.keyVaultName) {
      const url = `https://${this.keyVaultName}.vault.azure.net`;
      const credential = new DefaultAzureCredential();
      this.keyVaultClient = new SecretClient(url, credential);
    }
  }

  async getSecret(name: string): Promise<string> {
    // Production: Use Key Vault
    if (this.keyVaultClient) {
      try {
        const secret = await this.keyVaultClient.getSecret(name);
        return secret.value || '';
      } catch (error) {
        console.warn(`Failed to retrieve secret ${name} from Key Vault:`, error);
        // Fall back to environment variables
      }
    }

    // Development/Testing: Use environment variables
    const envVar = process.env[name.toUpperCase().replace(/-/g, '_')];
    if (envVar) {
      return envVar;
    }

    // Final fallback: mock values for CI/testing
    return this.getMockValue(name);
  }

  private getMockValue(name: string): string {
    const mocks: Record<string, string> = {
      'AZURE_DEVOPS_PAT_TOKEN': 'mock-devops-pat',
      'OPENAI_API_KEY': 'mock-openai-key',
      'FORM_RECOGNIZER_KEY': 'mock-fr-key',
      'STORAGE_CONNECTION_STRING': 'UseDevelopmentStorage=true',
      'BOT_APP_PASSWORD': 'mock-bot-password'
    };

    return mocks[name] || `mock-${name}`;
  }

  async setSecret(name: string, value: string): Promise<void> {
    if (this.keyVaultClient) {
      await this.keyVaultClient.setSecret(name, value);
    } else {
      // In development, you might use .env files or local storage
      console.warn(`Setting secrets locally: ${name} = *** ${value.substring(0, 4)}***`);
    }
  }
}

// Configuration Factory
export class ConfigurationService {
  private static cache: Map<string, EnvironmentConfig> = new Map();
  private static secretManager: SecretManager | null = null;

  static async getConfig(environment?: string): Promise<EnvironmentConfig> {
    const env = environment || process.env.NODE_ENV || 'development';

    if (!this.cache.has(env)) {
      const config = await this.loadConfig(env);
      this.cache.set(env, config);
    }

    return this.cache.get(env)!;
  }

  private static async loadConfig(environment: string): Promise<EnvironmentConfig> {
    this.secretManager = new SecretManager(environment);

    const baseConfig: EnvironmentConfig = {
      environment: environment as any,
      azure: {
        subscriptionId: process.env.AZURE_SUBSCRIPTION_ID || '',
        tenantId: process.env.AZURE_TENANT_ID || '',
        region: process.env.AZURE_REGION || 'uksouth'
      },
      azureDevOps: {
        organization: process.env.DEVOPS_ORGANIZATION || 'your-org',
        projects: {
          general: 'SDR-General',
          critical: 'SDR-Critical',
          external: 'SDR-External'
        },
        patToken: await this.secretManager.getSecret('AZURE_DEVOPS_PAT_TOKEN')
      },
      ai: {
        openAiEndpoint: process.env.OPENAI_ENDPOINT || '',
        openAiKey: await this.secretManager.getSecret('OPENAI_API_KEY'),
        formRecognizerEndpoint: process.env.FORM_RECOGNIZER_ENDPOINT || '',
        formRecognizerKey: await this.secretManager.getSecret('FORM_RECOGNIZER_KEY')
      },
      storage: {
        accountName: process.env.STORAGE_ACCOUNT_NAME || '',
        connectionString: await this.secretManager.getSecret('STORAGE_CONNECTION_STRING'),
        containers: {
          attachments: 'sdr-attachments',
          processing: 'ai-processing',
          exports: 'exports'
        }
      },
      teams: {
        appId: process.env.TEAMS_APP_ID || '',
        appPassword: await this.secretManager.getSecret('BOT_APP_PASSWORD')
      },
      monitoring: {
        applicationInsightsKey: process.env.APPLICATIONINSIGHTS_KEY || '',
        logLevel: environment === 'production' ? 'Information' : 'Debug',
        enableTelemetry: true
      },
      features: this.getFeatureFlags(environment)
    };

    return baseConfig;
  }

  private static getFeatureFlags(environment: string) {
    if (environment === 'production') {
      return {
        enableAiProcessing: true,
        enableTeamsBot: true,
        enableAdvancedAnalytics: true,
        maxFileUploadSize: 25 * 1024 * 1024, // 25MB
        approvalThresholdHours: 40
      };
    } else {
      return {
        enableAiProcessing: true,
        enableTeamsBot: false, // May not be configured in dev
        enableAdvancedAnalytics: false,
        maxFileUploadSize: 10 * 1024 * 1024, // 10MB
        approvalThresholdHours: 8
      };
    }
  }

  // Utility methods
  static isProduction(): boolean {
    return process.env.NODE_ENV === 'production';
  }

  static isDevelopment(): boolean {
    return process.env.NODE_ENV === 'development';
  }

  static getSecretManager(): SecretManager | null {
    return this.secretManager;
  }
}

// Environment validation
export function validateConfiguration(config: EnvironmentConfig): string[] {
  const errors: string[] = [];

  // Required fields validation
  if (!config.azureDevOps.organization) {
    errors.push('Azure DevOps organization is required');
  }

  if (!config.ai.openAiEndpoint) {
    errors.push('OpenAI endpoint is required');
  }

  if (config.environment === 'production') {
    // Production-specific validations
    if (!config.keyVaultName) {
      errors.push('Key Vault is required in production');
    }

    if (!config.monitoring.applicationInsightsKey) {
      errors.push('Application Insights key is required in production');
    }
  }

  return errors;
}

// Export default configuration loader
export async function loadEnvironmentConfig(): Promise<EnvironmentConfig> {
  const config = await ConfigurationService.getConfig();
  const errors = validateConfiguration(config);

  if (errors.length > 0) {
    console.error('Configuration validation errors:', errors);
    throw new Error(`Configuration validation failed: ${errors.join(', ')}`);
  }

  return config;
}