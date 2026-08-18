# The props <AgentChat> needs, and nothing else.
#
# Two surfaces render the same chat — the agent detail page and the signed-in
# root — so this is the one place that decides which conversation counts as
# "the" chat, how a message serializes, and when the agent still counts as
# thinking. Two copies of that is how the two surfaces drift apart.
module AgentChatProps
  extend ActiveSupport::Concern

  private

  def agent_chat_props(agent)
    # Find internal chat conversation (boss ↔ agent). Multiple internal convs
    # exist for historical reasons — pick the most recently active one, and
    # prefer the one tied to this specific user.
    chat_conversation = agent.conversations
      .where(kind: "internal", user: current_user)
      .order(updated_at: :desc)
      .first
    # Resolve user-uploaded attachments per message so they survive a page
    # reload. ActiveStorage stores them on Message via has_many_attached;
    # we surface their URL + filename + content_type so the frontend can
    # render the same attachment chip we use during composition.
    chat_messages = if chat_conversation
      ordered_msgs = chat_conversation.messages.includes(attachments_attachments: :blob).order(id: :asc).to_a
      ordered_msgs.each_with_index.map do |m, i|
        base = m.as_json(only: [ :id, :role, :content, :channel, :metadata, :created_at, :sender_name, :sender_email, :sender_user_id ])
        base["sender"] = m.display_sender
        base["attachments"] = m.attachments.map do |att|
          blob = att.blob
            {
              filename: blob.filename.to_s,
              content_type: blob.content_type,
              byte_size: blob.byte_size,
              url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
            }
          end
          # Engine emits metadata.thinking with duration_ms=0 today, so the
          # "Thought" pill loses its time hint on reload. Fall back to the
          # turn-elapsed (this assistant's created_at minus the prior message's
          # created_at) so the pill can render "Thought for Xs" instead of a
          # bare "Thought". Tool steps inflate this beyond pure thinking time,
          # but it's the closest signal until the engine reports a real value.
          thinking = base.dig("metadata", "thinking")
          if thinking.is_a?(Hash) && thinking["text"].to_s.length > 0 && thinking["duration_ms"].to_i <= 0
            prior = ordered_msgs[i - 1] if i > 0
            if prior
              gap_ms = ((m.created_at - prior.created_at) * 1000).to_i
              base["metadata"] = base["metadata"].merge(
                "thinking" => thinking.merge("duration_ms" => [ gap_ms, 0 ].max)
              )
            end
          end
          base
        end
    else
        []
    end

      # Surface "agent is thinking" across page reloads / new tabs. Heuristic:
      # find the most recent user message and see if any assistant message
      # exists *after* it. If not, and the user message is recent (<15 min),
      # the run is still in flight. Compare on created_at — m["id"] is the
      # PrefixedIds string ("msg_abc123") not the integer, so id.to_i would
      # always return 0 and the comparison would never match. Frontend
      # hydrates the indicator from this on mount and clears it via cable /
      # poll once a reply lands.
      agent_thinking = nil
      if chat_messages.any?
        last_user_msg = chat_messages.reverse.find { |m| m["role"] == "user" }
        if last_user_msg && last_user_msg["created_at"].to_time > 15.minutes.ago
          last_user_at = last_user_msg["created_at"].to_time
          has_reply = chat_messages.any? { |m|
            m["role"] == "assistant" &&
              m["content"].to_s.strip.length > 0 &&
              m["created_at"].to_time > last_user_at
          }
          unless has_reply
            agent_thinking = {
              since: last_user_msg["created_at"],
              after: last_user_msg["created_at"]
            }
          end
        end
      end

      # Get approvals keyed by message_id for inline rendering
      approvals_by_message = agent.pending_approvals
        .where.not(message_id: nil)
        .where("created_at > ?", 7.days.ago)
        .group_by(&:message_id)
        .transform_values { |approvals|
          approvals.map { |a| a.as_json(only: [ :id, :tool_name, :tool_input, :status, :created_at ]) }
        }

      # Item 4 — pending generic action approvals (request_approval) so the
      # inline chat card survives a page refresh. The card is hydrated from
      # this prop on mount; its DB row stays the source of truth.
      pending_action_approvals = agent.pending_approvals
        .where(status: "pending")
        .where.not(payload_type: nil)
        .where("created_at > ?", 24.hours.ago)
        .order(created_at: :desc)
        .limit(5)
        .map { |a|
          {
            id: a.id,
            approval_token: a.approval_token,
            summary: a.summary,
            payload_type: a.payload_type,
            payload: a.tool_input,
            options: a.options.presence || [
              { label: "Approve", value: "approve" },
              { label: "Reject", value: "reject" }
            ],
            risk_tier: a.risk_tier,
            allow_amendment: a.tool_input.is_a?(Hash) && a.tool_input["_allow_amendment"] == true,
            created_at: a.created_at
          }
        }

    {
      chat_messages: chat_messages,
      agent_thinking: agent_thinking,
      # Tool steps of a run that's still in flight. The assistant message
      # carries metadata.tool_history once the turn ends; until then this
      # mirror is the only way a freshly-loaded page can show the steps that
      # already streamed past. Same shape as metadata.tool_history.
      live_tool_steps: agent_thinking ? LiveToolBuffer.tool_history(agent.id) : [],
      approvals_by_message: approvals_by_message,
      pending_action_approvals: pending_action_approvals
    }
  end
end
