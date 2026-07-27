require "redis"
require "json"

# Replay buffer for the tool steps of an in-flight run.
#
# The engine streams `tool_call` / `tool_result` over the cable and the chat
# accumulates them into the step pills above the assistant reply. A browser
# that reloads mid-run subscribes to the cable *after* those events fired, so
# every step that already happened was lost — the reader saw a bare "working"
# animation and no history until the turn ended and metadata.tool_history
# landed on the saved message.
#
# We mirror the events into a Redis list as they relay through
# Api::AgentEventsController, and hand them back folded into the same shape
# the engine persists as metadata.tool_history, so the chat rehydrates
# through one code path whether the turn is finished or still running.
#
# Scoped per agent, matching AgentChatChannel: a run started from Slack while
# you watch the web chat shows up here too — exactly as it does live.
module LiveToolBuffer
  KEY_PREFIX = "agent-live-tools-".freeze
  # Long enough to cover a slow multi-tool turn, short enough that a run the
  # engine died on can't haunt the next one.
  TTL = 30.minutes.to_i
  MAX_EVENTS = 400
  # Tool inputs are only used for the Edit/Write diff badge — anything larger
  # than this is a file body we'd be round-tripping through Redis for nothing.
  MAX_INPUT_BYTES = 2000

  module_function

  # Mirror one relayed engine event. No-ops for every type but the two we
  # replay. Never raises — a buffering failure must not drop the broadcast.
  def record(agent_id, event)
    type = fetch(event, "type")
    return unless type == "tool_call" || type == "tool_result"

    entry = {
      "type" => type,
      "tool" => fetch(event, "tool").to_s,
      "toolUseId" => presence(fetch(event, "toolUseId")),
      "parentToolUseId" => presence(fetch(event, "parentToolUseId")),
      "label" => presence(fetch(event, "label")),
      "input" => bounded_input(fetch(event, "input")),
      "result" => presence(fetch(event, "result"))&.slice(0, 500),
      "isError" => fetch(event, "isError") == true,
      "timestamp" => fetch(event, "timestamp")
    }.compact

    key = key_for(agent_id)
    redis.multi do |r|
      r.rpush(key, entry.to_json)
      r.ltrim(key, -MAX_EVENTS, -1)
      r.expire(key, TTL)
    end
    nil
  rescue => e
    Rails.logger.warn("[LiveToolBuffer] record failed for agent #{agent_id}: #{e.class}: #{e.message}")
    nil
  end

  # Drop the buffer — the turn ended, so the saved message's
  # metadata.tool_history is now the source of truth.
  def clear(agent_id)
    redis.del(key_for(agent_id))
    nil
  rescue => e
    Rails.logger.warn("[LiveToolBuffer] clear failed for agent #{agent_id}: #{e.class}: #{e.message}")
    nil
  end

  # Fold the buffered events into metadata.tool_history's shape. Steps still
  # running come back without `ended_at`, which is how the chat knows to keep
  # spinning on them.
  def tool_history(agent_id)
    ordered = []
    by_id = {}

    raw_events(agent_id).each do |e|
      case e["type"]
      when "tool_call"
        id = presence(e["toolUseId"]) || "#{e['tool']}-#{ordered.size}"
        next if by_id.key?(id)
        entry = {
          "id" => id,
          "tool" => e["tool"].to_s,
          "label" => presence(e["label"]) || e["tool"].to_s,
          "input" => e["input"],
          "started_at" => iso(e["timestamp"]),
          "parent_tool_use_id" => presence(e["parentToolUseId"])
        }.compact
        by_id[id] = entry
        ordered << entry
      when "tool_result"
        # Match on tool_use id when the engine sent one; otherwise close the
        # most recent still-open step with the same tool name (same fallback
        # the live cable handler uses).
        entry = by_id[presence(e["toolUseId"]).to_s]
        entry ||= ordered.reverse.find { |x| x["tool"] == e["tool"].to_s && !x.key?("ended_at") }
        next unless entry
        entry["result"] = e["result"] if e["result"]
        entry["is_error"] = e["isError"] == true
        entry["ended_at"] = iso(e["timestamp"])
      end
    end

    ordered
  rescue => e
    Rails.logger.warn("[LiveToolBuffer] tool_history failed for agent #{agent_id}: #{e.class}: #{e.message}")
    []
  end

  def key_for(agent_id)
    "#{KEY_PREFIX}#{agent_id}"
  end

  def raw_events(agent_id)
    redis.lrange(key_for(agent_id), 0, -1).filter_map do |raw|
      JSON.parse(raw) rescue nil
    end
  end

  def redis
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end

  # Engine events arrive as ActionController params (string keys) in prod and
  # as plain symbol-keyed hashes from specs — accept both.
  def fetch(event, key)
    return nil unless event.respond_to?(:[])
    event[key].nil? ? event[key.to_sym] : event[key]
  end

  def presence(value)
    str = value.to_s
    str.empty? ? nil : str
  end

  def bounded_input(input)
    return nil if input.nil?
    input.to_json.bytesize > MAX_INPUT_BYTES ? nil : input
  rescue
    nil
  end

  def iso(timestamp)
    ms = timestamp.to_i
    return nil if ms <= 0
    Time.at(ms / 1000.0).utc.iso8601(3)
  end
end
