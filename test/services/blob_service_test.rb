require "test_helper"

class BlobServiceTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("simple-drive-service")
    @adapter = Storage::LocalAdapter.new(root: @dir)
    @service = BlobService.new(adapter: @adapter, backend_name: "local")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "stores metadata in the blobs table and bytes in the backend" do
    result = @service.create(identifier: "docs/readme.txt", encoded_data: Base64.strict_encode64("hello"))

    blob = result.blob
    assert_equal "docs/readme.txt", blob.identifier
    assert_equal 5, blob.size
    assert_equal "local", blob.backend
    assert_equal "hello", @adapter.retrieve(blob.storage_key)
  end

  test "fetch returns the stored bytes" do
    @service.create(identifier: "a", encoded_data: Base64.strict_encode64("bytes"))
    assert_equal "bytes", @service.fetch("a").data
  end

  test "rejects invalid base64" do
    ["not base64!", "SGVsbG8", "SGVs\nbG8=", 123, nil].each do |bad|
      assert_raises(BlobService::InvalidRequest, "expected #{bad.inspect} to be rejected") do
        @service.create(identifier: "x", encoded_data: bad)
      end
    end
    assert_equal 0, Blob.count
  end

  test "rejects missing or non-string ids" do
    [nil, "", "   ", 42, "a" * 1025].each do |bad|
      assert_raises(BlobService::InvalidRequest) { @service.create(identifier: bad, encoded_data: "") }
    end
  end

  test "rejects duplicate ids" do
    @service.create(identifier: "dup", encoded_data: Base64.strict_encode64("1"))
    assert_raises(BlobService::AlreadyExists) do
      @service.create(identifier: "dup", encoded_data: Base64.strict_encode64("2"))
    end
    assert_equal "1", @service.fetch("dup").data
  end

  test "rolls back metadata when the backend write fails" do
    failing = Storage::LocalAdapter.new(root: @dir)
    def failing.store(*) = raise(Storage::Error, "disk full")

    service = BlobService.new(adapter: failing, backend_name: "local")
    assert_raises(Storage::Error) { service.create(identifier: "x", encoded_data: Base64.strict_encode64("1")) }
    assert_equal 0, Blob.count
  end

  test "deletes the stored object when the write succeeds but the request then fails" do
    # e.g. S3 stored the object but the response timed out, or COMMIT failed
    flaky = Storage::LocalAdapter.new(root: @dir)
    def flaky.store(key, data)
      super
      raise Storage::Error, "timeout after write"
    end

    service = BlobService.new(adapter: flaky, backend_name: "local")
    assert_raises(Storage::Error) { service.create(identifier: "orphan?", encoded_data: Base64.strict_encode64("1")) }

    assert_equal 0, Blob.count
    assert_raises(Storage::NotFound) { @adapter.retrieve(Storage.key_for("orphan?")) }
  end

  test "a duplicate upload never deletes the original's data" do
    @service.create(identifier: "keep", encoded_data: Base64.strict_encode64("original"))
    assert_raises(BlobService::AlreadyExists) do
      @service.create(identifier: "keep", encoded_data: Base64.strict_encode64("other"))
    end
    assert_equal "original", @service.fetch("keep").data
  end

  test "enforces the maximum blob size" do
    service = BlobService.new(adapter: @adapter, backend_name: "local", max_size: 10)

    assert service.create(identifier: "fits", encoded_data: Base64.strict_encode64("a" * 10))
    assert_raises(BlobService::TooLarge) do
      service.create(identifier: "too-big", encoded_data: Base64.strict_encode64("a" * 11))
    end
    assert_nil Blob.find_by(identifier: "too-big")
  end

  test "max_encoded_size is the exact Base64 length of the limit" do
    [0, 1, 2, 3, 10, 1000].each do |n|
      assert_equal Base64.strict_encode64("a" * n).bytesize, BlobService.max_encoded_size(n)
    end
  end

  test "detects corrupted data via checksum" do
    blob = @service.create(identifier: "c", encoded_data: Base64.strict_encode64("original")).blob
    @adapter.store(blob.storage_key, "tampered")

    assert_raises(Storage::IntegrityError) { @service.fetch("c") }
  end

  test "raises NotFound for unknown ids" do
    assert_raises(BlobService::NotFound) { @service.fetch("missing") }
  end

  test "reads old blobs from the backend they were written to" do
    db_service = BlobService.new(adapter: Storage::DatabaseAdapter.new, backend_name: "database")
    db_service.create(identifier: "in-db", encoded_data: Base64.strict_encode64("from db"))

    assert_equal "from db", @service.fetch("in-db").data
  end
end
