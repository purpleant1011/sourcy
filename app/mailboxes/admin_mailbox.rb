# frozen_string_literal: true

# Admin email processing mailbox
# Handles administrative emails (alerts, reports, system notifications)
class AdminMailbox < ApplicationMailbox
  # Process incoming admin emails
  def process
    # Example: Parse command from subject line
    # Subject: "STATS" → Generate dashboard stats report
    # Subject: "ALERT" → Create alert notification

    case mail.subject.to_s.upcase
    when /STATS/
      generate_stats_report
    when /ALERT/
      create_alert
    when /REPORT/
      generate_custom_report
    else
      log_unrecognized_email
    end
  end

  private

  def generate_stats_report
    # Generate dashboard stats and email back
    AdminMailer.stats_report(current_account).deliver_later
  end

  def create_alert
    # Create alert notification from email body
    Alert.create!(
      title: mail.subject,
      description: mail.decoded,
      severity: :high,
      source: :email
    )
  end

  def generate_custom_report
    # Generate custom report based on email parameters
    # Parse parameters from email body
    params = parse_email_parameters
    ReportGeneratorJob.perform_later(params)
  end

  def log_unrecognized_email
    Rails.logger.warn "Unrecognized admin email from #{mail.from}: #{mail.subject}"
  end

  def parse_email_parameters
    # Parse JSON or key-value pairs from email body
    body = mail.decoded
    JSON.parse(body) rescue {}
  end
end
