require "rails_helper"

RSpec.describe ModelsDev::CatalogSync do
  def model(name:, release_date:, tool_call: true, output: [ "text" ], family: nil, cost_output: 10)
    {
      "name" => name, "family" => family, "release_date" => release_date,
      "tool_call" => tool_call, "reasoning" => true,
      "modalities" => { "input" => [ "text" ], "output" => output },
      "limit" => { "context" => 1_000_000, "output" => 64_000 },
      "cost" => { "input" => 3, "output" => cost_output }
    }
  end

  let(:payload) do
    {
      "anthropic" => { "models" => {
        "claude-opus-9" => model(name: "Claude Opus 9", release_date: "2026-07-01"),
        "claude-opus-9-20260701" => model(name: "Claude Opus 9 (pinned)", release_date: "2026-07-01"),
        "claude-sonnet-9" => model(name: "Claude Sonnet 9 (latest)", release_date: "2026-06-01")
      } },
      "openrouter" => { "models" => {
        "openai/gpt-9" => model(name: "GPT-9", release_date: "2026-07-10", family: "gpt"),
        "openai/gpt-9-mini" => model(name: "GPT-9 mini", release_date: "2026-07-09", family: "gpt-mini"),
        "google/gemini-9-image" => model(name: "Gemini 9 Image", release_date: "2026-07-20", family: "gemini"),
        "obscurelabs/whatever-1" => model(name: "Whatever 1", release_date: "2026-07-22"),
        "x-ai/grok-9" => model(name: "Grok 9", release_date: "2026-07-05", tool_call: false),
        "openai/gpt-9-free:free" => model(name: "GPT-9 free", release_date: "2026-07-10"),
        "~openai/gpt-latest" => model(name: "GPT latest", release_date: "2026-07-11"),
        "google/veo-9" => model(name: "Veo 9", release_date: "2026-07-12", output: [ "video" ])
      } },
      "someoneelse" => { "models" => { "x" => model(name: "X", release_date: "2026-07-01") } }
    }
  end

  before { allow(described_class).to receive(:fetch).and_return(payload) }

  it "imports only the providers we can route to" do
    described_class.run

    expect(CatalogModel.distinct.pluck(:provider)).to match_array(%w[anthropic openrouter])
  end

  it "skips aliases, free tiers and models that can't emit text" do
    described_class.run
    ids = CatalogModel.pluck(:model_id)

    expect(ids).not_to include("~openai/gpt-latest", "openai/gpt-9-free:free", "google/veo-9")
    expect(ids).to include("openai/gpt-9")
  end

  it "stores the pricing and capability columns the picker shows" do
    described_class.run
    m = CatalogModel.find_by!(provider: "anthropic", model_id: "claude-opus-9")

    expect(m.name).to eq("Claude Opus 9")
    expect(m.context_limit).to eq(1_000_000)
    expect(m.cost_input).to eq(3)
    expect(m.reasoning).to be(true)
    expect(m.tool_call).to be(true)
    expect(m.release_date).to eq(Date.new(2026, 7, 1))
  end

  it "strips the redundant (latest) suffix from names" do
    described_class.run

    expect(CatalogModel.find_by!(model_id: "claude-sonnet-9").name).to eq("Claude Sonnet 9")
  end

  it "features recent Claude releases but not their date-pinned duplicates" do
    described_class.run
    featured = CatalogModel.where(provider: "anthropic").featured.pluck(:model_id)

    expect(featured).to include("claude-opus-9", "claude-sonnet-9")
    expect(featured).not_to include("claude-opus-9-20260701")
  end

  it "features one model per known vendor and skips unknown vendors" do
    described_class.run
    featured = CatalogModel.where(provider: "openrouter").featured.pluck(:model_id)

    expect(featured).to eq([ "openai/gpt-9" ])
    expect(featured).not_to include("obscurelabs/whatever-1")
  end

  it "never features a model that can't call tools or an image generator" do
    described_class.run

    expect(CatalogModel.find_by!(model_id: "x-ai/grok-9").featured).to be(false)
    expect(CatalogModel.find_by!(model_id: "google/gemini-9-image").featured).to be(false)
  end

  it "is idempotent and prunes models that disappeared upstream" do
    described_class.run
    stale = CatalogModel.create!(provider: "openrouter", model_id: "openai/gpt-8", name: "GPT-8")

    result = described_class.run

    expect(CatalogModel.exists?(stale.id)).to be(false)
    expect(result[:pruned]).to eq(1)
    expect(CatalogModel.where(model_id: "openai/gpt-9").count).to eq(1)
  end

  it "preserves the admin-owned published flag across syncs" do
    described_class.run
    CatalogModel.find_by!(model_id: "openai/gpt-9").update!(published: false)

    described_class.run

    expect(CatalogModel.find_by!(model_id: "openai/gpt-9").published).to be(false)
  end

  it "reports a skip instead of wiping the table when models.dev is down" do
    described_class.run
    allow(described_class).to receive(:fetch).and_return(nil)

    expect(described_class.run[:synced]).to eq(0)
    expect(CatalogModel.count).to be > 0
  end
end
