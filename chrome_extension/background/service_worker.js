// Sourcy Chrome Extension — Service Worker (Background)
// Handles JWT auth, API communication, and message routing

const API_BASE = 'https://app.sourcy.kr/api/v1';

// ============================================================
// Auth Token Management
// ============================================================

async function getAuthToken() {
  const { jwt, jwt_expires_at } = await chrome.storage.local.get(['jwt', 'jwt_expires_at']);

  // If token exists and not expiring within 5 minutes, return it
  if (jwt && jwt_expires_at && Date.now() < jwt_expires_at - 300_000) {
    return jwt;
  }

  // Try to refresh
  return await refreshToken();
}

async function refreshToken() {
  const { refresh_token } = await chrome.storage.local.get(['refresh_token']);
  if (!refresh_token) {
    throw new Error('AUTH_REQUIRED');
  }

  try {
    const response = await fetch(`${API_BASE}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token })
    });

    if (!response.ok) {
      await chrome.storage.local.remove(['jwt', 'jwt_expires_at', 'refresh_token', 'user']);
      throw new Error('AUTH_EXPIRED');
    }

    const data = await response.json();
    await chrome.storage.local.set({
      jwt: data.data.jwt,
      jwt_expires_at: data.data.expires_at * 1000, // Convert to ms
      refresh_token: data.data.refresh_token
    });

    return data.data.jwt;
  } catch (error) {
    await chrome.storage.local.remove(['jwt', 'jwt_expires_at', 'refresh_token', 'user']);
    throw error;
  }
}

// ============================================================
// API Communication
// ============================================================

async function apiRequest(method, path, body = null) {
  const token = await getAuthToken();

  const options = {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-Idempotency-Key': crypto.randomUUID()
    }
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(`${API_BASE}${path}`, options);
  const data = await response.json();

  if (!response.ok) {
    throw { status: response.status, ...data };
  }

  return data;
}

async function collectProduct(metadata) {
  return apiRequest('POST', '/source_products', { source_product: metadata });
}

async function checkProductStatus(productId) {
  return apiRequest('GET', `/source_products/${productId}`);
}

async function bulkCollect(products) {
  return apiRequest('POST', '/source_products/bulk_import', { products });
}

// ============================================================
// Message Routing
// ============================================================

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const handlers = {
    // Auth
    'LOGIN': async () => {
      const { email, password } = msg;
      const response = await fetch(`${API_BASE}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      const data = await response.json();

      if (response.ok && data.success) {
        await chrome.storage.local.set({
          jwt: data.data.jwt,
          jwt_expires_at: data.data.expires_at * 1000,
          refresh_token: data.data.refresh_token,
          user: data.data.user
        });
      }
      return data;
    },

    'LOGOUT': async () => {
      try {
        await apiRequest('DELETE', '/auth/logout');
      } catch (e) {
        // Ignore logout API errors
      }
      await chrome.storage.local.remove(['jwt', 'jwt_expires_at', 'refresh_token', 'user']);
      return { success: true };
    },

    'GET_AUTH_STATUS': async () => {
      const { jwt, user } = await chrome.storage.local.get(['jwt', 'user']);
      return { authenticated: !!jwt, user: user || null };
    },

    // Product collection
    'API_COLLECT': async () => {
      return await collectProduct(msg.metadata);
    },

    'API_BULK_COLLECT': async () => {
      return await bulkCollect(msg.products);
    },

    'API_CHECK_STATUS': async () => {
      return await checkProductStatus(msg.product_id);
    },

    // Trigger content script collection from popup
    'TRIGGER_COLLECT': async () => {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab?.id) throw new Error('No active tab');

      const response = await chrome.tabs.sendMessage(tab.id, {
        type: 'COLLECT_PRODUCT',
        include_html: msg.include_html || false
      });

      if (!response?.success) {
        throw new Error(response?.error || 'Collection failed');
      }

      // Send to API
      return await collectProduct(response.metadata);
    }
  };

  const handler = handlers[msg.type];
  if (handler) {
    handler()
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({
        success: false,
        error: error.message || error.error?.message || 'Unknown error'
      }));
    return true; // Keep channel open for async
  }
});

// ============================================================
// Badge / Icon Updates
// ============================================================

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'PRODUCT_PAGE_DETECTED') {
    // Show green badge when on a supported product page
    chrome.action.setBadgeText({ text: '●' });
    chrome.action.setBadgeBackgroundColor({ color: '#22c55e' });
  }
});

// Clear badge when navigating away
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === 'loading') {
    chrome.action.setBadgeText({ text: '' });
  }
});
