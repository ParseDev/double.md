require "rails_helper"

RSpec.describe LiveToolBuffer do
  # Unique per example so parallel runs (and a leftover buffer from a crashed
  # run) can't bleed into each other.
  let(:agent_id) { rand(1_000_000..9_999_999) }

  after { described_class.clear(agent_id) }

  def call_event(tool:, id:, label: nil, at: 1_700_000_000_000, parent: nil)
    {
      "type" => "tool_call", "tool" => tool, "toolUseId" => id,
      "label" => label, "parentToolUseId" => parent, "timestamp" => at
    }.compact
  end

  def result_event(tool:, id: nil, result: "ok", error: false, at: 1_700_000_005_000)
    {
      "type" => "tool_result", "tool" => tool, "toolUseId" => id,
      "result" => result, "isError" => error, "timestamp" => at
    }.compact
  end

  it "folds call + result pairs into metadata.tool_history's shape" do
    described_class.record(agent_id, call_event(tool: "WebSearch", id: "tu_1", label: "Searching: cats"))
    described_class.record(agent_id, result_event(tool: "WebSearch", id: "tu_1", result: "found"))

    history = described_class.tool_history(agent_id)

    expect(history.size).to eq(1)
    step = history.first
    expect(step["id"]).to eq("tu_1")
    expect(step["tool"]).to eq("WebSearch")
    expect(step["label"]).to eq("Searching: cats")
    expect(step["result"]).to eq("found")
    expect(step["is_error"]).to be(false)
    expect(step["started_at"]).to be_present
    expect(step["ended_at"]).to be_present
  end

  it "leaves a step still running without ended_at" do
    described_class.record(agent_id, call_event(tool: "Bash", id: "tu_1"))

    step = described_class.tool_history(agent_id).first

    expect(step["started_at"]).to be_present
    expect(step).not_to have_key("ended_at")
  end

  it "matches results to the right call when the same tool runs in parallel" do
    described_class.record(agent_id, call_event(tool: "Read", id: "tu_1", label: "Read a.rb"))
    described_class.record(agent_id, call_event(tool: "Read", id: "tu_2", label: "Read b.rb"))
    described_class.record(agent_id, result_event(tool: "Read", id: "tu_2", result: "b contents"))

    history = described_class.tool_history(agent_id)

    expect(history.map { |s| s["id"] }).to eq(%w[tu_1 tu_2])
    expect(history.first).not_to have_key("ended_at")
    expect(history.last["result"]).to eq("b contents")
  end

  it "falls back to the newest open step of the same tool when no id is sent" do
    described_class.record(agent_id, call_event(tool: "Grep", id: "tu_1"))
    described_class.record(agent_id, result_event(tool: "Grep", result: "3 matches"))

    expect(described_class.tool_history(agent_id).first["result"]).to eq("3 matches")
  end

  it "flags errored steps" do
    described_class.record(agent_id, call_event(tool: "Bash", id: "tu_1"))
    described_class.record(agent_id, result_event(tool: "Bash", id: "tu_1", result: "boom", error: true))

    expect(described_class.tool_history(agent_id).first["is_error"]).to be(true)
  end

  it "keeps nesting so sub-agent steps stay indented under their Agent step" do
    described_class.record(agent_id, call_event(tool: "Agent", id: "tu_1"))
    described_class.record(agent_id, call_event(tool: "Read", id: "tu_2", parent: "tu_1"))

    expect(described_class.tool_history(agent_id).last["parent_tool_use_id"]).to eq("tu_1")
  end

  it "ignores event types it doesn't replay" do
    described_class.record(agent_id, { "type" => "text_delta", "text" => "hi" })

    expect(described_class.tool_history(agent_id)).to eq([])
  end

  it "drops oversized tool inputs rather than round-tripping file bodies" do
    described_class.record(
      agent_id,
      call_event(tool: "Write", id: "tu_1").merge("input" => { "content" => "x" * 5_000 })
    )

    expect(described_class.tool_history(agent_id).first).not_to have_key("input")
  end

  it "clears the buffer when the turn ends" do
    described_class.record(agent_id, call_event(tool: "Bash", id: "tu_1"))
    described_class.clear(agent_id)

    expect(described_class.tool_history(agent_id)).to eq([])
  end

  it "accepts symbol-keyed events" do
    described_class.record(agent_id, { type: "tool_call", tool: "Bash", toolUseId: "tu_1", timestamp: 1_700_000_000_000 })

    expect(described_class.tool_history(agent_id).first["tool"]).to eq("Bash")
  end
end
