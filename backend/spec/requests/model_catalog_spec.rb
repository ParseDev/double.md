require "rails_helper"

RSpec.describe "Model catalog", type: :request do
  let(:org) { create_org(name: "Catalog Co", onboarding_completed_at: Time.current) }
  let(:user) { create_user(org, email: "owner@example.com", role: "owner") }

  before { ActsAsTenant.current_tenant = nil }

  describe "GET /model_catalog" do
    before do
      CatalogModel.create!(
        provider: "anthropic", model_id: "claude-opus-9", name: "Claude Opus 9",
        featured: true, tool_call: true, context_limit: 1_000_000,
        cost_input: 5, cost_output: 25, synced_at: Time.current
      )
      CatalogModel.create!(
        provider: "openrouter", model_id: "openai/gpt-9", name: "GPT-9",
        tool_call: true, context_limit: 400_000, synced_at: Time.current
      )
    end

    it "requires a signed-in user" do
      get model_catalog_path

      expect(response).not_to have_http_status(:ok)
    end

    it "serves the featured groups plus every synced model" do
      sign_in user

      get model_catalog_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["groups"].flat_map { |g| g["options"] }.map { |o| o["model_id"] }).to eq([ "claude-opus-9" ])
      expect(body["all"].map { |m| m["model_id"] }).to match_array(%w[claude-opus-9 openai/gpt-9])
      expect(body["synced_at"]).to be_present
    end

    it "carries the capability flags the search UI warns on" do
      sign_in user

      get model_catalog_path, headers: { "Accept" => "application/json" }

      gpt = JSON.parse(response.body)["all"].find { |m| m["model_id"] == "openai/gpt-9" }
      expect(gpt).to include("tool_call" => true, "context" => 400_000)
    end
  end
end
