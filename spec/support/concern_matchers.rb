# frozen_string_literal: true

# Custom matchers for RSpec
RSpec::Matchers.define :be_account_scoped do |matcher|
  match do |actual|
    actual.class.included_modules.include?(AccountScoped)
  end

  description { "be account scoped" }
  failure_message { "expected #{actual} to include AccountScoped concern" }
end

RSpec::Matchers.define :be_auditable do |matcher|
  match do |actual|
    actual.class.included_modules.include?(Auditable)
  end

  description { "be auditable" }
  failure_message { "expected #{actual} to include Auditable concern" }
end
