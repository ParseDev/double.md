require "rails_helper"

# The agent page used to show inbound mail only: a delivered email was buried
# inside a thread, a draft waiting on a human was invisible, and a send SES
# rejected left no trace at all in the UI. `sent_emails` is the one feed that
# answers "did it actually go out?".
RSpec.describe "Agent sent-email feed", type: :request do
  let(:org) { create_org(name: "Outbox Co", onboarding_completed_at: Time.current) }
  let(:user) { create_user(org, email: "boss@example.com", role: "owner") }
  let(:agent) { create_agent(org, name: "Finch") }

  before { ActsAsTenant.current_tenant = nil }

  # Ask Inertia for the JSON page object rather than the HTML shell, so the
  # assertions read the props directly.
  def sent_emails
    sign_in user
    version = InertiaRails.configuration.version
    version = version.call if version.respond_to?(:call)
    get "/agents/#{agent.to_param}", headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => version.to_s,
      "X-Requested-With" => "XMLHttpRequest"
    }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).dig("props", "sent_emails")
  end

  it "reports a delivered email with its Cc list" do
    conv = create_conversation(agent, contact_email: "lead@acme.com")
    with_tenant(org) do
      create_message(conv,
        role: "assistant", direction: "outbound", channel: "email",
        content: "Heads up, your invoice is due.",
        metadata: {
          "to" => [ "lead@acme.com" ], "cc" => [ "boss@example.com" ],
          "subject" => "Invoice due", "ses_message_id" => "ses-1"
        })
    end

    row = sent_emails.first
    expect(row).to include(
      "state" => "sent",
      "to" => [ "lead@acme.com" ],
      "cc" => [ "boss@example.com" ],
      "subject" => "Invoice due",
    )
  end

  it "surfaces a draft still waiting on a human, so an approved-but-unsent email can't hide" do
    with_tenant(org) do
      PendingApproval.create!(
        organization: org, agent: agent, tool_name: "send_email", status: "pending",
        tool_input: {
          "to" => "lead@acme.com", "cc" => [ "boss@example.com" ],
          "subject" => "Invoice due", "body_text" => "Heads up."
        },
      )
    end

    row = sent_emails.first
    expect(row).to include("state" => "awaiting_approval", "subject" => "Invoice due")
    expect(row["cc"]).to eq([ "boss@example.com" ])
    expect(row["approval_id"]).to be_present
  end

  it "surfaces a failed send — no Message row is ever written for those" do
    with_tenant(org) do
      AuditLog.create!(
        organization: org, agent: agent, action: "email_failed", tool_name: "send_email",
        input: { "to" => [ "lead@acme.com" ], "subject" => "Invoice due" },
        output: { "error" => "Domain not verified: acme.test" },
        status: "failed",
      )
    end

    row = sent_emails.first
    expect(row).to include("state" => "failed", "error" => "Domain not verified: acme.test")
  end

  it "ignores chat replies that ride the email channel but carry no recipient" do
    conv = create_conversation(agent, contact_email: "lead@acme.com")
    with_tenant(org) do
      create_message(conv,
        role: "assistant", direction: "outbound", channel: "email",
        content: "Sure, I'll get on that.", metadata: {})
    end

    expect(sent_emails).to be_empty
  end
end
