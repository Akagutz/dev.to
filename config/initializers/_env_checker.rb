# This file is named in such a manner so that it run first.

keys = [
  "AIRBRAKE_API_KEY",
  "AIRBRAKE_PROJECT_ID",
  "ALGOLIASEARCH_API_KEY",
  "ALGOLIASEARCH_APPLICATION_ID",
  "ALGOLIASEARCH_SEARCH_ONLY_KEY",
  "APP_DOMAIN",
  "APP_PROTOCOL",
  "AWS_DEFAULT_REGION",
  "AWS_SDK_KEY",
  "AWS_SDK_SECRET",
  "BUFFER_ACCESS_TOKEN",
  "BUFFER_FACEBOOK_ID",
  "BUFFER_LINKEDIN_ID",
  "BUFFER_PROFILE_ID",
  "BUFFER_TWITTER_ID",
  "CLOUDINARY_CLOUD_NAME",
  "CLOUDINARY_API_KEY",
  "CLOUDINARY_API_SECRET",
  "CLOUDINARY_SECURE",
  "DACAST_STREAM_CODE",
  "DEPLOYMENT_SIGNATURE",
  "DEV_EMAIL_PASSWORD",
  "DEV_EMAIL_USERNAME",
  "DEVTO_USER_ID",
  "FACEBOOK_PIXEL_ID",
  "GA_SERVICE_ACCOUNT_JSON",
  "GA_TRACKING_ID",
  "GA_VIEW_ID",
  "GITHUB_KEY",
  "GITHUB_SECRET",
  "GITHUB_TOKEN",
  "INFINITE_LOOP_URL",
  "JWPLAYER_API_KEY",
  "JWPLAYER_API_SECRET",
  "KEEN_API_URL",
  "KEEN_PROJECT_ID",
  "KEEN_READ_KEY",
  "KEEN_WRITE_KEY",
  "MAILCHIMP_API_KEY",
  "MAILCHIMP_NEWSLETTER_ID",
  "RECAPTCHA_SECRET",
  "RECAPTCHA_SITE",
  "SERVICE_TIMEOUT",
  "SHARE_MEOW_BASE_URL",
  "SHARE_MEOW_SECRET_KEY",
  "SHOP_SECRET", # Should be a number
  "SLACK_CHANNEL",
  "SLACK_WEBHOOK_URL",
  "SMARTY_STREETS_AUTH_ID",
  "SMARTY_STREETS_AUTH_TOKEN",
  "SMARTY_STREETS_WEB_KEY",
  "SMOOCH_WEB_MESSENGER_APP_TOKEN",
  "STREAM_RAILS_KEY",
  "STREAM_RAILS_SECRET",
  "STREAM_URL",
  "STRIPE_PUBLISHABLE_KEY",
  "STRIPE_SECRET_KEY",
  "SENDBIRD_APP_ID",
  "SENDBIRD_LIVECHAT_URL",
  "TWITTER_ACCESS_TOKEN",
  "TWITTER_ACCESS_TOKEN_SECRET",
  "TWITTER_CARD_VALIDATOR_PASSWORD",
  "TWITTER_CARD_VALIDATOR_USERNAME",
  "TWITTER_KEY",
  "TWITTER_SECRET",
].freeze

missing = []

keys.each do |k|
  missing << k if ENV[k].nil?
end

# Run the checker when
# 1. Not in production
# 2. Not in CI
# 3. There are missing keys
if Rails.env != "production" && !ENV["CI"] && !missing.empty? && Rails.env != "test"
  message = <<~HEREDOC
    \n
    =====================================================
    Hey there DEVeloper!
    You are missing the [#{missing.length}] environment variable(s).
    Please obtain these missing key(s) and try again.
    -----------------------------------------------------
    #{missing.join("\n")}
    =====================================================
    \n
  HEREDOC
  raise message
end
