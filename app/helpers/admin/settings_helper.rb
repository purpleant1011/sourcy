# frozen_string_literal: true

module Admin::SettingsHelper
  def provider_badge_class(provider)
    case provider
    when 'naver', 'smart_store'
      'bg-green-100 text-green-800'
    when 'coupang'
      'bg-red-100 text-red-800'
    when 'gmarket'
      'bg-yellow-100 text-yellow-800'
    when 'elevenst'
      'bg-purple-100 text-purple-800'
    when 'google_vision'
      'bg-blue-100 text-blue-800'
    when 'naver_clova', 'papago'
      'bg-teal-100 text-teal-800'
    when 'openai', 'gpt'
      'bg-indigo-100 text-indigo-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  def mask_key(key)
    return '' if key.blank?

    if key.length <= 8
      '*' * key.length
    else
      "#{key[0..3]}#{'*' * (key.length - 8)}#{key[-4..]}"
    end
  end
end
