// MSAL (Microsoft Authentication Library) Configuration
// Handles Azure AD authentication across environments

import { PublicClientApplication, Configuration, LogLevel } from '@azure/msal-browser';
import { msalConfig } from './msal-config';

// Environment-specific authentication configuration
const getMsalConfig = (): Configuration => {
  const config: Configuration = {
    ...msalConfig,
    cache: {
      cacheLocation: 'sessionStorage',
      storeAuthStateInCookie: false,
    },
    system: {
      loggerOptions: {
        loggerCallback: (level: LogLevel, message: string, containsPii: boolean) => {
          if (containsPii) {
            return;
          }
          switch (level) {
            case LogLevel.Error:
              console.error(message);
              break;
            case LogLevel.Info:
              console.info(message);
              break;
            case LogLevel.Verbose:
              console.debug(message);
              break;
            case LogLevel.Warning:
              console.warn(message);
              break;
          }
        },
        logLevel: process.env.NODE_ENV === 'development' ? LogLevel.Info : LogLevel.Warning,
      },
    },
  };

  return config;
};

// Create MSAL instance
export const msalInstance = new PublicClientApplication(getMsalConfig());

// Login request configuration
export const loginRequest = {
  scopes: [
    'User.Read',
    'User.ReadBasic.All',
    'openid',
    'profile',
    'email',
    'https://management.azure.com/user_impersonation' // For Azure DevOps API access
  ]
};

// Token request configuration (for acquiring tokens silently)
export const tokenRequest = {
  scopes: [
    'https://management.azure.com/user_impersonation',
    'https://dev.azure.com/.default'
  ],
  forceRefresh: false
};

// Authentication result interface
export interface AuthenticationResult {
  account: any;
  idToken: string;
  accessToken: string;
  scopes: string[];
}

// Helper function to get active account
export const getActiveAccount = () => {
  const accounts = msalInstance.getAllAccounts();
  if (accounts.length === 0) {
    return null;
  }
  return accounts[0];
};

// Helper function to get token silently
export const getTokenSilently = async (scopes: string[] = tokenRequest.scopes) => {
  const account = getActiveAccount();
  if (!account) {
    throw new Error('No active account found');
  }

  const request = {
    scopes,
    account: account,
  };

  const response = await msalInstance.acquireTokenSilent(request);
  return response.accessToken;
};

// Helper function to get user info
export const getUserInfo = () => {
  const account = getActiveAccount();
  if (!account) {
    return null;
  }

  return {
    id: account.localAccountId,
    name: account.name,
    username: account.username,
    email: account.username, // Usually the email in username for AAD
  };
};

// Helper function to sign out
export const signOut = () => {
  const account = getActiveAccount();
  if (account) {
    msalInstance.logoutRedirect({
      account: account,
      postLogoutRedirectUri: window.location.origin
    });
  }
};