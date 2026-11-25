# Row in the table used by the "database" storage backend.
class BlobContent < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :data, exclusion: { in: [nil] }
end
