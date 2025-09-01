// MSAL Configuration - Environment-specific settings
// These values should be populated from environment variables or configuration

export const msalConfig = {
  auth: {
    clientId: process.env.VITE_AZURE_AD_CLIENT_ID || 'your-client-id',
    authority: `https://login.microsoftonline.com/${process.env.VITE_AZURE_AD_TENANT_ID || 'your-tenant-id'}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
    navigateToLoginRequestUrl: false,
  },
  // Cache configuration
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  // System configuration
  system: {
    allowNativeBroker: false,
    loggerOptions: {
      loggerCallback: (level: any, message: string, containsPii: boolean) => {
        if (containsPii) return;
        switch (level) {
          case 0: console.error(message); break;
          case 1: console.warn(message); break;
          case 2: console.info(message); break;
          case 3: console.debug(message); break;
        }
      },
      logLevel: process.env.NODE_ENV === 'development' ? 2 : 1,
    },
  },
};

// Environment-specific configurations
export const getMsalConfig = () => {
  const isDevelopment = process.env.NODE_ENV === 'development';
  const isProduction = process.env.NODE_ENV === 'production';

  if (isDevelopment) {
    return {
      ...msalConfig,
      system: {
        ...msalConfig.system,
        loggerOptions: {
          ...msalConfig.system.loggerOptions,
          logLevel: 2, // Info level for dev
        },
      },
    };
  }

  if (isProduction) {
    return {
      ...msalConfig,
      cache: {
        ...msalConfig.cache,
        cacheLocation: 'localStorage', // More persistent in prod
      },
    };
  }

  return msalConfig;
};