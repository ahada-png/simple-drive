# Tracks a stored blob. Holds metadata only; the bytes are in the backend.
class Blob < ApplicationRecord
  validates :identifier, presence: true, uniqueness: true, length: { maximum: 1024 }
  validates :size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :checksum, :backend, :storage_key, presence: true
end
