require "aws-sdk-s3"

module Email
  # Owns the S3 bucket that SES receipt rules write inbound mail into.
  #
  # Inbound mail is delivered via an S3 action rather than an SNS action
  # because the SNS action caps the *entire* message at 150 KB and AWS bounces
  # anything larger (see the "Publish to Amazon SNS topic action" note in the
  # SES docs). A long reply chain with an inline image crosses that line
  # easily: the sender gets a MAILER-DAEMON from amazonses.com and the agent
  # never learns the mail existed. The S3 action's ceiling is SES's own 40 MB
  # message limit instead.
  class InboundBucket
    KEY_PREFIX = "inbound/".freeze

    # Raw MIME is copied into the message record + Active Storage during
    # processing, so the bucket only needs to cover retries and debugging.
    RETENTION_DAYS = 30

    class MisconfiguredError < StandardError; end

    class << self
      # Bucket names are globally unique, so scope ours by account + region.
      def name_for(org = nil)
        return ENV["SES_INBOUND_BUCKET"] if ENV["SES_INBOUND_BUCKET"].present?

        account = SesClient.account_id
        raise MisconfiguredError, "AWS_ACCOUNT_ID is not set — cannot derive the SES inbound bucket name" if account.blank?

        "alchemy-ses-inbound-#{account}-#{region_for(org)}"
      end

      def region_for(org = nil)
        SesClient.region_for(org)
      end

      # Idempotent. Creates the bucket if it's missing, then (re)applies the
      # public access block, the SES write policy, and the retention rule.
      # Returns the bucket name so the caller can point a receipt rule at it.
      def ensure!(org = nil)
        bucket = name_for(org)
        region = region_for(org)
        s3 = SesClient.s3_for(org, region: region)

        create_bucket(s3, bucket, region) unless exists?(s3, bucket)
        block_public_access(s3, bucket)
        put_ses_write_policy(s3, bucket)
        put_retention_rule(s3, bucket)

        bucket
      end

      private

      def exists?(s3, bucket)
        s3.head_bucket(bucket: bucket)
        true
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
        false
      end

      def create_bucket(s3, bucket, region)
        params = { bucket: bucket }
        # us-east-1 is the API default and rejects an explicit constraint.
        params[:create_bucket_configuration] = { location_constraint: region } unless region == "us-east-1"
        s3.create_bucket(**params)
      rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
        # Raced with another provisioning call — fine.
      end

      def block_public_access(s3, bucket)
        s3.put_public_access_block(
          bucket: bucket,
          public_access_block_configuration: {
            block_public_acls: true,
            ignore_public_acls: true,
            block_public_policy: false, # the SES service-principal policy below is not "public"
            restrict_public_buckets: true
          }
        )
      end

      # Scoping to our own account is what stops another AWS customer's SES
      # from writing into this bucket (the confused-deputy case AWS warns
      # about); the service principal alone would not.
      def put_ses_write_policy(s3, bucket)
        account = SesClient.account_id
        raise MisconfiguredError, "AWS_ACCOUNT_ID is not set — cannot write the SES bucket policy" if account.blank?

        policy = {
          "Version" => "2012-10-17",
          "Statement" => [
            {
              "Sid" => "AllowSESInboundPuts",
              "Effect" => "Allow",
              "Principal" => { "Service" => "ses.amazonaws.com" },
              "Action" => "s3:PutObject",
              "Resource" => "arn:aws:s3:::#{bucket}/#{KEY_PREFIX}*",
              "Condition" => { "StringEquals" => { "AWS:SourceAccount" => account } }
            }
          ]
        }

        s3.put_bucket_policy(bucket: bucket, policy: policy.to_json)
      end

      def put_retention_rule(s3, bucket)
        s3.put_bucket_lifecycle_configuration(
          bucket: bucket,
          lifecycle_configuration: {
            rules: [
              {
                id: "expire-raw-inbound",
                status: "Enabled",
                filter: { prefix: KEY_PREFIX },
                expiration: { days: RETENTION_DAYS }
              }
            ]
          }
        )
      end
    end
  end
end
