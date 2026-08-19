require "aws-sdk-s3"

module Email
  # Resolves the raw MIME bytes for an inbound SES notification.
  #
  # SES delivers inbound mail to us one of two ways:
  #   * S3 action  — SES writes the message to a bucket and the notification
  #     carries only a bucket/key pointer. This is what we provision now.
  #   * SNS action — the raw message rides inline in `content`. Rules created
  #     before the S3 migration still do this, so we keep accepting it.
  class RawFetcher
    class FetchError < StandardError; end

    def self.call(notification)
      inline = notification["content"]
      return inline if inline.present?

      action = notification.dig("receipt", "action") || {}
      return nil unless action["type"] == "S3"

      key = action["objectKey"]
      return nil if key.blank?

      fetch_from_s3(action["bucketName"], key)
    end

    def self.fetch_from_s3(bucket, key)
      raise FetchError, "S3 action gave objectKey=#{key} with no bucketName" if bucket.blank?

      begin
        SesClient.s3_for.get_object(bucket: bucket, key: key).body.read
      rescue Aws::S3::Errors::ServiceError => e
        # An org with a custom SES region keeps its bucket there, and the
        # notification names the bucket but never its region. A cross-region
        # request comes back as a redirect that does name it, so retry once
        # against the right endpoint before giving up.
        region = bucket_region_from(e)
        raise if region.blank?

        SesClient.s3_for(region: region).get_object(bucket: bucket, key: key).body.read
      end
    rescue Aws::S3::Errors::ServiceError => e
      # Raise rather than degrade: MimeParser falls back to a subject-only
      # body when it has no MIME, so swallowing this would turn a transient
      # S3 error into an email whose contents are silently gone. Raising
      # 500s the webhook, and SNS redelivers.
      raise FetchError, "S3 get_object failed bucket=#{bucket} key=#{key}: #{e.class.name.demodulize}: #{e.message}"
    end

    def self.bucket_region_from(error)
      error.context&.http_response&.headers&.[]("x-amz-bucket-region")
    end
  end
end
