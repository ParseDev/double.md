require "rails_helper"

RSpec.describe Email::RawFetcher do
  let(:raw_mime) { "From: bob@example.com\r\nSubject: Hi\r\n\r\nBody text" }

  def s3_notification(bucket: "alchemy-ses-inbound-123-us-east-1", key: "inbound/abc123")
    {
      "mail" => { "messageId" => "abc123" },
      "receipt" => {
        "action" => {
          "type" => "S3",
          "topicArn" => "arn:aws:sns:us-east-1:123:alchemy-email-acme",
          "bucketName" => bucket,
          "objectKeyPrefix" => "inbound/",
          "objectKey" => key
        }
      }
    }
  end

  def service_error(klass = Aws::S3::Errors::NoSuchKey, headers: {})
    http_response = double("HttpResponse", headers: headers, body_contents: "")
    context = double("Context", http_response: http_response)
    klass.new(context, "boom")
  end

  describe ".call" do
    it "returns inline content when the notification carries it (legacy SNS action)" do
      notification = { "content" => raw_mime, "receipt" => { "action" => { "type" => "SNS" } } }

      expect(described_class.call(notification)).to eq(raw_mime)
      expect(SesClient).not_to receive(:s3_for)
    end

    it "downloads from S3 when the notification is a pointer" do
      body = double("Body", read: raw_mime)
      s3 = instance_double(Aws::S3::Client, get_object: double("Response", body: body))
      allow(SesClient).to receive(:s3_for).and_return(s3)

      expect(described_class.call(s3_notification)).to eq(raw_mime)
      expect(s3).to have_received(:get_object)
        .with(bucket: "alchemy-ses-inbound-123-us-east-1", key: "inbound/abc123")
    end

    it "returns nil for an action type that carries no message" do
      notification = { "receipt" => { "action" => { "type" => "Lambda" } } }

      expect(described_class.call(notification)).to be_nil
    end

    it "returns nil when there is neither content nor an action" do
      expect(described_class.call({ "mail" => {} })).to be_nil
    end
  end

  describe "failure handling" do
    it "raises FetchError rather than degrading when S3 is unreachable" do
      s3 = instance_double(Aws::S3::Client)
      allow(s3).to receive(:get_object).and_raise(service_error)
      allow(SesClient).to receive(:s3_for).and_return(s3)

      expect { described_class.call(s3_notification) }
        .to raise_error(Email::RawFetcher::FetchError, /NoSuchKey/)
    end

    it "raises FetchError when the action names a key but no bucket" do
      expect { described_class.call(s3_notification(bucket: nil)) }
        .to raise_error(Email::RawFetcher::FetchError, /no bucketName/)
    end

    it "retries against the bucket's real region on a cross-region redirect" do
      redirect = service_error(Aws::S3::Errors::PermanentRedirect, headers: { "x-amz-bucket-region" => "eu-west-1" })
      wrong_region = instance_double(Aws::S3::Client)
      allow(wrong_region).to receive(:get_object).and_raise(redirect)

      body = double("Body", read: raw_mime)
      right_region = instance_double(Aws::S3::Client, get_object: double("Response", body: body))

      allow(SesClient).to receive(:s3_for).with(no_args).and_return(wrong_region)
      allow(SesClient).to receive(:s3_for).with(region: "eu-west-1").and_return(right_region)

      expect(described_class.call(s3_notification)).to eq(raw_mime)
    end
  end
end
