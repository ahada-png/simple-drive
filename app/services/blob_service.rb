require "base64"
require "digest"

# Application logic for storing and fetching blobs. Knows nothing about HTTP
# and nothing about which backend is in use. It only talks to Storage::Adapter.
class BlobService
  class InvalidRequest < StandardError; end
  class TooLarge < StandardError; end
  class AlreadyExists < StandardError; end
  class NotFound < StandardError; end

  Result = Struct.new(:blob, :data, keyword_init: true)

  def self.max_blob_size
    Rails.configuration.x.simple_drive.fetch(:max_blob_size).to_i
  end

  # Largest Base64 string that can decode to +max_blob_size+ bytes.
  def self.max_encoded_size(max_size = max_blob_size)
    ((max_size + 2) / 3) * 4
  end

  def initialize(adapter: nil, backend_name: nil, max_size: self.class.max_blob_size)
    @backend_name = backend_name || Storage.backend_name
    @adapter = adapter || Storage.adapter_for(@backend_name)
    @max_size = max_size
  end

  # Decodes +encoded_data+ (Base64) and stores it under +identifier+.
  def create(identifier:, encoded_data:)
    validate_identifier!(identifier)
    bytes = decode!(encoded_data)
    key = Storage.key_for(identifier)

    Result.new(blob: persist!(identifier, key, bytes), data: bytes)
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyExists, "A blob with id #{identifier.inspect} already exists"
  rescue ActiveRecord::RecordInvalid => e
    raise AlreadyExists, "A blob with id #{identifier.inspect} already exists" if e.record.errors.of_kind?(:identifier, :taken)

    raise InvalidRequest, e.record.errors.full_messages.to_sentence
  end

  # Returns the blob metadata and its bytes, read from the backend it was
  # originally stored in (so switching STORAGE_BACKEND keeps old blobs readable).
  def fetch(identifier)
    blob = Blob.find_by(identifier: identifier.to_s)
    raise NotFound, "Blob #{identifier.inspect} not found" unless blob

    adapter = blob.backend == @backend_name ? @adapter : Storage.adapter_for(blob.backend)
    bytes = adapter.retrieve(blob.storage_key)

    if Digest::SHA256.hexdigest(bytes) != blob.checksum
      raise Storage::IntegrityError, "Checksum mismatch for blob #{identifier.inspect}"
    end

    Result.new(blob: blob, data: bytes)
  rescue Storage::NotFound
    raise NotFound, "Blob #{identifier.inspect} data is missing from the #{blob&.backend} backend"
  end

  private

  # Consistency between the metadata row and the stored bytes:
  #
  # * database backend: the bytes are written inside the same DB transaction,
  #   so both commit or both roll back. Fully atomic.
  # * external backends (local, S3, FTP): a DB transaction cannot cover them.
  #   The metadata row is inserted first (the unique index claims the id),
  #   then the bytes are written. If anything fails after the write was
  #   attempted (backend error/timeout, or the COMMIT itself), we roll back
  #   and delete the bytes as a compensating action, so no orphan is left.
  #   The only remaining gap is the process dying between the write and the
  #   COMMIT; see "Consistency" in the README.
  def persist!(identifier, key, bytes)
    write_attempted = false
    blob = nil

    Blob.transaction do
      blob = Blob.create!(
        identifier: identifier,
        size: bytes.bytesize,
        checksum: Digest::SHA256.hexdigest(bytes),
        backend: @backend_name,
        storage_key: key
      )
      # Only reached once our row holds the id, so +key+ is ours to clean up.
      write_attempted = true
      @adapter.store(key, bytes)
    end

    blob
  rescue StandardError
    compensate(key) if write_attempted
    raise
  end

  def compensate(key)
    @adapter.delete(key)
  rescue StandardError => e
    Rails.logger.error("[storage] could not remove orphaned object #{key}: #{e.class}: #{e.message}")
  end

  def validate_identifier!(identifier)
    raise InvalidRequest, "id is required and must be a string" unless identifier.is_a?(String) && !identifier.strip.empty?
    raise InvalidRequest, "id must be at most 1024 characters" if identifier.length > 1024
  end

  # strict_decode64 rejects anything that is not valid, padded Base64
  # (stray characters, wrong padding, embedded newlines). The size is checked
  # before decoding so an oversized payload is never decoded into memory.
  def decode!(encoded)
    raise InvalidRequest, "data is required and must be a Base64 string" unless encoded.is_a?(String)
    raise TooLarge, too_large_message if encoded.bytesize > self.class.max_encoded_size(@max_size)

    bytes = Base64.strict_decode64(encoded)
    raise TooLarge, too_large_message if bytes.bytesize > @max_size

    bytes
  rescue ArgumentError
    raise InvalidRequest, "data is not valid Base64"
  end

  def too_large_message
    "data exceeds the maximum blob size of #{@max_size} bytes"
  end
end
