namespace :email do
  desc "Migrate SES inbound receipt rules from the 150 KB SNS action to the S3 action (DRY_RUN=1 to preview)"
  task migrate_inbound_to_s3: :environment do
    dry_run = ENV["DRY_RUN"].present?
    puts "== SES inbound → S3 migration#{' (DRY RUN)' if dry_run} =="

    migrated = skipped = failed = 0

    ActsAsTenant.without_tenant do
      configs = ChannelConfig.where(channel_type: "email").select { |c| c.config["address"].present? }
      puts "#{configs.size} email channel(s) to check\n\n"

      configs.group_by { |c| c.agent.organization }.each do |org, org_configs|
        topic_arn = org.email_sns_topic_arn.presence
        if topic_arn.blank?
          puts "SKIP org=#{org.slug}: no email_sns_topic_arn — connect the channel in the UI first"
          skipped += org_configs.size
          next
        end

        begin
          bucket = dry_run ? Email::InboundBucket.name_for(org) : Email::InboundBucket.ensure!(org)
        rescue => e
          puts "FAIL org=#{org.slug}: bucket setup — #{e.class}: #{e.message}"
          failed += org_configs.size
          next
        end

        ses = SesClient.for(org)
        Email::ReceiptRule.ensure_rule_set!(ses) unless dry_run

        org_configs.each do |config|
          address = config.config["address"]
          rule = Email::ReceiptRule.build(address: address, bucket: bucket, topic_arn: topic_arn)

          if dry_run
            puts "WOULD UPSERT #{address} → s3://#{bucket}/#{Email::InboundBucket::KEY_PREFIX}"
            migrated += 1
            next
          end

          begin
            result = Email::ReceiptRule.upsert(ses, rule)
            puts "#{result.to_s.upcase} #{address} → s3://#{bucket}/#{Email::InboundBucket::KEY_PREFIX}"
            migrated += 1
          rescue => e
            puts "FAIL #{address}: #{e.class}: #{e.message}"
            failed += 1
          end
        end
      end
    end

    puts "\n#{migrated} migrated, #{skipped} skipped, #{failed} failed"
    abort "migration had failures" if failed.positive?
  end
end
