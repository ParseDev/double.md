# Refreshes catalog_models from models.dev. Scheduled daily — providers ship
# new models constantly and the picker should carry them without a deploy.
# Also safe to run on demand: `ModelCatalogSyncJob.perform_now`.
class ModelCatalogSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = ModelsDev::CatalogSync.run
    Rails.logger.info "ModelCatalogSyncJob: #{result.inspect}"
  rescue => e
    Rails.logger.warn "ModelCatalogSyncJob failed: #{e.class}: #{e.message}"
  end
end
