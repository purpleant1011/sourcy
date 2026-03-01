// Sourcy Chrome Extension — Content Script
// Detects product pages and extracts metadata from supported platforms

const PLATFORM_DETECTORS = {
  taobao: {
    match: () => location.hostname.includes('taobao.com') || location.hostname.includes('tmall.com'),
    extract: () => ({
      platform: 'taobao',
      external_id: new URLSearchParams(location.search).get('id'),
      title: document.querySelector('.mainTitle, .ItemHeader--mainTitle, [data-title]')?.textContent?.trim(),
      price: document.querySelector('.tb-rmb-num, .Price--priceText')?.textContent?.trim(),
      image_url: document.querySelector('#J_ImgBooth, .PicGallery--mainPic img')?.src,
      page_url: location.href,
      collected_at: new Date().toISOString()
    })
  },

  aliexpress: {
    match: () => location.hostname.includes('aliexpress.com'),
    extract: () => ({
      platform: 'aliexpress',
      external_id: location.pathname.match(/\/item\/(\d+)\.html/)?.[1],
      title: document.querySelector('h1[data-pl="product-title"], .product-title-text')?.textContent?.trim(),
      price: document.querySelector('.uniform-banner-box-price, .product-price-value')?.textContent?.trim(),
      image_url: document.querySelector('.magnifier-image, img[data-pl="product-image"]')?.src,
      page_url: location.href,
      collected_at: new Date().toISOString()
    })
  },

  alibaba_1688: {
    match: () => location.hostname.includes('1688.com'),
    extract: () => ({
      platform: 'alibaba_1688',
      external_id: location.pathname.match(/\/offer\/(\d+)\.html/)?.[1],
      title: document.querySelector('.title-text, .mod-detail-title')?.textContent?.trim(),
      price: document.querySelector('.price-text, .value-price')?.textContent?.trim(),
      image_url: document.querySelector('.detail-gallery-img img, #dt-tab img')?.src,
      page_url: location.href,
      collected_at: new Date().toISOString()
    })
  },

  amazon: {
    match: () => location.hostname.includes('amazon.com'),
    extract: () => ({
      platform: 'amazon',
      external_id: location.pathname.match(/\/dp\/([A-Z0-9]{10})/)?.[1] ||
                   location.pathname.match(/\/product\/([A-Z0-9]{10})/)?.[1],
      title: document.querySelector('#productTitle')?.textContent?.trim(),
      price: (() => {
        const whole = document.querySelector('.a-price-whole')?.textContent?.trim() || '';
        const fraction = document.querySelector('.a-price-fraction')?.textContent?.trim() || '00';
        return whole ? `${whole}${fraction}` : null;
      })(),
      image_url: document.querySelector('#landingImage, #imgBlkFront')?.src,
      page_url: location.href,
      collected_at: new Date().toISOString()
    })
  }
};

// Collect all visible images on the product page
function collectProductImages() {
  const selectors = [
    // Taobao/Tmall
    '#J_UlThumb img', '.PicGallery--thumbnail img',
    // AliExpress
    '.images-view-item img', '[data-pl="product-image"]',
    // 1688
    '.tab-content img', '.detail-gallery-img img',
    // Amazon
    '#altImages img', '.imageThumbnail img'
  ];

  const images = new Set();
  for (const selector of selectors) {
    document.querySelectorAll(selector).forEach(img => {
      const src = img.src || img.dataset?.src;
      if (src && !src.includes('placeholder') && !src.includes('loading')) {
        // Get highest resolution version
        const highRes = src
          .replace(/_\d+x\d+\.\w+$/, '') // Taobao thumbnails
          .replace(/\._.*_\./, '._SL1500_.'); // Amazon thumbnails
        images.add(highRes);
      }
    });
  }
  return Array.from(images).slice(0, 20); // Max 20 images
}

// Listen for messages from popup or service worker
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'COLLECT_PRODUCT') {
    const detector = Object.values(PLATFORM_DETECTORS).find(d => d.match());

    if (detector) {
      const metadata = detector.extract();
      metadata.images = collectProductImages();

      // Capture full page HTML for backend processing (user-assisted scraping)
      if (msg.include_html) {
        metadata.page_html = document.documentElement.outerHTML;
      }

      sendResponse({ success: true, metadata });
    } else {
      sendResponse({
        success: false,
        error: '지원하지 않는 페이지입니다. 타오바오, 알리익스프레스, 1688, 아마존 상품 페이지에서 사용해주세요.'
      });
    }
  }

  if (msg.type === 'CHECK_PAGE') {
    const detector = Object.values(PLATFORM_DETECTORS).find(d => d.match());
    sendResponse({
      supported: !!detector,
      platform: detector ? Object.keys(PLATFORM_DETECTORS).find(
        k => PLATFORM_DETECTORS[k] === detector
      ) : null
    });
  }

  return true; // Keep message channel open for async response
});

// Notify service worker that content script is loaded on a product page
const activeDetector = Object.entries(PLATFORM_DETECTORS).find(([, d]) => d.match());
if (activeDetector) {
  chrome.runtime.sendMessage({
    type: 'PRODUCT_PAGE_DETECTED',
    platform: activeDetector[0],
    url: location.href
  }).catch(() => {
    // Service worker might not be ready yet — ignore
  });
}
