class CreateCatalogModels < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_models do |t|
      # Our provider key ("anthropic" / "openrouter") — NOT models.dev's, which
      # we map on the way in so ai_config.provider values stay valid.
      t.string :provider, null: false
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :family
      t.text :description
      t.date :release_date
      t.string :knowledge_cutoff

      t.integer :context_limit
      t.integer :output_limit

      # USD per million tokens, as models.dev publishes them.
      t.decimal :cost_input, precision: 12, scale: 6
      t.decimal :cost_output, precision: 12, scale: 6
      t.decimal :cost_cache_read, precision: 12, scale: 6
      t.decimal :cost_cache_write, precision: 12, scale: 6

      t.boolean :reasoning, null: false, default: false
      t.boolean :tool_call, null: false, default: false
      t.boolean :attachment, null: false, default: false
      t.boolean :open_weights, null: false, default: false
      t.jsonb :input_modalities, null: false, default: []

      # Sync-owned: the handful surfaced as picker groups. Everything else is
      # still selectable through search.
      t.boolean :featured, null: false, default: false
      # Admin-owned, preserved across syncs.
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0

      t.datetime :synced_at
      t.timestamps
    end

    add_index :catalog_models, [ :provider, :model_id ], unique: true
    add_index :catalog_models, :featured
    add_index :catalog_models, :release_date
  end
end
