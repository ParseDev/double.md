require "mail"

module Email
  # Parses raw email content and SES SNS notifications.
  # Returns a normalized hash with body, headers, attachments.
  class MimeParser
    Result = Struct.new(:body_text, :attachments, :message_id, :in_reply_to, :references, :conversation_id_header, keyword_init: true)

    # Parse a SES SNS notification (Hash) into a normalized result
    def self.parse_ses_notification(ses_notification)
      mail_info = ses_notification["mail"] || {}
      headers = mail_info["headers"] || []
      mail = parse_mail(ses_notification)

      Result.new(
        body_text: extract_body(mail, ses_notification),
        attachments: extract_attachments(mail),
        message_id: header(headers, "Message-ID") || mail_info["messageId"],
        in_reply_to: header(headers, "In-Reply-To"),
        references: header(headers, "References"),
        # Our outbound emails include this header with the conversation's
        # public id; the inbound reply (any modern email client) preserves
        # it verbatim, giving us a deterministic thread anchor independent
        # of Message-ID rewriting. Prefer the current Sentrel header, but
        # fall back to the legacy Doublemd one so replies to emails sent
        # before the rebrand still thread correctly.
        conversation_id_header: header(headers, "X-Sentrel-Conversation-Id") || header(headers, "X-Doublemd-Conversation-Id"),
      )
    end

    def self.extract_cc(ses_notification)
      mail_info = ses_notification["mail"] || {}
      headers = mail_info["headers"] || []

      cc = mail_info.dig("commonHeaders", "cc") || []
      if cc.empty?
        cc_header = header(headers, "Cc")
        cc = cc_header.to_s.split(",").map(&:strip).reject(&:empty?) if cc_header
      end
      cc
    end

    def self.header(headers, name)
      headers.find { |h| h["name"]&.casecmp(name) == 0 }&.dig("value")
    end

    # Build the Mail object once per notification. S3-backed messages would
    # otherwise be downloaded twice — once for the body, once for attachments.
    # Returns nil when there's no MIME to parse; RawFetcher::FetchError is
    # deliberately left to propagate so a failed download retries rather than
    # landing as a subject-only message.
    def self.parse_mail(ses_notification)
      raw = RawFetcher.call(ses_notification)
      return nil if raw.blank?

      Mail.new(raw)
    rescue RawFetcher::FetchError
      raise
    rescue => e
      Rails.logger.error "MimeParser: could not parse MIME: #{e.message}"
      nil
    end

    def self.extract_body(mail, ses_notification)
      return ses_notification.dig("mail", "commonHeaders", "subject").to_s if mail.nil?

      mail.text_part&.decoded || mail.html_part&.decoded || mail.body&.decoded || ""
    rescue => e
      Rails.logger.error "MimeParser body error: #{e.message}"
      ""
    end

    def self.extract_attachments(mail)
      return [] if mail.nil?

      mail.attachments.reject(&:inline?).map do |att|
        {
          filename: att.filename,
          content_type: att.content_type,
          body: att.body.decoded
        }
      end
    rescue => e
      Rails.logger.warn "MimeParser attachment error: #{e.message}"
      []
    end
  end
end
