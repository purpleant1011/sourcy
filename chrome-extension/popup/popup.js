// Popup script for Sourcy Chrome Extension
// Handles authentication, product list display, and user interactions

(function() {
  'use strict';

  // DOM Elements
  const elements = {
    loadingState: document.getElementById('loading-state'),
    notLoggedInState: document.getElementById('not-logged-in-state'),
    loggedInState: document.getElementById('logged-in-state'),
    errorState: document.getElementById('error-state'),
    userEmail: document.getElementById('user-email'),
    accountName: document.getElementById('account-name'),
    productsCount: document.getElementById('products-count'),
    pendingCount: document.getElementById('pending-count'),
    listedCount: document.getElementById('listed-count'),
    productsList: document.getElementById('products-list'),
    loginBtn: document.getElementById('login-btn'),
    retryBtn: document.getElementById('retry-btn'),
    settingsBtn: document.getElementById('settings-btn'),
    extractCurrentBtn: document.getElementById('extract-current-btn'),
    openDashboardBtn: document.getElementById('open-dashboard-btn'),
    viewAllBtn: document.getElementById('view-all-btn'),
    helpLink: document.getElementById('help-link'),
    docsLink: document.getElementById('docs-link'),
    version: document.getElementById('version'),
    errorText: document.getElementById('error-text')
  };

  // Extension version
  const VERSION = chrome.runtime.getManifest().version;

  // Initialize popup
  async function init() {
    elements.version.textContent = `v${VERSION}`;
    showState('loading');

    try {
      // Check authentication status
      const authStatus = await sendMessage({ action: 'checkAuth' });

      if (authStatus.authenticated) {
        await loadUserDashboard();
      } else {
        showState('not-logged-in');
      }

      // Setup event listeners
      setupEventListeners();

    } catch (error) {
      console.error('[Sourcy Popup] Initialization error:', error);
      showError(error.message);
    }
  }

  // Setup event listeners
  function setupEventListeners() {
    elements.loginBtn.addEventListener('click', handleLogin);
    elements.retryBtn.addEventListener('click', handleRetry);
    elements.settingsBtn.addEventListener('click', openSettings);
    elements.extractCurrentBtn.addEventListener('click', handleExtractCurrent);
    elements.openDashboardBtn.addEventListener('click', openDashboard);
    elements.viewAllBtn.addEventListener('click', viewAllProducts);
    elements.helpLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://docs.sourcy.com/help');
    });
    elements.docsLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://docs.sourcy.com');
    });
  }

  // Handle login
  async function handleLogin() {
    try {
      showState('loading');

      // Start OAuth2 PKCE flow
      const result = await sendMessage({ action: 'startAuth' });

      if (result.success) {
        // Auth URL opened, wait for callback
        pollAuthStatus();
      } else {
        showError(result.error || 'Failed to start authentication');
      }
    } catch (error) {
      console.error('[Sourcy Popup] Login error:', error);
      showError(error.message);
    }
  }

  // Poll for authentication status
  async function pollAuthStatus() {
    const maxAttempts = 30; // 30 seconds timeout
    let attempts = 0;

    const pollInterval = setInterval(async () => {
      attempts++;

      try {
        const authStatus = await sendMessage({ action: 'checkAuth' });

        if (authStatus.authenticated) {
          clearInterval(pollInterval);
          await loadUserDashboard();
        } else if (attempts >= maxAttempts) {
          clearInterval(pollInterval);
          showError('Authentication timeout. Please try again.');
        }
      } catch (error) {
        clearInterval(pollInterval);
        showError(error.message);
      }
    }, 1000);
  }

  // Handle logout
  async function handleLogout() {
    try {
      await sendMessage({ action: 'logout' });
      showState('not-logged-in');
    } catch (error) {
      console.error('[Sourcy Popup] Logout error:', error);
      showError(error.message);
    }
  }

  // Handle retry
  function handleRetry() {
    init();
  }

  // Handle extract current page
  async function handleExtractCurrent() {
    try {
      // Get current tab
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

      if (!tab) {
        showError('No active tab found');
        return;
      }

      // Check if tab is supported platform
      const url = new URL(tab.url);
      if (!isSupportedPlatform(url.hostname)) {
        showError('This page is not supported for extraction');
        return;
      }

      // Send message to content script
      const response = await chrome.tabs.sendMessage(tab.id, { action: 'extractProduct' });

      if (response.success) {
        showNotification('Product extracted successfully!');
        await loadUserDashboard();
      } else {
        showError(response.error || 'Failed to extract product');
      }
    } catch (error) {
      console.error('[Sourcy Popup] Extract error:', error);
      showError(error.message);
    }
  }

  // Load user dashboard
  async function loadUserDashboard() {
    try {
      showState('loading');

      // Get user info
      const userInfo = await sendMessage({ action: 'getUserInfo' });
      elements.userEmail.textContent = userInfo.email;
      elements.accountName.textContent = userInfo.accountName;

      // Get product stats
      const stats = await sendMessage({ action: 'getProductStats' });
      elements.productsCount.textContent = stats.total || 0;
      elements.pendingCount.textContent = stats.pending || 0;
      elements.listedCount.textContent = stats.listed || 0;

      // Get recent products
      const products = await sendMessage({ action: 'getRecentProducts', limit: 5 });
      renderProducts(products);

      showState('logged-in');

    } catch (error) {
      console.error('[Sourcy Popup] Load dashboard error:', error);
      showError(error.message);
    }
  }

  // Render products list
  function renderProducts(products) {
    if (!products || products.length === 0) {
      elements.productsList.innerHTML = `
        <div class="empty-products">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
            <polyline points="7 10 12 15 17 10"></polyline>
            <line x1="12" y1="15" x2="12" y2="3"></line>
          </svg>
          <p>No products collected yet</p>
        </div>
      `;
      return;
    }

    elements.productsList.innerHTML = products.map(product => `
      <div class="product-item" data-product-id="${product.id}">
        <div class="product-image">
          ${product.image ? `<img src="${product.image}" alt="${escapeHtml(product.title)}">` : ''}
        </div>
        <div class="product-info">
          <div class="product-title" title="${escapeHtml(product.title)}">${escapeHtml(product.title)}</div>
          <div class="product-meta">
            <span class="product-platform ${escapeHtml(product.platform)}">${escapeHtml(product.platform)}</span>
            <span class="product-status">
              <span class="status-dot ${product.status}"></span>
              ${escapeHtml(product.status)}
            </span>
          </div>
        </div>
      </div>
    `).join('');
  }

  // Check if URL is supported platform
  function isSupportedPlatform(hostname) {
    const platforms = [
      'taobao.com',
      'tmall.com',
      '1688.com',
      'aliexpress.com',
      'amazon.com',
      'amazon.co.jp',
      'amazon.co.uk',
      'amazon.de'
    ];

    return platforms.some(platform => hostname.includes(platform));
  }

  // Open settings
  function openSettings() {
    chrome.tabs.create({ url: 'settings.html' });
  }

  // Open dashboard
  function openDashboard() {
    chrome.tabs.create({ url: 'https://app.sourcy.com/dashboard' });
  }

  // View all products
  function viewAllProducts() {
    chrome.tabs.create({ url: 'https://app.sourcy.com/products' });
  }

  // Open URL in new tab
  function openUrl(url) {
    chrome.tabs.create({ url: url });
  }

  // Show specific state
  function showState(state) {
    elements.loadingState.classList.add('hidden');
    elements.notLoggedInState.classList.add('hidden');
    elements.loggedInState.classList.add('hidden');
    elements.errorState.classList.add('hidden');

    switch (state) {
      case 'loading':
        elements.loadingState.classList.remove('hidden');
        break;
      case 'not-logged-in':
        elements.notLoggedInState.classList.remove('hidden');
        break;
      case 'logged-in':
        elements.loggedInState.classList.remove('hidden');
        break;
      case 'error':
        elements.errorState.classList.remove('hidden');
        break;
    }
  }

  // Show error message
  function showError(message) {
    elements.errorText.textContent = message;
    showState('error');
  }

  // Show notification
  function showNotification(message) {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = 'notification';
    notification.textContent = message;

    // Add to popup
    document.body.appendChild(notification);

    // Remove after delay
    setTimeout(() => {
      notification.remove();
    }, 3000);
  }

  // Send message to background script
  function sendMessage(message) {
    return new Promise((resolve, reject) => {
      chrome.runtime.sendMessage(message, (response) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
        } else if (response && response.error) {
          reject(new Error(response.error));
        } else {
          resolve(response);
        }
      });
    });
  }

  // Escape HTML to prevent XSS
  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
