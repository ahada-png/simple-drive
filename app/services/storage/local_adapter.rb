require "fileutils"
require "pathname"
require "securerandom"

module Storage
  # Stores each blob as a file under a root directory.
  #
  # Layout: <root>/ab/cd/abcdef...  (first two byte pairs of the key as
  # sub-directories, so no single directory grows too large).
  class LocalAdapter < Adapter
    KEY_FORMAT = /\A[0-9a-f]{64}\z/

    attr_reader :root

    def self.from_config(options)
      new(root: options[:root])
    end

    def initialize(root:)
      raise ConfigurationError, "LocalAdapter: missing root" if root.nil? || root.to_s.empty?

      @root = Pathname.new(root.to_s).expand_path
      FileUtils.mkdir_p(@root)
    rescue SystemCallError => e
      raise ConfigurationError, "LocalAdapter: cannot use #{root}: #{e.message}"
    end

    def store(key, data)
      path = path_for(key)
      FileUtils.mkdir_p(path.dirname)

      # Write to a temp file then rename: readers never see a half-written file.
      tmp = path.dirname.join(".#{path.basename}.#{SecureRandom.hex(6)}.tmp")
      File.binwrite(tmp, data)
      File.rename(tmp, path)
      true
    rescue SystemCallError => e
      FileUtils.rm_f(tmp) if tmp
      raise Error, "Local storage write failed: #{e.message}"
    end

    def retrieve(key)
      File.binread(path_for(key))
    rescue Errno::ENOENT
      raise NotFound, "No blob stored for key #{key}"
    rescue SystemCallError => e
      raise Error, "Local storage read failed: #{e.message}"
    end

    def delete(key)
      FileUtils.rm_f(path_for(key))
      true
    end

    private

    def path_for(key)
      raise ArgumentError, "invalid storage key #{key.inspect}" unless KEY_FORMAT.match?(key.to_s)

      root.join(key[0, 2], key[2, 2], key)
    end
  end
end
