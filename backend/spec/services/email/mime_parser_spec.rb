require "rails_helper"

RSpec.describe Email::MimeParser do
  let(:raw_mime) do
    <<~MIME
      From: Bob <bob@example.com>
      To: finch@ext.acme.com
      Subject: Factures en souffrance
      Message-ID: <msg-1@mail.example.com>
      In-Reply-To: <msg-0@mail.example.com>
      References: <msg-0@mail.example.com>
      X-Sentrel-Conversation-Id: cnv_123
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="b1"

      --b1
      Content-Type: text/plain; charset=UTF-8

      Voici les factures.
      --b1
      Content-Type: application/pdf; name="facture.pdf"
      Content-Disposition: attachment; filename="facture.pdf"
      Content-Transfer-Encoding: base64

      JVBERi0xLjQK
      --b1--
    MIME
  end

  let(:s3_notification) do
    {
      "mail" => {
        "messageId" => "abc123",
        "commonHeaders" => { "subject" => "Factures en souffrance" },
        "headers" => [
          { "name" => "Message-ID", "value" => "<msg-1@mail.example.com>" },
          { "name" => "In-Reply-To", "value" => "<msg-0@mail.example.com>" },
          { "name" => "X-Sentrel-Conversation-Id", "value" => "cnv_123" }
        ]
      },
      "receipt" => {
        "action" => { "type" => "S3", "bucketName" => "b", "objectKey" => "inbound/abc123" }
      }
    }
  end

  describe ".parse_ses_notification" do
    it "parses body and attachments from an S3-delivered message" do
      allow(Email::RawFetcher).to receive(:call).and_return(raw_mime)

      result = described_class.parse_ses_notification(s3_notification)

      expect(result.body_text).to include("Voici les factures.")
      expect(result.attachments.map { |a| a[:filename] }).to eq([ "facture.pdf" ])
      expect(result.message_id).to eq("<msg-1@mail.example.com>")
      expect(result.conversation_id_header).to eq("cnv_123")
    end

    it "downloads the message only once for body + attachments" do
      allow(Email::RawFetcher).to receive(:call).and_return(raw_mime)

      described_class.parse_ses_notification(s3_notification)

      expect(Email::RawFetcher).to have_received(:call).once
    end

    it "still parses inline content from a legacy SNS-action rule" do
      notification = s3_notification.merge("content" => raw_mime).except("receipt")

      result = described_class.parse_ses_notification(notification)

      expect(result.body_text).to include("Voici les factures.")
    end

    it "propagates a fetch failure instead of yielding a subject-only message" do
      allow(Email::RawFetcher).to receive(:call).and_raise(Email::RawFetcher::FetchError, "S3 down")

      expect { described_class.parse_ses_notification(s3_notification) }
        .to raise_error(Email::RawFetcher::FetchError)
    end

    it "falls back to the subject when there is genuinely no MIME to parse" do
      allow(Email::RawFetcher).to receive(:call).and_return(nil)

      result = described_class.parse_ses_notification(s3_notification)

      expect(result.body_text).to eq("Factures en souffrance")
      expect(result.attachments).to eq([])
    end
  end
end
