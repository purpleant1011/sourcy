# frozen_string_literal: true

# Base translation service for translating text between languages
# Subclasses must implement the #translate method
module Translation
  class BaseService
    class TranslationError < StandardError; end

    attr_reader :source_lang, :target_lang, :options

    # Initialize translation service
    #
    # @param source_lang [String] Source language code (e.g., 'zh-CN', 'en-US', 'ja')
    # @param target_lang [String] Target language code (e.g., 'ko', 'en')
    # @param options [Hash] Additional options
    # @option options [String] :source_text Text to translate
    # @option options [String] :context Translation context (optional)
    def initialize(source_lang:, target_lang:, options: {})
      @source_lang = source_lang
      @target_lang = target_lang
      @options = options
    end

    # Translate the source text to target language
    #
    # @abstract
    # @return [Hash] Translated text with metadata
    # @raise [NotImplementedError] if subclass doesn't implement
    def translate
      raise NotImplementedError, "Subclasses must implement #translate"
    end

    # Check if the service is available
    #
    # @return [Boolean] true if API credentials are configured
    def available?
      credentials_configured?
    end

    # Get supported language pairs
    #
    # @abstract
    # @return [Hash] Mapping of source languages to supported target languages
    def supported_languages
      raise NotImplementedError, "Subclasses must implement #supported_languages"
    end

    protected

    # Format translation result to standard structure
    #
    # @param translated_text [String] Translated text
    # @param confidence [Float] Confidence score (0-1)
    # @param alternatives [Array<Hash>] Alternative translations (optional)
    # @return [Hash] Formatted result
    def format_result(translated_text:, confidence: 0.0, alternatives: [])
      {
        source_text: @options[:source_text],
        translated_text: translated_text.to_s.strip,
        source_language: @source_lang,
        target_language: @target_lang,
        confidence: confidence.to_f,
        alternatives: alternatives,
        provider: self.class.name.demodulize,
        timestamp: Time.current.iso8601
      }
    end

    # Check if API credentials are configured
    #
    # @abstract
    # @return [Boolean]
    def credentials_configured?
      raise NotImplementedError, "Subclasses must implement #credentials_configured?"
    end
  end
end
