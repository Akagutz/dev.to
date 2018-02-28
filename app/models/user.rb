include CloudinaryHelper

class User < ApplicationRecord
  attr_accessor :scholar_email
  rolify
  include AlgoliaSearch
  include Storext.model

  acts_as_followable
  acts_as_follower

  has_many    :articles
  has_many    :reactions
  belongs_to  :organization, optional: true
  has_many    :comments
  has_many    :identities
  has_many    :collections
  has_many    :tweets
  has_many    :notifications
  has_many    :mentions
  has_many    :email_messages, class_name: "Ahoy::Message"
  has_many    :notes
  has_many    :github_repos

  mount_uploader :profile_image, ProfileImageUploader

  devise :omniauthable, :trackable, :rememberable,
        :registerable, :database_authenticatable, :confirmable
  validates :email,
            uniqueness: { allow_blank: true, case_sensitive: false },
            length: { maximum: 50 },
            email: true,
            allow_blank: true
  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[a-zA-Z0-9_]+\Z/ },
            length: { in: 2..30 },
            exclusion: { in: RESERVED_WORDS,
                         message: "%{value} is reserved." }
  validates :twitter_username, uniqueness: { allow_blank: true }
  validates :github_username, uniqueness: { allow_blank: true }
  validates :text_color_hex, format: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, allow_blank: true
  validates :bg_color_hex, format: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, allow_blank: true
  validates :website_url, url: { allow_blank: true, no_local: true, schemes: ["https", "http"] }
  validates :employer_url, url: { allow_blank: true, no_local: true, schemes: ["https", "http"] }
  validates :shirt_gender,
              inclusion: { in: %w(unisex womens),
              message: "%{value} is not a valid shirt style" },
              allow_blank: true
  validates :shirt_size,
              inclusion: { in: %w(xs s m l xl 2xl 3xl 4xl),
              message: "%{value} is not a valid size" },
              allow_blank: true
  validates :tabs_or_spaces,
              inclusion: { in: %w(tabs spaces),
              message: "%{value} is not a valid answer" },
              allow_blank: true
  validates :shipping_country,
              length: { in: 2..2 },
              allow_blank: true
  validates :website_url, url: { allow_blank: true, no_local: true, schemes: ["https", "http"] }
  validates :website_url, :employer_name, :employer_url,
            :employment_title, :top_languages, :education, :location,
            length: { maximum: 64 }
  validates :mostly_work_with, :currently_learning, :currently_hacking_on, :available_for,
            length: { maximum: 500 }
  validate  :conditionally_validate_summary
  validate  :validate_feed_url
  validate  :unique_including_orgs

  after_create :send_welcome_notification
  after_save  :bust_cache
  after_save  :subscribe_to_mailchimp_newsletter
  after_create :estimate_default_language!
  before_validation :set_username
  before_validation :downcase_email
  before_validation :check_for_username_change

  algoliasearch per_environment: true, enqueue: :trigger_delayed_index do
    add_index "searchables",
                  id: :index_id,
                  per_environment: true,
                  enqueue: :trigger_delayed_index do
      attribute :user do
        { username: user.username,
          name: user.username,
          profile_image_90: ProfileImage.new(user).get(90) }
      end
      attribute :title, :path, :tag_list, :main_image, :id,
        :featured, :published, :published_at, :featured_number, :comments_count,
        :reactions_count, :positive_reactions_count, :class_name, :user_name,
        :user_username, :comments_blob, :body_text, :tag_keywords_for_search,
        :search_score, :hotness_score
      searchableAttributes ["unordered(title)",
                            "body_text",
                            "tag_list",
                            "tag_keywords_for_search",
                            "user_name",
                            "user_username",
                            "comments_blob"]
      attributesForFaceting [:class_name]
      customRanking ["desc(search_score)", "desc(hotness_score)"]
    end
  end

  # Via https://github.com/G5/storext
  store_attributes :language_settings do
    estimated_default_language String
    prefer_language_en Boolean, default: true
    prefer_language_ja Boolean, default: false
    prefer_language_es Boolean, default: false
    prefer_language_fr Boolean, default: false
    prefer_language_it Boolean, default: false
  end

  def self.trigger_delayed_index(record, remove)
    if remove
      record.delay.remove_from_index! if (record && record.persisted?)
    else
      record.delay.index!
    end
  end

  def index_id
    "users-#{id}"
  end

  def estimate_default_language!
    identity = identities.where(provider: "twitter").first
    if email.end_with?(".jp")
      self.update(:estimated_default_language => "ja", :prefer_language_ja => true)
    elsif identity
      lang = identity.auth_data_dump["extra"]["raw_info"]["lang"]
      self.update(:estimated_default_language => lang, "prefer_language_#{lang}" => true)
    end
  end
  handle_asynchronously :estimate_default_language!

  def calculate_score
    score = (articles.where(featured:true).size*100) + (comments.sum(:score))
    self.update_column(:score, score)
  end

  def path
    "/"+username.to_s
  end

  def followed_articles
    Article.tagged_with(cached_followed_tag_names, any: true).union(
      Article.where(
        user_id: cached_following_users_ids,
      )
    ).where(language: cached_preferred_langs, published: true)
  end

  def cached_following_users_ids
    Rails.cache.fetch("user-#{id}-#{updated_at}-#{following_users_count}/following_users_ids", expires_in: 120.hours) do
      # More efficient query. May not cover future edge cases.
      # Should probably only return users who have published lately
      # But this should be okay for most for now.
      Follow.where(follower_id: id, followable_type: "User").limit(150).pluck(:followable_id)
    end
  end

  def cached_preferred_langs
    Rails.cache.fetch("user-#{id}-#{updated_at}/cached_preferred_langs", expires_in: 80.hours) do
      langs = []
      langs << "en" if prefer_language_en
      langs << "ja" if prefer_language_ja
      langs << "es" if prefer_language_es
      langs << "fr" if prefer_language_fr
      langs << "it" if prefer_language_it
      langs
    end
  end

  def processed_website_url
    if website_url.present?
      website_url.to_s.strip
    end
  end

  def remember_me
    true
  end

  def cached_followed_tag_names
    Rails.cache.fetch("user-#{id}-#{updated_at}/followed_tag_names", expires_in: 100.hours) do
      Tag.where(id:Follow.where(follower_id:id,followable_type:"ActsAsTaggableOn::Tag").pluck(:followable_id)).pluck(:name)
    end
  end

  # methods for Administrate field
  def banned
    has_role? :banned
  end

  def warned
    has_role? :warned
  end

  def trusted
    has_role? :trusted
  end

  def reason_for_ban
    return if notes.where(reason: "banned").blank?
    Note.find_by(user_id: id, reason: "banned").content
  end

  def reason_for_warning
    return if notes.where(reason: "warned").blank?
    Note.find_by(user_id: id, reason: "warned").content
  end

  def scholar
    valid_pass = workshop_expiration.nil? || workshop_expiration > Time.now
    has_role?(:workshop_pass) && valid_pass
  end

  def analytics
    has_role? :analytics_beta_tester
  end

  def workshop_eligible?
    has_any_role?(:workshop_pass, :level_3_member, :level_4_member, :triple_unicorn_member)
  end

  def unique_including_orgs
    errors.add(:username, "is taken.") if Organization.find_by_slug(username)
  end

  def subscribe_to_mailchimp_newsletter
    return unless email.present? && email.include?("@")

    if saved_changes["unconfirmed_email"] && saved_changes["confirmation_sent_at"]
      # This is when user is updating their email. There
      # is no need to update mailchimp until email is confirmed.
      return
    else
      MailchimpBot.new(self).upsert
    end
  end
  handle_asynchronously :subscribe_to_mailchimp_newsletter

  def can_view_analytics?
    has_any_role?(:super_admin, :admin, :analytics_beta_tester)
  end

  def a_sustaining_member?
    monthly_dues.positive?
  end

  private

  def send_welcome_notification
    Broadcast.send_welcome_notification(id)
  end

  def set_username
    if username.blank?
      set_temp_username
    end
    self.username = username&.downcase
  end

  def set_temp_username
    self.username = if temp_name_exists?
      temp_username + "_" + rand(100).to_s
    else
      temp_username
    end
  end

  def temp_name_exists?
    User.find_by_username(temp_username) || Organization.find_by_slug(temp_username)
  end

  def temp_username
    if twitter_username
      twitter_username.downcase.gsub(/[^0-9a-z_]/i, "").gsub(/ /, "")
    elsif  github_username
      github_username.downcase.gsub(/[^0-9a-z_]/i, "").gsub(/ /, "")
    end
  end

  def downcase_email
    self.email = email.downcase if email
  end

  def check_for_username_change
    if username_changed?
      self.old_old_username = old_username
      self.old_username = username_was
    end
  end

  def conditionally_resave_articles
    if core_profile_details_changed?
      delay.resave_articles
    end
  end

  def bust_cache
    CacheBuster.new.bust("/#{username}")
    CacheBuster.new.bust("/feed/#{username}")
  end
  handle_asynchronously :bust_cache

  def core_profile_details_changed?
    saved_change_to_username? ||
      saved_change_to_name? ||
      saved_change_to_profile_image? ||
      saved_change_to_github_username? ||
      saved_change_to_twitter_username?
  end

  def resave_articles
    articles.each do |article|
      CacheBuster.new.bust(article.path)
      CacheBuster.new.bust(article.path + "?i=i")
      article.save
    end
  end

  def conditionally_validate_summary
    # Grandfather people who had a too long summary before.
    return if summary_was && summary_was.size > 200
    if summary.present? && summary.size > 200
      errors.add(:summary, "is too long.")
    end
  end

  def validate_feed_url
    return unless feed_url.present?
    errors.add(:feed_url, "is not a valid rss feed") unless RssReader.new.valid_feed_url?(feed_url)
  end

  def title
    name
  end

  def tag_list
    cached_followed_tag_names
  end

  def main_image; end

  def featured
    true
  end

  def published
    true
  end

  def published_at; end

  def featured_number; end

  def positive_reactions_count
    reactions_count
  end

  def user
    self
  end

  def class_name
    self.class.name
  end

  def user_name
    username
  end

  def user_username
    username
  end

  def comments_blob
    ActionView::Base.full_sanitizer.sanitize(comments.last(2).pluck(:body_markdown).join(" "))[0..2500]
  end

  def body_text
    summary.to_s + ActionView::Base.full_sanitizer.
      sanitize(articles.last(50).
        pluck(:processed_html).
        join(" "))[0..2500]
  end

  def tag_keywords_for_search
    employer_name.to_s + mostly_work_with.to_s + available_for.to_s
  end

  def hotness_score
    search_score
  end

  def search_score
    score = (((articles_count + comments_count + reactions_count) * 10) + tag_keywords_for_search.size) * reputation_modifier * followers_count
    score.to_i
  end
end
