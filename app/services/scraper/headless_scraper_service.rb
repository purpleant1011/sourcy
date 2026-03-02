# frozen_string_literal: true

# Headless scraper service using Playwright for JavaScript-rendered pages
# Requires playwright-ruby gem: https://github.com/YusukeIwaki/playwright-ruby
# Install with: bundle add playwright-ruby && npx playwright install
module Scraper
  class HeadlessScraperService
    class ScrapingError < StandardError; end

    attr_reader :options, :browser_type

    # Initialize headless scraper
    #
    # @param options [Hash] Scraper options
    # @option options [Symbol] :browser_type Browser type (:chromium, :firefox, :webkit)
    # @option options [Boolean] :headless Run in headless mode (default: true)
    # @option options [Integer] :timeout Page timeout in seconds (default: 30)
    # @option options [String] :user_agent Custom user agent
    # @option options [String] :locale Browser locale (default: 'ko-KR')
    # @option options [String] :timezone Timezone (default: 'Asia/Seoul')
    def initialize(options: {})
      @options = {
        browser_type: :chromium,
        headless: true,
        timeout: 30,
        locale: 'ko-KR',
        timezone: 'Asia/Seoul'
      }.merge(options)

      @browser_type = @options[:browser_type]
    end

    # Fetch product from URL with JavaScript rendering
    #
    # @param url [String] Product URL
    # @param wait_for_selector [String, nil] CSS selector to wait for
    # @param wait_for_timeout [Integer] Max wait time in seconds (default: 10)
    # @yield [page] Optional block for custom scraping logic
    # @return [Hash] Product details
    def fetch_product(url, wait_for_selector: nil, wait_for_timeout: 10)
      with_browser do |browser|
        page = browser.new_page(
          viewport: { width: 1920, height: 1080 },
          locale: @options[:locale],
          timezone_id: @options[:timezone]
        )

        begin
          page.set_user_agent(@options[:user_agent]) if @options[:user_agent]
          page.goto(url, wait_until: 'networkidle', timeout: @options[:timeout] * 1000)

          # Wait for dynamic content if selector provided
          if wait_for_selector
            page.wait_for_selector(wait_for_selector, timeout: wait_for_timeout * 1000)
          end

          # Allow custom scraping logic via block
          if block_given?
            yield(page)
          else
            # Default extraction
            extract_default_product_data(page, url)
          end
        ensure
          page.close
        end
      end
    end

    # Take screenshot of page
    #
    # @param url [String] Page URL
    # @param path [String] Screenshot save path
    # @param full_page [Boolean] Capture full page (default: false)
    # @return [String] Screenshot path
    def take_screenshot(url, path: nil, full_page: false)
      with_browser do |browser|
        page = browser.new_page(viewport: { width: 1920, height: 1080 })

        begin
          page.goto(url, wait_until: 'networkidle', timeout: @options[:timeout] * 1000)

          path ||= Rails.root.join('tmp', "screenshot_#{Time.now.to_i}.png")
          page.screenshot(path: path, full_page: full_page)

          path
        ensure
          page.close
        end
      end
    end

    # Extract all images from page
    #
    # @param url [String] Page URL
    # @param min_width [Integer] Minimum image width (default: 100)
    # @param min_height [Integer] Minimum image height (default: 100)
    # @return [Array<String>] Image URLs
    def extract_images(url, min_width: 100, min_height: 100)
      fetch_product(url) do |page|
        images = page.query_selector_all('img')

        images.filter_map do |img|
          src = img.get_attribute('src')
          width = img.get_attribute('width')&.to_i
          height = img.get_attribute('height')&.to_i

          # Filter by dimensions
          next if width && width < min_width
          next if height && height < min_height
          next if src.nil? || src.empty?

          # Resolve relative URLs
          if src.start_with?('//')
            "https:#{src}"
          elsif src.start_with?('/')
            base_uri = URI(url)
            "#{base_uri.scheme}://#{base_uri.host}#{src}"
          else
            src
          end
        end.uniq
      end
    end

    # Extract structured data from JSON-LD scripts
    #
    # @param url [String] Page URL
    # @param schema_type [String, nil] Filter by schema type (e.g., 'Product')
    # @return [Array<Hash>] JSON-LD structured data
    def extract_json_ld(url, schema_type: nil)
      fetch_product(url) do |page|
        scripts = page.query_selector_all('script[type="application/ld+json"]')

        scripts.filter_map do |script|
          content = script.text_content
          next if content.nil? || content.empty?

          data = JSON.parse(content)
          next if schema_type && data['@type'] != schema_type

          data
        rescue JSON::ParserError
          nil
        end
      end
    end

    # Execute custom JavaScript on page
    #
    # @param url [String] Page URL
    # @param script [String] JavaScript code to execute
    # @return [Any] Script result
    def execute_script(url, script)
      fetch_product(url) do |page|
        page.evaluate(script)
      end
    end

    # Extract text content from page
    #
    # @param url [String] Page URL
    # @param selector [String] CSS selector
    # @return [String, nil] Text content
    def extract_text(url, selector)
      fetch_product(url) do |page|
        element = page.query_selector(selector)
        element&.text_content
      end
    end

    # Scroll page to load lazy-loaded content
    #
    # @param url [String] Page URL
    # @param max_scrolls [Integer] Maximum scroll次数 (default: 10)
    # @param scroll_delay [Integer] Delay between scrolls in ms (default: 500)
    # @yield [page] Optional block to process after each scroll
    # @return [Hash] Page data
    def scroll_and_extract(url, max_scrolls: 10, scroll_delay: 500)
      with_browser do |browser|
        page = browser.new_page(viewport: { width: 1920, height: 1080 })

        begin
          page.goto(url, wait_until: 'networkidle', timeout: @options[:timeout] * 1000)

          all_data = []
          scroll_count = 0

          while scroll_count < max_scrolls
            # Yield for custom extraction
            if block_given?
              data = yield(page, scroll_count)
              all_data.concat(Array(data)) if data
            end

            # Scroll down
            page.evaluate('window.scrollBy(0, window.innerHeight)')
            sleep(scroll_delay / 1000.0)

            # Check if reached bottom
            scroll_height = page.evaluate('document.documentElement.scrollHeight')
            scroll_position = page.evaluate('window.scrollY + window.innerHeight')

            break if scroll_position >= scroll_height - 100
            scroll_count += 1
          end

          # Final extraction
          if block_given?
            final_data = yield(page, scroll_count)
            all_data.concat(Array(final_data)) if final_data
          end

          all_data.uniq
        ensure
          page.close
        end
      end
    end

    # Handle popup/alert dialogs
    #
    # @param url [String] Page URL
    # @param handler [Proc] Handler for dialog
    # @return [Hash] Page data
    def with_dialog_handler(url, &handler)
      fetch_product(url) do |page|
        page.on('dialog') { |dialog| handler.call(dialog) }

        # Default extraction
        extract_default_product_data(page, url)
      end
    end

    # Intercept network requests
    #
    # @param url [String] Page URL
    # @param filter [Proc] Request filter
    # @yield [request, response] Handler for matched requests
    # @return [Hash] Page data
    def intercept_requests(url, filter: nil)
      with_browser do |browser|
        page = browser.new_page

        begin
          # Intercept XHR/JSON requests
          page.on('response') do |response|
            next if filter && !filter.call(response)
            next unless response.request.resource_type == 'xhr'

            yield(response.request, response) if block_given?
          end

          page.goto(url, wait_until: 'networkidle', timeout: @options[:timeout] * 1000)
          extract_default_product_data(page, url)
        ensure
          page.close
        end
      end
    end

    private

    # Execute code block with browser context
    #
    # @yield [browser] Browser instance
    def with_browser
      Playwright.create(playwright_cli_executable_path: playwright_cli_path) do |playwright|
        playwright.send(@browser_type).launch(headless: @options[:headless]) do |browser|
          yield(browser)
        end
      end
    rescue StandardError => e
      raise ScrapingError, "Playwright error: #{e.message}"
    end

    # Extract default product data from page
    #
    # @param page [Playwright::Page] Page instance
    # @param url [String] Original URL
    # @return [Hash] Product data
    def extract_default_product_data(page, url)
      # Try JSON-LD first
      json_ld_data = extract_json_ld_from_page(page)
      return json_ld_data if json_ld_data && valid_product_data?(json_ld_data)

      # Fallback to heuristic extraction
      extract_heuristic_product_data(page, url)
    end

    # Extract JSON-LD from page
    #
    # @param page [Playwright::Page] Page instance
    # @return [Hash, nil] Product data
    def extract_json_ld_from_page(page)
      scripts = page.query_selector_all('script[type="application/ld+json"]')

      scripts.each do |script|
        content = script.text_content
        next if content.nil? || content.empty?

        begin
          data = JSON.parse(content)

          # Handle single product or array of products
          product = data.is_a?(Array) ? data.find { |d| d['@type'] == 'Product' } : data
          next unless product && product['@type'] == 'Product'

          return normalize_json_ld_data(product)
        rescue JSON::ParserError
          next
        end
      end

      nil
    end

    # Normalize JSON-LD product data
    #
    # @param data [Hash] JSON-LD data
    # @return [Hash] Normalized product data
    def normalize_json_ld_data(data)
      {
        id: extract_id(data),
        title: data['name'] || data['headline'],
        description: data['description'] || data['articleBody'],
        price_cents: extract_price_from_json_ld(data),
        images: extract_images_from_json_ld(data),
        variants: extract_variants_from_json_ld(data),
        attributes: extract_attributes_from_json_ld(data),
        specifications: extract_specifications_from_json_ld(data),
        shipping: { domestic: true },
        stock: { available: data['offers']&.dig('availability')&.include?('InStock') },
        raw_api_data: data
      }
    end

    # Extract product ID from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [String] Product ID
    def extract_id(data)
      data['sku'] || data['productID'] || data['@id'] || 'unknown'
    end

    # Extract price from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [Integer] Price in cents
    def extract_price_from_json_ld(data)
      offers = data['offers']
      return 0 unless offers

      offer = offers.is_a?(Array) ? offers.first : offers
      price = offer['price'] || offer.dig('priceSpecification', 'price')

      return 0 unless price

      (price.to_f * 100).to_i
    end

    # Extract images from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [Array<String>] Image URLs
    def extract_images_from_json_ld(data)
      images = []

      if data['image']
        images.concat(Array(data['image']))
      end

      images.uniq.compact
    end

    # Extract variants from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [Array<Hash>] Variants
    def extract_variants_from_json_ld(data)
      offers = data['offers']
      return [] unless offers

      Array(offers).map do |offer|
        {
          id: offer['sku'] || offer['identifier'],
          name: offer['name'] || 'Variant',
          price_cents: offer['price'] ? (offer['price'].to_f * 100).to_i : 0,
          available: offer['availability']&.include?('InStock')
        }
      end
    end

    # Extract attributes from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [Hash] Attributes
    def extract_attributes_from_json_ld(data)
      {
        brand: data.dig('brand', 'name') || 'Unknown',
        category: data.dig('category'),
        origin: 'International'
      }
    end

    # Extract specifications from JSON-LD data
    #
    # @param data [Hash] JSON-LD data
    # @return [Hash] Specifications
    def extract_specifications_from_json_ld(data)
      specs = {}

      if data['additionalProperty']
        data['additionalProperty'].each do |prop|
          specs[prop['name']] = prop['value']
        end
      end

      specs
    end

    # Validate product data
    #
    # @param data [Hash] Product data
    # @return [Boolean] Valid?
    def valid_product_data?(data)
      data['title'].present? && data['id'].present?
    end

    # Extract product data using heuristics
    #
    # @param page [Playwright::Page] Page instance
    # @param url [String] Original URL
    # @return [Hash] Product data
    def extract_heuristic_product_data(page, url)
      title = extract_text_heuristic(page, [
        'h1',
        '[class*="title"]',
        '[class*="product-title"]',
        '[class*="product-name"]'
      ])

      description = extract_text_heuristic(page, [
        '[class*="description"]',
        '[class*="product-desc"]',
        '#product-description',
        '.product-detail'
      ])

      images = extract_images_from_page(page)

      {
        id: extract_id_from_url(url),
        title: title || 'Unknown',
        description: description || '',
        images: images,
        variants: [],
        attributes: { origin: 'International' },
        specifications: {},
        shipping: {},
        stock: {},
        raw_api_data: {}
      }
    end

    # Extract text using heuristic selectors
    #
    # @param page [Playwright::Page] Page instance
    # @param selectors [Array<String>] CSS selectors
    # @return [String, nil] Text content
    def extract_text_heuristic(page, selectors)
      selectors.each do |selector|
        element = page.query_selector(selector)
        text = element&.text_content
        return text.strip if text.present?
      end
      nil
    end

    # Extract images from page
    #
    # @param page [Playwright::Page] Page instance
    # @return [Array<String>] Image URLs
    def extract_images_from_page(page)
      images = page.query_selector_all('img')

      images.filter_map do |img|
        src = img.get_attribute('src')
        next unless src.present?

        # Filter small tracking pixels
        width = img.get_attribute('width')&.to_i
        height = img.get_attribute('height')&.to_i
        next if width && width < 100
        next if height && height < 100

        # Resolve relative URLs
        resolve_url(src, page.url)
      end.uniq.take(20)
    end

    # Extract product ID from URL
    #
    # @param url [String] URL
    # @return [String] Product ID
    def extract_id_from_url(url)
      uri = URI.parse(url)
      path = uri.path

      # Extract ID from path patterns
      patterns = [
        %r{/(\d+)$},                    # Ends with numbers
        %r{/dp/([A-Z0-9]{10})},        # Amazon ASIN
        %r{/item/(\d+)}                 # Taobao/Tmall
      ]

      patterns.each do |pattern|
        match = path.match(pattern)
        return match.captures.first if match
      end

      'unknown'
    end

    # Resolve relative URL to absolute
    #
    # @param src [String] Source URL
    # @param base_url [String] Base URL
    # @return [String] Absolute URL
    def resolve_url(src, base_url)
      return src if src.start_with?('http')

      if src.start_with?('//')
        "https:#{src}"
      elsif src.start_with?('/')
        base_uri = URI(base_url)
        "#{base_uri.scheme}://#{base_uri.host}#{src}"
      else
        base_uri = URI(base_url)
        "#{base_uri.scheme}://#{base_uri.host}/#{src}"
      end
    end

    # Get Playwright CLI executable path
    #
    # @return [String] Path to Playwright CLI
    def playwright_cli_path
      Rails.root.join('node_modules', '.bin', 'playwright').to_s
    end
  end
end
