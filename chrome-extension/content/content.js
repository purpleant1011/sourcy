// Content script for product extraction from e-commerce sites
// Supports: Taobao, AliExpress, 1688, Amazon

(function() {
  'use strict';

  // Platform detection
  const PLATFORMS = {
    TAOBAO: 'taobao',
    ALIEXPRESS: 'aliexpress',
    TMALL: 'tmall',
    AMAZON: 'amazon',
    AMAZON_JP: 'amazon_jp'
  };

  // Current platform
  let currentPlatform = null;

  // Initialize content script
  function init() {
    currentPlatform = detectPlatform();
    if (currentPlatform) {
      console.log('[Sourcy Extension] Platform detected:', currentPlatform);
      setupExtraction();
    }
  }

  // Detect current platform from URL
  function detectPlatform() {
    const hostname = window.location.hostname.toLowerCase();

    if (hostname.includes('taobao.com')) {
      return PLATFORMS.TAOBAO;
    } else if (hostname.includes('tmall.com')) {
      return PLATFORMS.TMALL;
    } else if (hostname.includes('aliexpress.com')) {
      return PLATFORMS.ALIEXPRESS;
    } else if (hostname.includes('1688.com')) {
      return PLATFORMS.TAOBAO; // 1688 uses similar structure
    } else if (hostname.includes('amazon.com')) {
      return PLATFORMS.AMAZON;
    } else if (hostname.includes('amazon.co.jp')) {
      return PLATFORMS.AMAZON_JP;
    }

    return null;
  }

  // Setup extraction button and functionality
  function setupExtraction() {
    // Create floating button
    const button = createExtractionButton();
    document.body.appendChild(button);

    // Listen for messages from background/popup
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      if (request.action === 'extractProduct') {
        extractProduct().then(data => {
          sendResponse({ success: true, data: data });
        }).catch(error => {
          sendResponse({ success: false, error: error.message });
        });
        return true; // Keep message channel open for async response
      }
    });
  }

  // Create floating extraction button
  function createExtractionButton() {
    const button = document.createElement('div');
    button.id = 'sourcy-extract-btn';
    button.innerHTML = `
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
        <polyline points="7 10 12 15 17 10"></polyline>
        <line x1="12" y1="15" x2="12" y2="3"></line>
      </svg>
      <span>Extract Product</span>
    `;

    Object.assign(button.style, {
      position: 'fixed',
      bottom: '20px',
      right: '20px',
      zIndex: '2147483647',
      backgroundColor: '#3B82F6',
      color: 'white',
      padding: '12px 20px',
      borderRadius: '8px',
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      fontSize: '14px',
      fontWeight: '500',
      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
      transition: 'all 0.2s ease'
    });

    button.addEventListener('mouseenter', () => {
      button.style.backgroundColor = '#2563EB';
      button.style.transform = 'translateY(-2px)';
    });

    button.addEventListener('mouseleave', () => {
      button.style.backgroundColor = '#3B82F6';
      button.style.transform = 'translateY(0)';
    });

    button.addEventListener('click', async () => {
      button.innerHTML = '<span>Extracting...</span>';
      button.style.opacity = '0.7';

      try {
        const data = await extractProduct();
        await sendToBackground({ action: 'productExtracted', data: data });
        showNotification('Product extracted successfully!');
      } catch (error) {
        console.error('[Sourcy Extension] Extraction error:', error);
        showNotification('Extraction failed: ' + error.message, 'error');
      }

      button.innerHTML = `
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
          <polyline points="7 10 12 15 17 10"></polyline>
          <line x1="12" y1="15" x2="12" y2="3"></line>
        </svg>
        <span>Extract Product</span>
      `;
      button.style.opacity = '1';
    });

    return button;
  }

  // Extract product data based on current platform
  async function extractProduct() {
    console.log('[Sourcy Extension] Extracting product from:', currentPlatform);

    let productData = null;

    switch (currentPlatform) {
      case PLATFORMS.TAOBAO:
        productData = await extractTaobaoProduct();
        break;
      case PLATFORMS.TMALL:
        productData = await extractTmallProduct();
        break;
      case PLATFORMS.ALIEXPRESS:
        productData = await extractAliExpressProduct();
        break;
      case PLATFORMS.AMAZON:
      case PLATFORMS.AMAZON_JP:
        productData = await extractAmazonProduct();
        break;
      default:
        throw new Error('Unsupported platform');
    }

    // Add metadata
    productData.platform = currentPlatform;
    productData.url = window.location.href;
    productData.collectedAt = new Date().toISOString();

    return productData;
  }

  // Extract Taobao product data
  async function extractTaobaoProduct() {
    const productId = extractProductId();
    if (!productId) {
      throw new Error('Could not extract product ID');
    }

    const title = document.querySelector('.tb-main-title')?.textContent?.trim() ||
                  document.querySelector('h1[data-spm="1000983"]')?.textContent?.trim() ||
                  document.querySelector('.ItemTitle--mainTitle--nWFzCjU')?.textContent?.trim();

    const priceText = document.querySelector('.tb-price')?.textContent?.trim() ||
                      document.querySelector('.Price--priceInt--ZlsSi_H')?.textContent?.trim();

    const images = Array.from(document.querySelectorAll('img.tb-pic'))
      .map(img => img.src)
      .filter(Boolean);

    const description = document.querySelector('.tb-detail-hd')?.textContent?.trim() ||
                       document.querySelector('.desc-loaded')?.textContent?.trim();

    const shopName = document.querySelector('.tb-shop-name')?.textContent?.trim() ||
                     document.querySelector('.ShopHeader--shopName--MvRQ9F1')?.textContent?.trim();

    return {
      source_id: productId,
      title: title,
      price: parsePrice(priceText),
      currency: 'CNY',
      images: images,
      description: description,
      shop_name: shopName,
      variants: await extractVariants(),
      specifications: extractSpecifications()
    };
  }

  // Extract Tmall product data (similar to Taobao)
  async function extractTmallProduct() {
    return await extractTaobaoProduct(); // Tmall uses similar structure
  }

  // Extract AliExpress product data
  async function extractAliExpressProduct() {
    const productId = extractProductId();
    if (!productId) {
      throw new Error('Could not extract product ID');
    }

    const title = document.querySelector('.product-title-text')?.textContent?.trim() ||
                  document.querySelector('h1[data-pl="product-title"]')?.textContent?.trim();

    const priceText = document.querySelector('.product-price-value')?.textContent?.trim() ||
                      document.querySelector('.snow-price_SnowPrice__mainM')?.textContent?.trim();

    const images = Array.from(document.querySelectorAll('.images-view-item img'))
      .map(img => img.src)
      .filter(Boolean);

    const description = document.querySelector('.product-description')?.textContent?.trim() ||
                       document.querySelector('[data-role="description"]')?.textContent?.trim();

    const shopName = document.querySelector('.shop-name')?.textContent?.trim() ||
                     document.querySelector('.store-name')?.textContent?.trim();

    return {
      source_id: productId,
      title: title,
      price: parsePrice(priceText),
      currency: 'USD',
      images: images,
      description: description,
      shop_name: shopName,
      variants: await extractVariants(),
      specifications: extractSpecifications()
    };
  }

  // Extract Amazon product data
  async function extractAmazonProduct() {
    const asin = extractProductId();
    if (!asin) {
      throw new Error('Could not extract ASIN');
    }

    const title = document.querySelector('#productTitle')?.textContent?.trim() ||
                  document.querySelector('h1#title')?.textContent?.trim();

    const priceText = document.querySelector('.a-price .a-offscreen')?.textContent?.trim() ||
                      document.querySelector('#priceblock_ourprice')?.textContent?.trim() ||
                      document.querySelector('#priceblock_dealprice')?.textContent?.trim();

    const images = Array.from(document.querySelectorAll('#landingImage, #imgBlkFront, .a-dynamic-image'))
      .filter(img => img.src && !img.src.includes('no-img'))
      .map(img => img.src)
      .filter(Boolean);

    const description = document.querySelector('#productDescription')?.textContent?.trim() ||
                       document.querySelector('#feature-bullets')?.textContent?.trim();

    const shopName = document.querySelector('#sellerProfileTriggerId')?.textContent?.trim() ||
                     document.querySelector('#merchant-info')?.textContent?.trim();

    return {
      source_id: asin,
      title: title,
      price: parsePrice(priceText),
      currency: currentPlatform === PLATFORMS.AMAZON_JP ? 'JPY' : 'USD',
      images: images,
      description: description,
      shop_name: shopName,
      variants: await extractAmazonVariants(),
      specifications: extractAmazonSpecifications()
    };
  }

  // Extract product ID from URL
  function extractProductId() {
    const url = window.location.href;

    // Taobao/Tmall/1688: ?id=123456789
    const taobaoMatch = url.match(/[?&]id=(\d+)/);
    if (taobaoMatch) return taobaoMatch[1];

    // AliExpress: /item/123456789.html
    const aliExpressMatch = url.match(/\/item\/(\d+)\.html/);
    if (aliExpressMatch) return aliExpressMatch[1];

    // Amazon: /dp/B0XXXXXXX or /gp/product/B0XXXXXXX
    const amazonMatch = url.match(/(?:\/dp\/|\/gp\/product\/)([A-Z0-9]{10})(?:\/|$)/);
    if (amazonMatch) return amazonMatch[1];

    return null;
  }

  // Parse price string to number
  function parsePrice(priceText) {
    if (!priceText) return 0;

    // Remove currency symbols and whitespace
    const cleaned = priceText.replace(/[^\d.,]/g, '');

    // Parse number (handle both comma and decimal separators)
    const match = cleaned.match(/(\d+[.,]\d+)/);
    if (match) {
      return parseFloat(match[1].replace(',', ''));
    }

    return parseFloat(cleaned) || 0;
  }

  // Extract product variants
  async function extractVariants() {
    const variants = [];

    // Look for variant selectors
    const variantGroups = document.querySelectorAll('.tb-sku, .sku-attr-list, .sku-property');

    variantGroups.forEach(group => {
      const name = group.querySelector('.tb-sku-name, .sku-title')?.textContent?.trim();
      const values = Array.from(group.querySelectorAll('li span, a span'))
        .map(el => el.textContent?.trim())
        .filter(Boolean);

      if (name && values.length > 0) {
        variants.push({
          name: name,
          values: values
        });
      }
    });

    return variants;
  }

  // Extract Amazon variants
  async function extractAmazonVariants() {
    const variants = [];

    // Amazon variant dropdowns
    const dropdowns = document.querySelectorAll('#native_dropdown_selected_size_name, #native_dropdown_selected_color_name');

    dropdowns.forEach(dropdown => {
      const name = dropdown.closest('.a-section')?.querySelector('.a-native-dropdown')?.getAttribute('aria-label') || dropdown.id.replace(/_/g, ' ');

      const options = Array.from(dropdown.querySelectorAll('option'))
        .filter(opt => opt.value)
        .map(opt => opt.textContent.trim());

      if (options.length > 0) {
        variants.push({
          name: name,
          values: options
        });
      }
    });

    return variants;
  }

  // Extract product specifications
  function extractSpecifications() {
    const specs = {};

    // Try to find specification tables
    const specRows = document.querySelectorAll('#detail-bullets .a-list-item, .parameter2 li, .obj-parameter li');

    specRows.forEach(row => {
      const text = row.textContent.trim();
      const match = text.match(/^([^:：]+)[:：](.+)$/);
      if (match) {
        specs[match[1].trim()] = match[2].trim();
      }
    });

    return specs;
  }

  // Extract Amazon specifications
  function extractAmazonSpecifications() {
    const specs = {};

    // Product details table
    const productTable = document.querySelector('#productDetails_techSpec_section_1, #productDetails_detailBullets_sections_1');

    if (productTable) {
      const rows = productTable.querySelectorAll('tr');
      rows.forEach(row => {
        const label = row.querySelector('th')?.textContent?.trim();
        const value = row.querySelector('td')?.textContent?.trim();
        if (label && value) {
          specs[label] = value;
        }
      });
    }

    return specs;
  }

  // Send message to background script
  async function sendToBackground(message) {
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

  // Show notification to user
  function showNotification(message, type = 'success') {
    const notification = document.createElement('div');
    notification.id = 'sourcy-notification';
    notification.textContent = message;

    Object.assign(notification.style, {
      position: 'fixed',
      top: '20px',
      right: '20px',
      zIndex: '2147483647',
      backgroundColor: type === 'error' ? '#EF4444' : '#10B981',
      color: 'white',
      padding: '16px 24px',
      borderRadius: '8px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      fontSize: '14px',
      fontWeight: '500',
      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
      animation: 'slideIn 0.3s ease'
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
