# frozen_string_literal: true

# Naver Papago translation service
# Requires NAVER_CLIENT_ID and NAVER_CLIENT_SECRET in Rails credentials
# @see https://developers.naver.com/docs/papago/
module Translation
  class PapagoService < BaseService
    class AuthenticationError < TranslationError; end

    API_ENDPOINT = "https://openapi.naver.com/v1/papago/n2mt"

    # Initialize translation service
    #
    # @param source_lang [String] Source language code (e.g., 'zh-CN', 'en', 'ja')
    # @param target_lang [String] Target language code (e.g., 'ko', 'en')
    # @param options [Hash] Additional options
    # @option options [String] :source_text Text to translate
    # @option options [String] :context Translation context (optional)
    def initialize(source_lang:, target_lang:, options: {})
      super
      @source_text = @options[:source_text]
    end

    # Translate text using Papago API
    #
    # @return [Hash] Translated text with metadata
    def translate
      raise AuthenticationError, "Naver Papago credentials not configured" unless available?

      response = call_papago_api
      raise TranslationError, "Papago API error: #{response.code}" unless response.success?

      parse_papago_response(response.parsed_response)
    end

    # Check if Naver credentials are configured
    #
    # @return [Boolean]
    def available?
      Rails.application.credentials.dig(:naver, :client_id).present? &&
        Rails.application.credentials.dig(:naver, :client_secret).present?
    end

    # Get supported languages
    #
    # @return [Hash] Supported source languages and their targets
    def supported_languages
      {
        'zh-CN' => ['ko', 'en', 'ja'],
        'zh-TW' => ['ko', 'en', 'ja'],
        'en' => ['ko', 'ja', 'zh-CN'],
        'ja' => ['ko', 'en', 'zh-CN'],
        'ko' => ['en', 'ja', 'zh-CN']
      }
    end

    private

    def call_papago_api
      client_id = Rails.application.credentials.dig(:naver, :client_id)
      client_secret = Rails.application.credentials.dig(:naver, :client_secret)

      HTTParty.post(
        API_ENDPOINT,
        body: {
          source: normalize_language_code(@source_lang),
          target: normalize_language_code(@target_lang),
          text: @source_text
        }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-Naver-Client-Id" => client_id,
          "X-Naver-Client-Secret" => client_secret
        },
        timeout: 30
      )
    end

    def parse_papago_response(response)
      message = response.dig("message")

      translated_text = message.dig("result", "translatedText") || ""

      # Papago doesn't provide confidence scores, use a default
      format_result(translated_text: translated_text, confidence: 0.95)
    end

    # Normalize language codes to Papago format
    #
    # @param code [String] Language code
    # @return [String] Normalized code
    def normalize_language_code(code)
      case code
      when 'zh-CN', 'zh-TW'
        code
      when 'zh'
        'zh-CN'
      else
        code&.downcase&.split('-')&.first || code
      end
    end
  end
end
