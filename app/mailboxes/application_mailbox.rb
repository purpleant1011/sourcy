# frozen_string_literal: true

# Base Mailbox for all email processing
# Rails 8 Action Mailbox provides email ingestion and routing
class ApplicationMailbox < ActionMailbox::Base
  # Routes emails based on sender
  routing /^admin@/i => :admin
  routing /^support@/i => :support
  routing /@sourcy\.app$/i => :account
end
