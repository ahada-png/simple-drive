module Storage
  # Abstract base class: the one interface every backend implements.
  class Adapter
    # Build an adapter from the hash in config/simple_drive.yml.
    def self.from_config(_options)
      new
    end

    # Persist +data+ (a binary String) under +key+.
    def store(key, data)
      raise NotImplementedError, "#{self.class} must implement #store"
    end

    # Return the binary String stored under +key+.
    # Raises Storage::NotFound if nothing is stored there.
    def retrieve(key)
      raise NotImplementedError, "#{self.class} must implement #retrieve"
    end

    # Remove +key+. Removing a missing key is not an error.
    def delete(key)
      raise NotImplementedError, "#{self.class} must implement #delete"
    end

    private

    def require_option!(options, name)
      value = options[name]
      raise ConfigurationError, "#{self.class.name}: missing #{name}" if value.nil? || value.to_s.empty?

      value
    end
  end
end
