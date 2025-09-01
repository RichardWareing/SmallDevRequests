// Secret Management Helpers
// Provides utilities for secure secret handling across environments

import { SecretManager } from './environment';

// Environment Variables Manager
export class EnvironmentVariablesManager {
  private static readonly sensitiveKeys = [
    'AZURE_DEVOPS_PAT_TOKEN',
    'OPENAI_API_KEY',
    'FORM_RECOGNIZER_KEY',
    'STORAGE_CONNECTION_STRING',
    'BOT_APP_PASSWORD',
    'APPLICATIONINSIGHTS_KEY'
  ];

  static isSensitiveKey(key: string): boolean {
    return this.sensitiveKeys.includes(key.toUpperCase());
  }

  static maskSensitiveValue(value: string): string {
    if (!value) return '';
    if (value.length <= 4) return '*'.repeat(value.length);
    return value.substring(0, 4) + '*'.repeat(value.length - 4);
  }

  static sanitizeEnvironmentVariables(): Record<string, string> {
    const sanitized: Record<string, string> = {};

    Object.keys(process.env).forEach(key => {
      const value = process.env[key] || '';
      if (this.isSensitiveKey(key)) {
        sanitized[key] = this.maskSensitiveValue(value);
      } else {
        sanitized[key] = value;
      }
    });

    return sanitized;
  }

  static validateEnvironmentVariables(requiredVars: string[]): string[] {
    const missing: string[] = [];
    const warnings: string[] = [];

    requiredVars.forEach(varName => {
      if (!process.env[varName]) {
        missing.push(varName);
      }
    });

    // Additional validations
    if (process.env.NODE_ENV === 'production') {
      if (!process.env.KEY_VAULT_NAME) {
        warnings.push('KEY_VAULT_NAME is recommended for production');
      }
      if (!process.env.APPLICATIONINSIGHTS_KEY) {
        warnings.push('APPLICATIONINSIGHTS_KEY is recommended for production');
      }
    }

    return [...missing, ...warnings];
  }
}

// Secret Rotation Manager
export class SecretRotationManager {
  private static rotationSchedule: NodeJS.Timeout | null = null;

  static startPeriodicRotation(secretManager: SecretManager, intervalHours: number = 24): void {
    if (this.rotationSchedule) {
      clearInterval(this.rotationSchedule);
    }

    const intervalMs = intervalHours * 60 * 60 * 1000;

    this.rotationSchedule = setInterval(async () => {
      try {
        await this.rotateSecrets(secretManager);
        console.log('Secret rotation completed successfully');
      } catch (error) {
        console.error('Secret rotation failed:', error);
      }
    }, intervalMs);

    console.log(`Secret rotation scheduled every ${intervalHours} hours`);
  }

  static stopPeriodicRotation(): void {
    if (this.rotationSchedule) {
      clearInterval(this.rotationSchedule);
      this.rotationSchedule = null;
      console.log('Secret rotation stopped');
    }
  }

  private static async rotateSecrets(secretManager: SecretManager): Promise<void> {
    const secretsToRotate = [
      'AZURE_DEVOPS_PAT_TOKEN',
      'OPENAI_API_KEY',
      'FORM_RECOGNIZER_KEY'
    ];

    for (const secretName of secretsToRotate) {
      const currentValue = await secretManager.getSecret(secretName);

      // In a real implementation, this would generate new tokens/keys
      // For now, just log the rotation
      console.log(`Rotated secret: ${secretName}`);

      // Update the secret store
      await secretManager.setSecret(`${secretName}_old`, currentValue);
      // Generate new value would happen here
      // await secretManager.setSecret(secretName, newValue);
    }
  }
}

// Configuration Validator
export class ConfigurationValidator {
  static validateAzureConfiguration(config: any): string[] {
    const errors: string[] = [];

    // Azure DevOps validation
    if (!config.azureDevOps?.organization) {
      errors.push('Azure DevOps organization is required');
    }

    if (!config.azureDevOps?.patToken || config.azureDevOps.patToken.startsWith('mock')) {
      if (process.env.NODE_ENV === 'production') {
        errors.push('Valid Azure DevOps PAT token is required in production');
      }
    }

    // Storage validation
    if (!config.storage?.connectionString) {
      errors.push('Storage connection string is required');
    }

    // AI services validation
    if (config.features?.enableAiProcessing) {
      if (!config.ai?.openAiKey || config.ai.openAiKey.startsWith('mock')) {
        errors.push('Valid OpenAI API key is required when AI processing is enabled');
      }
    }

    // Teams validation
    if (config.features?.enableTeamsBot) {
      if (!config.teams?.appId) {
        errors.push('Teams app ID is required when Teams bot is enabled');
      }
      if (!config.teams?.appPassword || config.teams.appPassword.startsWith('mock')) {
        if (process.env.NODE_ENV === 'production') {
          errors.push('Valid Teams app password is required in production');
        }
      }
    }

    return errors;
  }

  static generateConfigurationReport(config: any): void {
    const report = {
      environment: config.environment,
      timestamp: new Date().toISOString(),
      validations: this.validateAzureConfiguration(config),
      featureFlags: Object.entries(config.features || {}),
      security: {
        usingKeyVault: !!process.env.KEY_VAULT_NAME,
        sensitiveVarsMasked: EnvironmentVariablesManager.sanitizeEnvironmentVariables(),
        monitoringEnabled: !!config.monitoring?.enableTelemetry
      }
    };

    console.log('Configuration Report:', JSON.stringify(report, null, 2));
  }
}

// Development helpers
export class DevelopmentHelpers {
  private static isDevelopment: boolean;

  static setDevelopmentMode(isDev: boolean): void {
    this.isDevelopment = isDev;
  }

  static async loadDevelopmentSecrets(): Promise<Record<string, string>> {
    if (!this.isDevelopment) return {};

    try {
      // In development, you might load from a .env file or other sources
      const dotenv = await import('dotenv');
      dotenv.config();

      const secrets: Record<string, string> = {};
      const sensitiveKeys = EnvironmentVariablesManager.sanitizeEnvironmentVariables();

      Object.keys(sensitiveKeys).forEach(key => {
        if (sensitiveKeys[key] !== '***masked***') {
          secrets[key] = sensitiveKeys[key];
        }
      });

      return secrets;
    } catch (error) {
      console.warn('Failed to load development secrets:', error);
      return {};
    }
  }

  static generateDevEnvironmentFile(): string {
    return `# Development Environment Variables
# Copy to .env and fill in values

NODE_ENV=development
PORT=3001

# Azure Configuration
AZURE_SUBSCRIPTION_ID=
AZURE_TENANT_ID=
AZURE_REGION=uksouth

# Azure DevOps
DEVOPS_ORGANIZATION=your-devops-org
AZURE_DEVOPS_PAT_TOKEN=your-pat-token

# AI Services
OPENAI_ENDPOINT=
OPENAI_API_KEY=
FORM_RECOGNIZER_ENDPOINT=
FORM_RECOGNIZER_KEY=

# Storage
STORAGE_ACCOUNT_NAME=
STORAGE_CONNECTION_STRING=

# Teams Bot
TEAMS_APP_ID=
BOT_APP_PASSWORD=

# Monitoring
APPLICATIONINSIGHTS_KEY=

# Key Vault (leave empty for dev, required in prod)
KEY_VAULT_NAME=
`;
  }
}

// Export utility functions
export const configurationUtils = {
  validateEnvVars: EnvironmentVariablesManager.validateEnvironmentVariables,
  isSensitive: EnvironmentVariablesManager.isSensitiveKey,
  maskValue: EnvironmentVariablesManager.maskSensitiveValue,
  startRotation: SecretRotationManager.startPeriodicRotation,
  generateReport: ConfigurationValidator.generateConfigurationReport,
  loadDevSecrets: DevelopmentHelpers.loadDevelopmentSecrets,
  generateDevEnvFile: DevelopmentHelpers.generateDevEnvironmentFile
};