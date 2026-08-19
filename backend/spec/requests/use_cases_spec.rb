require "rails_helper"
require "inertia_rails/rspec"

RSpec.describe "Use cases catalog", type: :request do
  let(:org) { create_org(name: "Use Case Co", onboarding_completed_at: Time.current) }

  before { ActsAsTenant.current_tenant = nil }

  describe "GET /use-cases" do
    it "renders for a logged-out visitor" do
      get use_cases_path

      expect(response).to have_http_status(:ok)
    end

    it "tags a role with template_slug when a public template matches it" do
      AgentTemplate.create!(
        slug: "sdr-outbound", name: "SDR", role: "SDR (outbound)", published: true
      )

      get use_cases_path

      expect(role_named("SDR (outbound)")[:template_slug]).to eq("sdr-outbound")
    end

    it "does not leak an org-owned template slug onto the public page" do
      AgentTemplate.create!(
        slug: "support-triage", name: "Jamie", role: "Support triage",
        published: true, organization_id: org.id
      )

      get use_cases_path

      expect(role_named("Support triage")).not_to have_key(:template_slug)
    end
  end

  def role_named(role)
    inertia.props[:categories].flat_map { |c| c[:roles] }.find { |r| r[:role] == role }
  end
end
