# frozen_string_literal: true

module Admin::DashboardHelper
  def activity_color(action_type)
    case action_type.to_s
    when 'create', 'import', 'publish'
      'bg-green-100 text-green-800'
    when 'update', 'sync'
      'bg-blue-100 text-blue-800'
    when 'delete', 'cancel', 'refund'
      'bg-red-100 text-red-800'
    when 'error', 'failure'
      'bg-red-200 text-red-900'
    when 'warning'
      'bg-yellow-100 text-yellow-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  def activity_icon(action_type)
    case action_type.to_s
    when 'create', 'import', 'publish'
      '✓'
    when 'update', 'sync'
      '↻'
    when 'delete', 'cancel', 'refund'
      '✕'
    when 'error', 'failure'
      '⚠'
    when 'warning'
      '!'
    else
      '•'
    end
  end

  def activity_display_text(activity)
    case activity.action_type.to_s
    when 'create'
      "새로운 #{activity.entity_type}이(가) 생성되었습니다."
    when 'update'
      "#{activity.entity_type}이(가) 업데이트되었습니다."
    when 'delete'
      "#{activity.entity_type}이(가) 삭제되었습니다."
    when 'import'
      "제품이 #{activity.details&.dig('count') || '여러'}개 수집되었습니다."
    when 'publish'
      "#{activity.entity_type}이(가) 마켓플레이스에 발행되었습니다."
    when 'sync'
      "#{activity.entity_type} 동기화 완료."
    when 'error'
      "오류 발생: #{activity.error_message}"
    when 'warning'
      "경고: #{activity.error_message}"
    else
      "#{activity.action_type} - #{activity.entity_type}"
    end
  end
end
