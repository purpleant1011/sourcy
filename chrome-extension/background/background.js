// Background service worker for Sourcy Chrome Extension
// Handles authentication, API calls, and message routing

const API_BASE_URL = 'https://app.sourcy.com/api/v1';

// State
let authState = {
  isAuthenticated: false,
  accessToken: null,
  refreshToken: null,
  tokenExpiresAt: null,
  userInfo: null
};

let pkceState = {
  codeVerifier: null,
  codeChallenge: null,
  state: null
};

// Initialize extension
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('[Sourcy Background] Extension installed:', details.reason);

  if (details.reason === 'install') {
    // First time install
    await chrome.storage.local.clear();
  } else if (details.reason === 'update') {
    // Extension updated
    console.log('[Sourcy Background] Extension updated to version:', chrome.runtime.getManifest().version);
  }

  // Load saved auth state
  await loadAuthState();
});

// Load auth state from storage
async function loadAuthState() {
  const stored = await chrome.storage.local.get(['authState']);

  if (stored.authState) {
    authState = stored.authState;

    // Check if token is expired
    if (authState.tokenExpiresAt && Date.now() > authState.tokenExpiresAt) {
      console.log('[Sourcy Background] Token expired, refreshing...');
      await refreshAccessToken();
    }
  }
}

// Save auth state to storage
async function saveAuthState() {
  await chrome.storage.local.set({ authState });
}

// Handle messages from content scripts and popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log('[Sourcy Background] Received message:', request.action);

  // Handle async responses
  if (needsAsyncResponse(request.action)) {
    handleAsyncMessage(request, sender).then(sendResponse).catch(error => {
      console.error('[Sourcy Background] Message handler error:', error);
      sendResponse({ error: error.message });
    });
    return true; // Keep message channel open
  }

  // Handle sync responses
  try {
    const response = handleSyncMessage(request, sender);
    sendResponse(response);
  } catch (error) {
    console.error('[Sourcy Background] Message handler error:', error);
    sendResponse({ error: error.message });
  }

  return true;
});

// Check if message needs async response
function needsAsyncResponse(action) {
  const asyncActions = [
    'startAuth',
    'productExtracted',
    'getRecentProducts',
    'getProductStats'
  ];
  return asyncActions.includes(action);
}

// Handle async messages
async function handleAsyncMessage(request, sender) {
  switch (request.action) {
    case 'startAuth':
      return await startOAuthFlow();

    case 'productExtracted':
      return await handleProductExtracted(request.data);

    case 'getRecentProducts':
      return await getRecentProducts(request.limit);

    case 'getProductStats':
      return await getProductStats();

    default:
      throw new Error(`Unknown async action: ${request.action}`);
  }
}

// Handle sync messages
function handleSyncMessage(request, sender) {
  switch (request.action) {
    case 'checkAuth':
      return checkAuthStatus();

    case 'getUserInfo':
      return getUserInfo();

    case 'logout':
      return logout();

    case 'refreshToken':
      // Trigger token refresh (async)
      refreshAccessToken().catch(error => {
        console.error('[Sourcy Background] Token refresh error:', error);
      });
      return { success: true };

    default:
      throw new Error(`Unknown action: ${request.action}`);
  }
}

// Check authentication status
function checkAuthStatus() {
  const isExpired = authState.tokenExpiresAt && Date.now() > authState.tokenExpiresAt;
  return {
    authenticated: authState.isAuthenticated && !isExpired,
    expiresAt: authState.tokenExpiresAt
  };
}

// Get user info
function getUserInfo() {
  if (!authState.isAuthenticated || !authState.userInfo) {
    throw new Error('Not authenticated');
  }

  return authState.userInfo;
}

// Start OAuth2 PKCE flow
async function startOAuthFlow() {
  console.log('[Sourcy Background] Starting OAuth2 PKCE flow');

  // Generate code verifier and challenge
  pkceState.codeVerifier = generateCodeVerifier();
  pkceState.codeChallenge = await generateCodeChallenge(pkceState.codeVerifier);
  pkceState.state = generateState();

  // Store PKCE state
  await chrome.storage.local.set({ pkceState });

  // Build authorization URL
  const authUrl = new URL(`${API_BASE_URL}/auth/authorize`);
  authUrl.searchParams.append('response_type', 'code');
  authUrl.searchParams.append('client_id', 'sourcy-chrome-extension');
  authUrl.searchParams.append('redirect_uri', chrome.identity.getRedirectURL());
  authUrl.searchParams.append('code_challenge', pkceState.codeChallenge);
  authUrl.searchParams.append('code_challenge_method', 'S256');
  authUrl.searchParams.append('state', pkceState.state);

  // Open authorization page
  chrome.tabs.create({ url: authUrl.toString() }, (tab) => {
    console.log('[Sourcy Background] Authorization tab opened');
  });

  return { success: true };
}

// Handle OAuth callback
chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    if (details.url.includes('sourcy.com/oauth/callback')) {
      handleOAuthCallback(details.url);
    }
  },
  { urls: ['<all_urls>'] },
  ['requestBody']
);

// Handle OAuth2 callback
async function handleOAuthCallback(callbackUrl) {
  console.log('[Sourcy Background] Handling OAuth callback');

  try {
    const url = new URL(callbackUrl);
    const code = url.searchParams.get('code');
    const state = url.searchParams.get('state');

    // Verify state
    if (state !== pkceState.state) {
      throw new Error('Invalid state parameter');
    }

    // Exchange code for tokens
    const tokens = await exchangeCodeForTokens(code);

    // Update auth state
    authState.isAuthenticated = true;
    authState.accessToken = tokens.access_token;
    authState.refreshToken = tokens.refresh_token;
    authState.tokenExpiresAt = Date.now() + (tokens.expires_in * 1000);

    // Get user info
    const userInfo = await fetchUserInfo();
    authState.userInfo = userInfo;

    // Save auth state
    await saveAuthState();

    // Close auth tab if exists
    chrome.tabs.query({ url: '*://*/*authorize*' }, (tabs) => {
      tabs.forEach(tab => chrome.tabs.remove(tab.id));
    });

    console.log('[Sourcy Background] Authentication successful');

  } catch (error) {
    console.error('[Sourcy Background] OAuth callback error:', error);
    await logout();
  }
}

// Exchange authorization code for tokens
async function exchangeCodeForTokens(code) {
  const response = await fetch(`${API_BASE_URL}/auth/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code: code,
      code_verifier: pkceState.codeVerifier,
      redirect_uri: chrome.identity.getRedirectURL(),
      client_id: 'sourcy-chrome-extension'
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to exchange code for tokens');
  }

  return await response.json();
}

// Refresh access token
async function refreshAccessToken() {
  console.log('[Sourcy Background] Refreshing access token');

  if (!authState.refreshToken) {
    throw new Error('No refresh token available');
  }

  try {
    const response = await fetch(`${API_BASE_URL}/auth/token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        grant_type: 'refresh_token',
        refresh_token: authState.refreshToken,
        client_id: 'sourcy-chrome-extension'
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'Failed to refresh token');
    }

    const tokens = await response.json();

    // Update auth state with token rotation
    authState.accessToken = tokens.access_token;
    authState.refreshToken = tokens.refresh_token || authState.refreshToken;
    authState.tokenExpiresAt = Date.now() + (tokens.expires_in * 1000);

    await saveAuthState();

    console.log('[Sourcy Background] Token refreshed successfully');

  } catch (error) {
    console.error('[Sourcy Background] Token refresh error:', error);
    await logout();
    throw error;
  }
}

// Fetch user info from API
async function fetchUserInfo() {
  return await apiCall('/user', { method: 'GET' });
}

// Logout
async function logout() {
  console.log('[Sourcy Background] Logging out');

  // Revoke tokens if available
  if (authState.accessToken) {
    try {
      await fetch(`${API_BASE_URL}/auth/revoke`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authState.accessToken}`
        }
      });
    } catch (error) {
      console.error('[Sourcy Background] Revoke token error:', error);
    }
  }

  // Clear auth state
  authState = {
    isAuthenticated: false,
    accessToken: null,
    refreshToken: null,
    tokenExpiresAt: null,
    userInfo: null
  };

  pkceState = {
    codeVerifier: null,
    codeChallenge: null,
    state: null
  };

  await chrome.storage.local.clear();

  return { success: true };
}

// Handle product extracted from content script
async function handleProductExtracted(productData) {
  console.log('[Sourcy Background] Product extracted:', productData);

  if (!authState.isAuthenticated) {
    throw new Error('Not authenticated');
  }

  const response = await apiCall('/products/extract', {
    method: 'POST',
    body: JSON.stringify(productData)
  });

  return { success: true, product: response };
}

// Get recent products
async function getRecentProducts(limit = 5) {
  if (!authState.isAuthenticated) {
    throw new Error('Not authenticated');
  }

  return await apiCall(`/products?limit=${limit}&sort=collected_at:desc`, {
    method: 'GET'
  });
}

// Get product stats
async function getProductStats() {
  if (!authState.isAuthenticated) {
    throw new Error('Not authenticated');
  }

  return await apiCall('/products/stats', {
    method: 'GET'
  });
}

// API call with authentication
async function apiCall(endpoint, options = {}) {
  // Ensure we have a valid token
  if (authState.tokenExpiresAt && Date.now() > authState.tokenExpiresAt) {
    await refreshAccessToken();
  }

  if (!authState.accessToken) {
    throw new Error('No access token available');
  }

  // Build request
  const url = `${API_BASE_URL}${endpoint}`;
  const requestOptions = {
    ...options,
    headers: {
      ...options.headers,
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${authState.accessToken}`
    }
  };

  // Add idempotency key for mutation requests
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(options.method)) {
    requestOptions.headers['Idempotency-Key'] = generateIdempotencyKey();
  }

  const response = await fetch(url, requestOptions);

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || error.message || 'API request failed');
  }

  return await response.json();
}

// Generate code verifier (PKCE)
function generateCodeVerifier() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64UrlEncode(array);
}

// Generate code challenge (PKCE)
async function generateCodeChallenge(codeVerifier) {
  const encoder = new TextEncoder();
  const data = encoder.encode(codeVerifier);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return base64UrlEncode(new Uint8Array(hash));
}

// Generate random state
function generateState() {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return base64UrlEncode(array);
}

// Generate idempotency key
function generateIdempotencyKey() {
  return `${Date.now()}-${crypto.randomUUID()}`;
}

// Base64 URL encode
function base64UrlEncode(data) {
  const base64 = btoa(String.fromCharCode(...data));
  return base64
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// Schedule periodic token refresh
function scheduleTokenRefresh() {
  // Refresh token 5 minutes before expiry
  if (authState.tokenExpiresAt) {
    const refreshAt = authState.tokenExpiresAt - (5 * 60 * 1000);
    const delay = Math.max(0, refreshAt - Date.now());

    setTimeout(async () => {
      try {
        await refreshAccessToken();
      } catch (error) {
        console.error('[Sourcy Background] Scheduled token refresh error:', error);
      }
    }, delay);
  }
}

// Start token refresh scheduling
chrome.alarms.create('tokenRefresh', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'tokenRefresh') {
    scheduleTokenRefresh();
  }
});

// Schedule initial token refresh
scheduleTokenRefresh();
