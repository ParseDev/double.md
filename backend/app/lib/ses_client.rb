require "aws-sdk-s3"

module SesClient
  # Returns an SES client configured for the given organization.
  # Falls back to global env config if org has no specific region set.
  def self.for(org)
    Aws::SES::Client.new(region: region_for(org))
  end

  def self.sns_for(org)
    Aws::SNS::Client.new(region: region_for(org))
  end

  # `region:` overrides the org/env default — used when talking to a bucket
  # that lives somewhere other than the org's SES region.
  def self.s3_for(org = nil, region: nil)
    Aws::S3::Client.new(region: region.presence || region_for(org))
  end

  def self.region_for(org)
    org&.email_aws_region.presence || ENV.fetch("AWS_REGION", "us-east-1")
  end

  # AWS_ACCOUNT_ID is sometimes set in the hyphenated display form
  # (9471-3198-7715). ARNs and IAM policy conditions need the bare 12 digits.
  def self.account_id
    ENV["AWS_ACCOUNT_ID"].to_s.gsub(/\D/, "").presence
  end
end
