// Settings script for Sourcy Chrome Extension
// Handles settings page functionality

(function() {
  'use strict';

  // DOM Elements
  const elements = {
    closeBtn: document.getElementById('close-btn'),
    userEmail: document.getElementById('user-email'),
    accountName: document.getElementById('account-name'),
    accountId: document.getElementById('account-id'),
    planName: document.getElementById('plan-name'),
    apiKey: document.getElementById('api-key'),
    accountStatus: document.getElementById('account-status'),
    manageAccountBtn: document.getElementById('manage-account-btn'),
    logoutBtn: document.getElementById('logout-btn'),
    autoExtractToggle: document.getElementById('auto-extract-toggle'),
    notificationsToggle: document.getElementById('notifications-toggle'),
    soundToggle: document.getElementById('sound-toggle'),
    platformToggles: document.querySelectorAll('input[name="platform"]'),
    analyticsToggle: document.getElementById('analytics-toggle'),
    clearCacheBtn: document.getElementById('clear-cache-btn'),
    exportDataBtn: document.getElementById('export-data-btn'),
    deleteDataBtn: document.getElementById('delete-data-btn'),
    helpLink: document.getElementById('help-link'),
    docsLink: document.getElementById('docs-link'),
    feedbackLink: document.getElementById('feedback-link'),
    privacyLink: document.getElementById('privacy-link'),
    termsLink: document.getElementById('terms-link'),
    version: document.getElementById('version'),
    build: document.getElementById('build')
  };

  // Initialize settings
  async function init() {
    console.log('[Sourcy Settings] Initializing');

    // Set version info
    elements.version.textContent = chrome.runtime.getManifest().version;
    elements.build.textContent = chrome.runtime.getManifest().version_name || 'development';

    // Setup event listeners
    setupEventListeners();

    // Load user info
    await loadUserInfo();

    // Load settings
    await loadSettings();
  }

  // Setup event listeners
  function setupEventListeners() {
    // Close button
    elements.closeBtn.addEventListener('click', () => {
      window.close();
    });

    // Account actions
    elements.manageAccountBtn.addEventListener('click', manageAccount);
    elements.logoutBtn.addEventListener('click', handleLogout);

    // Settings toggles
    elements.autoExtractToggle.addEventListener('change', (e) => {
      saveSetting('autoExtract', e.target.checked);
    });

    elements.notificationsToggle.addEventListener('change', (e) => {
      saveSetting('notifications', e.target.checked);
    });

    elements.soundToggle.addEventListener('change', (e) => {
      saveSetting('sound', e.target.checked);
    });

    elements.analyticsToggle.addEventListener('change', (e) => {
      saveSetting('analytics', e.target.checked);
    });

    // Platform toggles
    elements.platformToggles.forEach(toggle => {
      toggle.addEventListener('change', async () => {
        const platforms = Array.from(document.querySelectorAll('input[name="platform"]:checked'))
          .map(input => input.value);
        await saveSetting('platforms', platforms);
      });
    });

    // Data & privacy actions
    elements.clearCacheBtn.addEventListener('click', clearCache);
    elements.exportDataBtn.addEventListener('click', exportData);
    elements.deleteDataBtn.addEventListener('click', deleteAllData);

    // Support links
    elements.helpLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://docs.sourcy.com/help');
    });

    elements.docsLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://docs.sourcy.com');
    });

    elements.feedbackLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://sourcy.com/feedback');
    });

    elements.privacyLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://sourcy.com/privacy');
    });

    elements.termsLink.addEventListener('click', (e) => {
      e.preventDefault();
      openUrl('https://sourcy.com/terms');
    });
  }

  // Load user info
  async function loadUserInfo() {
    try {
      const userInfo = await sendMessage({ action: 'getUserInfo' });

      if (userInfo) {
        elements.userEmail.textContent = userInfo.email || '-';
        elements.accountName.textContent = userInfo.accountName || '-';
        elements.accountId.textContent = userInfo.accountId || '-';
        elements.planName.textContent = userInfo.plan || '-';
        elements.apiKey.textContent = maskApiKey(userInfo.apiKey) || '-';
        elements.accountStatus.textContent = userInfo.status || '-';
      }
    } catch (error) {
      console.error('[Sourcy Settings] Failed to load user info:', error);
      showNotification('Failed to load user information', 'error');
    }
  }

  // Load settings
  async function loadSettings() {
    try {
      const settings = await chrome.storage.local.get('settings');

      if (settings.settings) {
        elements.autoExtractToggle.checked = settings.settings.autoExtract || false;
        elements.notificationsToggle.checked = settings.settings.notifications !== false;
        elements.soundToggle.checked = settings.settings.sound || false;
        elements.analyticsToggle.checked = settings.settings.analytics !== false;

        // Platform settings
        const platforms = settings.settings.platforms || ['taobao', 'tmall', 'aliexpress', 'amazon', '1688'];
        elements.platformToggles.forEach(toggle => {
          toggle.checked = platforms.includes(toggle.value);
        });
      }
    } catch (error) {
      console.error('[Sourcy Settings] Failed to load settings:', error);
    }
  }

  // Save setting
  async function saveSetting(key, value) {
    try {
      const settings = (await chrome.storage.local.get('settings')).settings || {};
      settings[key] = value;

      await chrome.storage.local.set({ settings });
      console.log('[Sourcy Settings] Setting saved:', key, value);

      showNotification('Setting saved');
    } catch (error) {
      console.error('[Sourcy Settings] Failed to save setting:', error);
      showNotification('Failed to save setting', 'error');
    }
  }

  // Manage account
  function manageAccount() {
    openUrl('https://app.sourcy.com/account');
  }

  // Handle logout
  async function handleLogout() {
    if (!confirm('Are you sure you want to logout?')) {
      return;
    }

    try {
      await sendMessage({ action: 'logout' });
      showNotification('Logged out successfully');

      // Close settings window after delay
      setTimeout(() => {
        window.close();
      }, 1000);
    } catch (error) {
      console.error('[Sourcy Settings] Logout error:', error);
      showNotification('Failed to logout', 'error');
    }
  }

  // Clear cache
  async function clearCache() {
    if (!confirm('Clear extension cache?')) {
      return;
    }

    try {
      await chrome.storage.local.remove(['cache', 'productsCache']);
      showNotification('Cache cleared');
    } catch (error) {
      console.error('[Sourcy Settings] Clear cache error:', error);
      showNotification('Failed to clear cache', 'error');
    }
  }

  // Export data
  async function exportData() {
    if (!confirm('Export extension data?')) {
      return;
    }

    try {
      const data = await chrome.storage.local.get(null);

      // Remove sensitive data
      delete data.authState;
      delete data.pkceState;

      // Create export object
      const exportData = {
        settings: data.settings,
        cache: data.cache,
        productsCache: data.productsCache,
        exportedAt: new Date().toISOString(),
        version: chrome.runtime.getManifest().version
      };

      // Download as JSON
      const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = url;
      a.download = `sourcy-export-${Date.now()}.json`;
      a.click();

      URL.revokeObjectURL(url);
      showNotification('Data exported');
    } catch (error) {
      console.error('[Sourcy Settings] Export data error:', error);
      showNotification('Failed to export data', 'error');
    }
  }

  // Delete all data
  async function deleteAllData() {
    if (!confirm('Are you sure you want to delete all data? This cannot be undone.')) {
      return;
    }

    if (!confirm('This will delete all settings, cache, and local data. Continue?')) {
      return;
    }

    try {
      await chrome.storage.local.clear();
      showNotification('All data deleted');

      // Close settings window after delay
      setTimeout(() => {
        window.close();
      }, 1000);
    } catch (error) {
      console.error('[Sourcy Settings] Delete data error:', error);
      showNotification('Failed to delete data', 'error');
    }
  }

  // Open URL
  function openUrl(url) {
    chrome.tabs.create({ url });
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

  // Mask API key for display
  function maskApiKey(apiKey) {
    if (!apiKey) return '-';
    if (apiKey.length <= 8) return apiKey;

    return apiKey.substring(0, 4) + '...' + apiKey.substring(apiKey.length - 4);
  }

  // Show notification
  function showNotification(message, type = 'success') {
    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    notification.textContent = message;

    Object.assign(notification.style, {
      position: 'fixed',
      bottom: '24px',
      right: '24px',
      backgroundColor: type === 'error' ? '#EF4444' : '#10B981',
      color: 'white',
      padding: '12px 20px',
      borderRadius: '8px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      fontSize: '14px',
      fontWeight: '500',
      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
      animation: 'slideIn 0.3s ease',
      zIndex: '9999'
    });

    document.body.appendChild(notification);

    setTimeout(() => {
      notification.style.animation = 'slideOut 0.3s ease';
      setTimeout(() => notification.remove(), 300);
    }, 3000);
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Add animation styles
  const style = document.createElement('style');
  style.textContent = `
    @keyframes slideIn {
      from {
        transform: translateX(400px);
        opacity: 0;
      }
      to {
        transform: translateX(0);
        opacity: 1;
      }
    }

    @keyframes slideOut {
      from {
        transform: translateX(0);
        opacity: 1;
      }
      to {
        transform: translateX(400px);
        opacity: 0;
      }
    }
  `;
  document.head.appendChild(style);

})();
