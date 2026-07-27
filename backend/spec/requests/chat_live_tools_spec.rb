require "rails_helper"

RSpec.describe "Chat live tool steps", type: :request do
  let(:org) { create_org(name: "Live Tools Co", onboarding_completed_at: Time.current) }
  let(:user) { create_user(org, email: "owner@example.com", role: "owner") }
  let(:agent) { create_agent(org) }

  before { ActsAsTenant.current_tenant = nil }

  after { LiveToolBuffer.clear(agent.id) }

  describe "GET /agents/:agent_id/chat/live_tools" do
    it "requires a signed-in user" do
      get "/agents/#{agent.to_param}/chat/live_tools"

      expect(response).not_to have_http_status(:ok)
    end

    it "replays the in-flight run's tool steps for a page that reloaded mid-run" do
      sign_in user
      LiveToolBuffer.record(agent.id, {
        "type" => "tool_call", "tool" => "WebSearch", "toolUseId" => "tu_1",
        "label" => "Searching: cats", "timestamp" => 1_700_000_000_000
      })
      LiveToolBuffer.record(agent.id, {
        "type" => "tool_result", "tool" => "WebSearch", "toolUseId" => "tu_1",
        "result" => "found", "timestamp" => 1_700_000_002_000
      })

      get "/agents/#{agent.to_param}/chat/live_tools", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      steps = JSON.parse(response.body)["tool_history"]
      expect(steps.map { |s| s["id"] }).to eq([ "tu_1" ])
      expect(steps.first).to include("tool" => "WebSearch", "label" => "Searching: cats", "result" => "found")
    end

    it "returns an empty timeline when nothing is running" do
      sign_in user

      get "/agents/#{agent.to_param}/chat/live_tools", headers: { "Accept" => "application/json" }

      expect(JSON.parse(response.body)["tool_history"]).to eq([])
    end
  end
end
