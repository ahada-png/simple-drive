require "digest"
require "securerandom"

# Opaque bearer token. The raw value is shown once at creation; only its
# SHA-256 digest is persisted, so a leaked database does not leak tokens.
class ApiToken < ApplicationRecord
  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  # Returns [record, raw_token].
  def self.generate!(name:)
    raw = "sd_#{SecureRandom.urlsafe_base64(32)}"
    [create!(name: name, token_digest: digest(raw)), raw]
  end

  # Looking up by digest means the comparison never touches the raw secret,
  # so there is no timing side-channel on the token itself.
  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    token = find_by(token_digest: digest(raw_token))
    token&.touch(:last_used_at)
    token
  end
end
