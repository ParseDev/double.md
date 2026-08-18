class DashboardController < ApplicationController
  include AgentChatProps

  before_action :authenticate_user!

  # The signed-in root is a chat, not a report. Landing on stat tiles meant
  # every session started with a click to get to the thing people actually
  # came for, so this opens straight into a conversation with whichever agent
  # was last active. The agent list lives in the sidebar; this renders the
  # right-hand side of it.
  def index
    agent = default_chat_agent

    props = { agent: agent && chat_agent_json(agent) }
    props.merge!(agent_chat_props(agent)) if agent

    render inertia: "dashboard/index", props: props
  end

  private

  # Most recently active first — "active" meaning the internal chat this user
  # last exchanged a message in, so returning to the root picks up where they
  # left off rather than on whichever agent happens to sort first. Falls back
  # to the newest agent for a user who has not chatted with any of them yet.
  def default_chat_agent
    scope = current_tenant.agents.includes(:instance)

    last_chatted = scope
      .joins(:conversations)
      .where(conversations: { kind: "internal", user_id: current_user.id })
      .order("conversations.updated_at DESC")
      .first

    last_chatted || scope.order(created_at: :desc).first
  end

  def chat_agent_json(agent)
    agent.as_json(only: [ :id, :name, :slug, :role, :status ]).merge(
      instance_status: agent.instance&.status
    )
  end
end
