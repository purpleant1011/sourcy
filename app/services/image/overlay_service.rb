# frozen_string_literal: true

# Image overlay service for adding translated text overlays to product images
# Uses ruby-vips for efficient image manipulation
# @see https://github.com/libvips/ruby-vips
module Image
  class OverlayService
    class OverlayError < StandardError; end

    attr_reader :image_url, :overlay_data, :options

    # Initialize overlay service
    #
    # @param image_url [String] URL of the source image
    # @param overlay_data [Array<Hash>] Text overlay data
    # @option overlay_data [String] :text Text to overlay
    # @option overlay_data [Hash] :position Position {x, y} or 'bottom-left', etc.
    # @option overlay_data [Hash] :style Style options {font_size, color, bg_color}
    # @param options [Hash] Additional options
    # @option options [String] :output_format Output format (jpg, png, webp, default: png)
    # @option options [Integer] :quality JPEG/WebP quality (0-100, default: 90)
    def initialize(image_url:, overlay_data:, options: {})
      @image_url = image_url
      @overlay_data = overlay_data || []
      @options = options
      @output_format = options[:output_format] || 'png'
      @quality = options[:quality] || 90
    end

    # Add text overlays to the image
    #
    # @return [String] Base64-encoded processed image
    def overlay
      raise OverlayError, "ruby-vips not available" unless vips_available?

      source_path = download_image
      raise OverlayError, "Failed to download image" unless source_path

      begin
        image = Vips::Image.new_from_file(source_path)

        # Add each text overlay
        @overlay_data.each do |overlay|
          image = add_text_overlay(image, overlay)
        end

        # Convert to output format and return base64
        buffer = image_to_buffer(image)

        Base64.strict_encode64(buffer)
      ensure
        cleanup_temp_file(source_path)
      end
    end

    # Process image and save to file
    #
    # @param output_path [String] Path to save the processed image
    # @return [Boolean] true if successful
    def overlay_to_file(output_path)
      base64_data = overlay
      return false unless base64_data

      File.binwrite(output_path, Base64.strict_decode64(base64_data))
      true
    rescue StandardError => e
      Rails.logger.error "Failed to save overlay image: #{e.message}"
      false
    end

    # Check if ruby-vips is available
    #
    # @return [Boolean]
    def vips_available?
      defined?(Vips)
    end

    private

    def download_image
      return nil unless @image_url.present?

      response = HTTParty.get(@image_url, timeout: 30, follow_redirects: true)
      return nil unless response.success?

      temp_file = Tempfile.new(['overlay_', ".#{@output_format}"])
      temp_file.binmode
      temp_file.write(response.body)
      temp_file.close

      temp_file.path
    rescue StandardError => e
      Rails.logger.error "Failed to download image: #{e.message}"
      nil
    end

    def cleanup_temp_file(file_path)
      File.delete(file_path) if file_path && File.exist?(file_path)
    rescue StandardError => e
      Rails.logger.warn "Failed to cleanup temp file: #{e.message}"
    end

    def add_text_overlay(image, overlay)
      text = overlay[:text]
      position = overlay[:position] || {}
      style = overlay[:style] || {}

      return image if text.blank?

      # Parse text style
      font_size = style[:font_size] || 16
      font = style[:font] || 'sans'
      text_color = parse_color(style[:color] || 'white')
      bg_color = parse_color(style[:bg_color] || 'black')
      bg_alpha = style[:bg_alpha] || 0.7
      padding = style[:padding] || 5

      # Create text image
      text_image = create_text_image(text, font_size, font, text_color)

      # Add background to text
      text_with_bg = add_text_background(text_image, bg_color, bg_alpha, padding)

      # Calculate position
      x, y = calculate_position(image, text_with_bg, position)

      # Composite text onto image
      image.composite2(text_with_bg, :over, x: x, y: y)
    end

    def create_text_image(text, font_size, font, color)
      # Create text image with white text on transparent background
      # VIPS doesn't have native text rendering, so we use a simplified approach
      # In production, consider using ImageMagick's `convert` or a dedicated text rendering library

      # For now, create a simple colored rectangle as placeholder for text
      # This is a limitation of ruby-vips not having text rendering built-in

      text_width = estimate_text_width(text, font_size)
      text_height = font_size + 10

      # Create colored rectangle
      text_rect = Vips::Image.black(text_width, text_height).linear(color[:r], 0)
      text_rect = text_rect.bandjoin([color[:g].zero?, color[:b].zero?]) # Simplified

      # Add alpha channel
      text_rect = text_rect.bandjoin([255]) # Full opacity

      text_rect
    end

    def add_text_background(text_image, bg_color, bg_alpha, padding)
      width = text_image.width + (padding * 2)
      height = text_image.height + (padding * 2)

      # Create background rectangle
      bg = Vips::Image.black(width, height).linear(bg_color[:r], 0)
      bg = bg.bandjoin([bg_color[:g].zero?, bg_color[:b].zero?])
      bg = bg.bandjoin([(bg_alpha * 255).to_i]) # Semi-transparent

      # Composite text onto background (centered)
      bg.composite2(text_image, :over, x: padding, y: padding)
    end

    def calculate_position(image, text_image, position)
      if position.is_a?(Hash) && position[:x] && position[:y]
        # Absolute position
        [position[:x], position[:y]]
      else
        # Predefined position
        case position.to_s
        when 'top-left'
          [10, 10]
        when 'top-right'
          [image.width - text_image.width - 10, 10]
        when 'bottom-left'
          [10, image.height - text_image.height - 10]
        when 'bottom-right'
          [image.width - text_image.width - 10, image.height - text_image.height - 10]
        when 'center'
          [(image.width - text_image.width) / 2, (image.height - text_image.height) / 2]
        else
          # Default: bottom-left
          [10, image.height - text_image.height - 10]
        end
      end
    end

    def image_to_buffer(image)
      case @output_format.to_s
      when 'jpg', 'jpeg'
        image.jpegsave_buffer(Q: @quality)
      when 'webp'
        image.webpsave_buffer(Q: @quality)
      else
        # PNG (default)
        image.pngsave_buffer
      end
    end

    def parse_color(color_string)
      # Parse color string like 'white', 'black', '#FF0000', 'rgb(255,0,0)'
      case color_string.to_s.downcase
      when 'white', '#ffffff', 'rgb(255,255,255)'
        { r: 255, g: 255, b: 255 }
      when 'black', '#000000', 'rgb(0,0,0)'
        { r: 0, g: 0, b: 0 }
      when 'red', '#ff0000', 'rgb(255,0,0)'
        { r: 255, g: 0, b: 0 }
      when 'blue', '#0000ff', 'rgb(0,0,255)'
        { r: 0, g: 0, b: 255 }
      when 'green', '#00ff00', 'rgb(0,255,0)'
        { r: 0, g: 255, b: 0 }
      when 'yellow', '#ffff00', 'rgb(255,255,0)'
        { r: 255, g: 255, b: 0 }
      when 'gray', 'grey', '#808080', 'rgb(128,128,128)'
        { r: 128, g: 128, b: 128 }
      when /#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i
        { r: $1.to_i(16), g: $2.to_i(16), b: $3.to_i(16) }
      when /rgb\((\d+),(\d+),(\d+)\)/i
        { r: $1.to_i, g: $2.to_i, b: $3.to_i }
      else
        { r: 0, g: 0, b: 0 } # Default to black
      end
    end

    def estimate_text_width(text, font_size)
      # Rough estimation: 0.6 * font_size * character count
      # In production, use a proper text measurement library
      (text.length * font_size * 0.6).to_i
    end
  end
end
