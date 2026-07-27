# One LLM an agent can be pointed at. Rows are synced daily from models.dev
# (ModelsDev::CatalogSync), so new releases show up in the picker without a
# deploy — that's the whole point of the table. `published` and `position` are
# admin-owned and preserved across syncs; everything else models.dev owns.
#
# `provider` is OUR routing key ("anthropic" / "openrouter"), not models.dev's
# — it's what lands in AiConfig#provider, and the engine's env wiring keys off
# it (see AgentProvisioner).
class CatalogModel < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :featured,  -> { where(featured: true) }
  # Newest first, with a stable tiebreak so Telegram's index-into-the-flat-list
  # callback payloads don't shuffle between requests.
  scope :ordered,   -> { order(position: :asc, release_date: :desc, name: :asc, model_id: :asc) }

  # Shape the pickers (web, mobile, Telegram) consume.
  def to_option
    { provider: provider, model_id: model_id, label: name, hint: hint }.compact
  end

  # One line of "why would I pick this" — generated rather than hand-written so
  # it stays true for models nobody has curated. Price first (the thing people
  # actually compare), then context, then reasoning support.
  def hint
    bits = []
    bits << "#{price(cost_input)}/#{price(cost_output)} per M" if cost_input && cost_output
    bits << "#{humanized_context} context" if context_limit.to_i.positive?
    bits << "reasoning" if reasoning?
    bits.join(" · ").presence
  end

  def humanized_context
    n = context_limit.to_i
    return "#{n / 1_000_000}M" if n >= 1_000_000
    return "#{n / 1_000}K" if n >= 1_000
    n.to_s
  end

  private

  def price(value)
    d = value.to_d
    d == d.truncate ? "$#{d.to_i}" : "$#{format('%g', d)}"
  end
end
