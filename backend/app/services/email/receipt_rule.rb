module Email
  # Shape of the SES receipt rule that routes one agent address inbound.
  # Shared by channel setup, Resync, and the backfill rake task so the three
  # can't drift apart on which action a rule is supposed to carry.
  module ReceiptRule
    RULE_SET = "alchemy-inbound".freeze

    def self.name_for(address)
      "alchemy-#{address.gsub(/[^a-z0-9]/i, '-')}"
    end

    # The S3 action holds the message and notifies us with a bucket/key
    # pointer. An SNS action would inline the whole message instead and AWS
    # bounces those over 150 KB — see Email::InboundBucket.
    def self.build(address:, bucket:, topic_arn:)
      {
        name: name_for(address),
        enabled: true,
        recipients: [ address ],
        actions: [
          {
            s3_action: {
              bucket_name: bucket,
              object_key_prefix: InboundBucket::KEY_PREFIX,
              topic_arn: topic_arn
            }
          }
        ],
        scan_enabled: true
      }
    end

    def self.ensure_rule_set!(ses_client)
      ses_client.describe_receipt_rule_set(rule_set_name: RULE_SET)
    rescue Aws::SES::Errors::RuleSetDoesNotExist
      ses_client.create_receipt_rule_set(rule_set_name: RULE_SET)
      ses_client.set_active_receipt_rule_set(rule_set_name: RULE_SET)
    end

    # Create, or overwrite an existing rule. Rules created before the S3
    # migration still carry an sns_action, so "already exists" means "needs
    # updating", not "nothing to do".
    def self.upsert(ses_client, rule)
      ses_client.create_receipt_rule(rule_set_name: RULE_SET, rule: rule)
      :created
    rescue Aws::SES::Errors::AlreadyExists
      ses_client.update_receipt_rule(rule_set_name: RULE_SET, rule: rule)
      :updated
    end
  end
end
