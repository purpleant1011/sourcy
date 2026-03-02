# frozen_string_literal: true

# Support email processing mailbox
# Handles customer support emails and automatically creates tickets
class SupportMailbox < ApplicationMailbox
  # Process incoming support emails
  def process
    # Automatically create support ticket from email
    create_support_ticket

    # Send auto-reply to sender
    send_auto_reply
  end

  private

  def create_support_ticket
    # Extract sender information
    sender_email = mail.from&.first
    sender_name = mail['from']&.display_names&.first || sender_email

    # Create or find user by email
    user = User.find_by(email: sender_email) || create_guest_user(sender_email, sender_name)

    # Extract order number from subject if present
    order_number = extract_order_number(mail.subject)

    # Create support ticket
    ticket = SupportTicket.create!(
      user: user,
      account: current_account || user&.account,
      subject: mail.subject,
      description: mail.decoded,
      priority: determine_priority(mail.subject),
      order_id: find_order_id(order_number),
      status: :open,
      source: :email
    )

    # Attach any email attachments to the ticket
    attach_email_files(ticket)
  end

  def send_auto_reply
    SupportMailer.auto_reply(mail.from.first, mail.subject).deliver_later
  end

  def extract_order_number(subject)
    # Extract order number patterns like "Order #12345" or "주문번호 12345"
    subject.to_s[/[#숀]*(\d{6,})/, 1]
  end

  def find_order_id(order_number)
    return nil unless order_number
    Order.find_by(marketplace_order_number: order_number)&.id
  end

  def determine_priority(subject)
    subject_str = subject.to_s.upcase
    case subject_str
    when /긴급|URGENT|EMERGENCY/
      :urgent
    when /높음|HIGH/
      :high
    else
      :normal
    end
  end

  def create_guest_user(email, name)
    User.create!(
      email: email,
      full_name: name,
      password: SecureRandom.hex(16),
      guest: true
    )
  end

  def attach_email_files(ticket)
    return unless mail.attachments.present?

    mail.attachments.each do |attachment|
      ticket.attachments.attach(
        io: attachment.body.to_s,
        filename: attachment.filename,
        content_type: attachment.content_type
      )
    end
  end
end
