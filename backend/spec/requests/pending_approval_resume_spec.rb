require "rails_helper"

# When the agent released its turn before the human decided, Rails wakes it
# with a continuation job. That job has to carry WHAT was approved, not just
# prose: the engine replays an approved email_draft as consent so the outbox
# doesn't raise a second send_email approval for the message the user just
# okayed — a card nobody sees, on a run with no conversation to attach it to.
RSpec.describe "Approval resume payload", type: :request do
  let(:org) { create_org(name: "Resume Co", onboarding_completed_at: Time.current) }
  let(:user) { create_user(org, email: "boss@example.com", role: "owner") }
  let(:agent) { create_agent(org, name: "Finch") }

  before do
    ActsAsTenant.current_tenant = nil
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: 1))
    # Scale-to-zero: the continuation job only fires for a sleeping machine.
    # "sleeping" predates the model's status inclusion list, so it's written
    # the same way production got there — straight to the column.
    agent.update_column(:status, "sleeping")
  end

  it "echoes the payload type and decision so the engine can skip a second approval" do
    approval = with_tenant(org) do
      PendingApproval.create!(
        organization: org, agent: agent,
        tool_name: "request_approval:email_draft", payload_type: "email_draft",
        approval_token: "tok_#{SecureRandom.hex(4)}", status: "pending",
        summary: "Send billing heads-up to Liad",
        tool_input: { "to" => "liad@example.com", "subject" => "Billing" },
      )
    end

    published = nil
    allow(AgentEventBus).to receive(:publish) { |**kwargs| published = kwargs }

    sign_in user
    patch "/pending_approvals/#{approval.id}",
      params: { status: "approved" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(published[:payload]).to include(
      approvalPayloadType: "email_draft",
      approvalDecision: "approved",
      approvalSummary: "Send billing heads-up to Liad",
    )
  end
end
