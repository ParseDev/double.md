require "net/http"
require "json"

module ModelsDev
  # Populates catalog_models from models.dev's public catalog (~3MB of every
  # model every provider ships). Runs daily on a cron + on demand, so a model
  # released this morning is pickable this afternoon without a deploy.
  #
  # We only import the providers we can actually route to:
  #   anthropic  — Claude direct (also backs the "Your Claude subscription"
  #                group, which uses the same model ids over OAuth)
  #   openrouter — everything else; the engine points ANTHROPIC_BASE_URL at
  #                OpenRouter and passes the slug through (see AgentProvisioner)
  #
  # Idempotent upsert keyed by [provider, model_id]. `published` / `position`
  # are admin-owned and never touched here; `featured` is ours, and is
  # recomputed every run so the recommended groups follow new releases.
  module CatalogSync
    API_URL = "https://models.dev/api.json".freeze
    # models.dev provider key => our AiConfig#provider value.
    PROVIDER_MAP = { "anthropic" => "anthropic", "openrouter" => "openrouter" }.freeze

    # Vendors whose newest models earn a slot in the "recommended" OpenRouter
    # group. Deliberately a vendor list, not a model list — vendors are stable,
    # model ids are exactly what goes stale.
    FEATURED_VENDORS = %w[anthropic openai google moonshotai minimax deepseek qwen z-ai x-ai].freeze
    FEATURED_ANTHROPIC = 5

    module_function

    def run
      payload = fetch
      return { synced: 0, skipped: "models.dev unreachable" } if payload.blank?

      rows = PROVIDER_MAP.flat_map do |source_key, provider|
        build_rows(provider, payload.dig(source_key, "models"))
      end
      return { synced: 0, skipped: "no usable models in payload" } if rows.empty?

      mark_featured(rows)

      CatalogModel.upsert_all(
        rows,
        unique_by: %i[provider model_id],
        update_only: %i[name family description release_date knowledge_cutoff
                        context_limit output_limit cost_input cost_output
                        cost_cache_read cost_cache_write reasoning tool_call
                        attachment open_weights input_modalities featured synced_at]
      )

      # Retired models shouldn't keep haunting the picker — an agent already
      # pointed at one keeps running (ai_config stores the raw id), it just
      # stops being offered.
      pruned = CatalogModel
        .where(provider: rows.map { |r| r[:provider] }.uniq)
        .where.not(model_id: rows.map { |r| r[:model_id] })
        .delete_all

      { synced: rows.size, featured: rows.count { |r| r[:featured] }, pruned: pruned }
    end

    def fetch
      res = Net::HTTP.get_response(URI(API_URL))
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[ModelsDev] #{API_URL} returned #{res.code}")
        return nil
      end
      JSON.parse(res.body)
    rescue => e
      Rails.logger.warn("[ModelsDev] fetch failed: #{e.class}: #{e.message}")
      nil
    end

    def build_rows(provider, models)
      return [] unless models.is_a?(Hash)
      now = Time.current
      models.filter_map do |model_id, m|
        next unless usable?(model_id, m)
        {
          provider: provider,
          model_id: model_id,
          name: clean_name(m["name"], model_id),
          family: m["family"],
          description: m["description"],
          release_date: parse_date(m["release_date"]),
          knowledge_cutoff: m["knowledge"],
          context_limit: m.dig("limit", "context"),
          output_limit: m.dig("limit", "output"),
          cost_input: m.dig("cost", "input"),
          cost_output: m.dig("cost", "output"),
          cost_cache_read: m.dig("cost", "cache_read"),
          cost_cache_write: m.dig("cost", "cache_write"),
          reasoning: m["reasoning"] == true,
          tool_call: m["tool_call"] == true,
          attachment: m["attachment"] == true,
          open_weights: m["open_weights"] == true,
          input_modalities: Array(m.dig("modalities", "input")),
          featured: false,
          synced_at: now,
          created_at: now,
          updated_at: now
        }
      end
    end

    # An agent brain has to emit text. Image/audio-only endpoints and the
    # provider's synthetic "~vendor/model-latest" aliases aren't selectable
    # brains, and :free tiers are rate-limited into uselessness for agents.
    def usable?(model_id, m)
      return false unless m.is_a?(Hash)
      return false if model_id.start_with?("~") || model_id.end_with?(":free")
      Array(m.dig("modalities", "output")).include?("text")
    end

    # Flips `featured` in place on the rows that should headline the picker.
    # Anthropic gets the last few Claude releases (this is a Claude-first
    # product); every other vendor gets exactly its newest model, so the
    # recommended group stays a short "what's current" list. Everything else
    # is one search away.
    def mark_featured(rows)
      by_provider = rows.group_by { |r| r[:provider] }

      headliners(Array(by_provider["anthropic"]))
        .first(FEATURED_ANTHROPIC)
        .each { |r| r[:featured] = true }

      headliners(Array(by_provider["openrouter"]))
        .select { |r| FEATURED_VENDORS.include?(vendor_of(r[:model_id])) }
        .group_by { |r| vendor_of(r[:model_id]) }
        .each_value { |vendor_rows| vendor_rows.first[:featured] = true }
    end

    # Featurable rows, newest first: tool-callers only (an agent that can't
    # call tools is inert), no image generators, and no date-pinned duplicates
    # — models.dev carries both "claude-opus-4-5" and the pinned
    # "claude-opus-4-5-20251101", and the rolling alias is the one to offer.
    def headliners(rows)
      rows
        .select { |r| r[:tool_call] }
        .reject { |r| r[:model_id].match?(/-\d{8}\z/) }
        .reject { |r| image_generator?(r) }
        .sort_by { |r| [ r[:release_date] || Date.new(1970), r[:model_id] ] }
        .reverse
    end

    def image_generator?(row)
      row[:name].to_s.match?(/image/i) || row[:model_id].match?(/image/i)
    end

    def newest(rows)
      rows.max_by { |r| [ r[:release_date] || Date.new(1970), r[:model_id] ] }
    end

    def vendor_of(model_id)
      model_id.split("/").first.to_s
    end

    # "Claude Opus 4.5 (latest)" reads as noise next to the pinned variant we
    # don't offer — the rolling id is the only one in the picker anyway.
    def clean_name(name, model_id)
      base = name.to_s.sub(/\s*\(latest\)\s*\z/i, "").strip
      base.presence || model_id
    end

    # models.dev dates are usually "2026-02-17" but sometimes just "2026-01".
    def parse_date(raw)
      return nil if raw.blank?
      str = raw.to_s
      str = "#{str}-01" if str.match?(/\A\d{4}-\d{2}\z/)
      str = "#{str}-01-01" if str.match?(/\A\d{4}\z/)
      Date.parse(str)
    rescue Date::Error
      nil
    end
  end
end
