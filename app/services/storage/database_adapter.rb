module Storage
  # Stores bytes in the dedicated `blob_contents` table (not the `blobs`
  # metadata table).
  class DatabaseAdapter < Adapter
    def self.from_config(_options)
      new
    end

    def initialize(model: BlobContent)
      @model = model
    end

    def store(key, data)
      @model.create!(key: key, data: data.b)
      true
    rescue ActiveRecord::ActiveRecordError => e
      raise Error, "Database storage write failed: #{e.message}"
    end

    def retrieve(key)
      record = @model.find_by(key: key)
      raise NotFound, "No blob stored for key #{key}" unless record

      record.data.to_s.b
    end

    def delete(key)
      @model.where(key: key).delete_all
      true
    end
  end
end
