# frozen_string_literal: true

# OpenAI GPT translation service
# Requires OPENAI_API_KEY in Rails credentials
# @see https://platform.openai.com/docs/api-reference/chat
module Translation
  class GptService < BaseService
    class AuthenticationError < TranslationError; end

    API_ENDPOINT = "https://api.openai.com/v1/chat/completions"

    attr_reader :model

    # Initialize translation service
    #
    # @param source_lang [String] Source language code (e.g., 'zh-CN', 'en', 'ja')
    # @param target_lang [String] Target language code (e.g., 'ko', 'en')
    # @param options [Hash] Additional options
    # @option options [String] :source_text Text to translate
    # @option options [String] :context Translation context (optional)
    # @option options [String] :model GPT model to use (default: 'gpt-4o')
    # @option options [Integer] :temperature Sampling temperature (0-2, default: 0.3)
    # @option options [Boolean] :include_alternatives Include alternative translations (default: false)
    def initialize(source_lang:, target_lang:, options: {})
      super
      @source_text = @options[:source_text]
      @model = @options[:model] || 'gpt-4o'
      @temperature = @options[:temperature] || 0.3
      @include_alternatives = @options[:include_alternatives] || false
    end

    # Translate text using OpenAI GPT API
    #
    # @return [Hash] Translated text with metadata
    def translate
      raise AuthenticationError, "OpenAI API key not configured" unless available?

      response = call_openai_api
      raise TranslationError, "OpenAI API error: #{response.code}" unless response.success?

      parse_openai_response(response.parsed_response)
    end

    # Check if OpenAI API key is configured
    #
    # @return [Boolean]
    def available?
      Rails.application.credentials.dig(:openai, :api_key).present?
    end

    # Get supported languages (GPT supports most languages)
    #
    # @return [Hash] Supported languages (broad support for most languages)
    def supported_languages
      {
        'zh-CN' => ['ko', 'en', 'ja', 'fr', 'de', 'es'],
        'zh-TW' => ['ko', 'en', 'ja', 'fr', 'de', 'es'],
        'en' => ['ko', 'ja', 'zh-CN', 'fr', 'de', 'es', 'ru', 'ar'],
        'ja' => ['ko', 'en', 'zh-CN', 'fr', 'de'],
        'ko' => ['en', 'ja', 'zh-CN', 'fr', 'de', 'es'],
        'fr' => ['en', 'ko', 'de', 'es'],
        'de' => ['en', 'ko', 'fr'],
        'es' => ['en', 'ko', 'fr', 'de']
      }
    end

    private

    def call_openai_api
      api_key = Rails.application.credentials.dig(:openai, :api_key)

      HTTParty.post(
        API_ENDPOINT,
        body: build_request_body,
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        },
        timeout: 60
      )
    end

    def build_request_body
      {
        model: @model,
        messages: build_messages,
        temperature: @temperature,
        n: @include_alternatives ? 3 : 1
      }
    end

    def build_messages
      messages = [
        {
          role: "system",
          content: build_system_prompt
        },
        {
          role: "user",
          content: @source_text
        }
      ]

      messages
    end

    def build_system_prompt
      source_name = language_name(@source_lang)
      target_name = language_name(@target_lang)

      prompt = "You are a professional translator. " \
               "Translate the following text from #{source_name} to #{target_name}. " \
               "Provide natural, culturally appropriate translations suitable for e-commerce product descriptions."

      prompt += " Maintain technical terms and brand names in original form where appropriate." if @options[:context] == 'ecommerce'

      prompt
    end

    def language_name(code)
      names = {
        'zh-CN' => 'Simplified Chinese',
        'zh-TW' => 'Traditional Chinese',
        'en' => 'English',
        'ja' => 'Japanese',
        'ko' => 'Korean',
        'fr' => 'French',
        'de' => 'German',
        'es' => 'Spanish'
      }

      names[code] || code
    end

    def parse_openai_response(response)
      choices = response.dig("choices") || []
      return format_result(translated_text: "", confidence: 0.0) if choices.empty?

      # Get primary translation
      primary_choice = choices.first
      translated_text = primary_choice.dig("message", "content") || ""

      # Parse alternatives if requested
      alternatives = []
      if @include_alternatives && choices.length > 1
        alternatives = choices[1..-1].map do |choice|
          {
            text: choice.dig("message", "content"),
            confidence: 0.85 # No confidence from API, use estimate
          }
        end
      end

      # Estimate confidence from finish reason and presence of reasoning
      confidence = estimate_confidence(primary_choice)

      format_result(
        translated_text: translated_text,
        confidence: confidence,
        alternatives: alternatives
      )
    end

    def estimate_confidence(choice)
      return 0.5 unless choice

      # Higher confidence if response completed normally
      finish_reason = choice.dig("finish_reason")

      case finish_reason
      when "stop"
        0.95
      when "length"
        0.85
      when "content_filter"
        0.3
      else
        0.7
      end
    end
  end
end
