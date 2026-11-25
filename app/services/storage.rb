require "digest"

# Single entry point to every storage backend.
#
#   Storage.adapter                 # adapter for the configured backend
#   Storage.adapter_for("s3")       # adapter for a specific backend
#   Storage.key_for("any/client id")# backend-safe key derived from an id
#
# Every adapter implements the same interface (see Storage::Adapter):
#   store(key, bytes) / retrieve(key) -> bytes / delete(key)
module Storage
  class Error < StandardError; end
  class NotFound < Error; end
  class ConfigurationError < Error; end
  class IntegrityError < Error; end

  BACKENDS = {
    "local"    => "Storage::LocalAdapter",
    "database" => "Storage::DatabaseAdapter",
    "s3"       => "Storage::S3Adapter",
    "ftp"      => "Storage::FtpAdapter"
  }.freeze

  class << self
    def backend_name
      settings.fetch(:backend).to_s
    end

    def adapter
      adapter_for(backend_name)
    end

    def adapter_for(name)
      name = name.to_s
      @adapters ||= {}
      @adapters[name] ||= build(name)
    end

    # Client ids may be anything (UUIDs, paths, unicode...). Backends get a
    # fixed-length hex key instead, which is safe as a filename, S3 key, or
    # FTP path and rules out path traversal.
    def key_for(identifier)
      Digest::SHA256.hexdigest(identifier.to_s)
    end

    # Used by tests to swap adapters/settings.
    def reset!
      @adapters = nil
    end

    private

    def build(name)
      class_name = BACKENDS[name] or
        raise ConfigurationError, "Unknown storage backend #{name.inspect}. Use one of: #{BACKENDS.keys.join(', ')}"

      options = settings.fetch(name.to_sym, {}) || {}
      class_name.constantize.from_config(options.to_h.symbolize_keys)
    end

    def settings
      Rails.configuration.x.simple_drive
    end
  end
end
