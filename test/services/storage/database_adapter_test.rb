require "test_helper"

class DatabaseAdapterTest < ActiveSupport::TestCase
  KEY = Digest::SHA256.hexdigest("db blob")

  setup { @adapter = Storage::DatabaseAdapter.new }

  test "stores bytes in the blob_contents table, not the blobs table" do
    data = "\x00\x01\x02\xFF".b
    @adapter.store(KEY, data)

    assert_equal data, @adapter.retrieve(KEY)
    assert_equal 1, BlobContent.where(key: KEY).count
    assert_equal 0, Blob.count
  end

  test "raises NotFound for missing keys" do
    assert_raises(Storage::NotFound) { @adapter.retrieve(KEY) }
  end

  test "duplicate keys raise Storage::Error" do
    @adapter.store(KEY, "a")
    assert_raises(Storage::Error) { @adapter.store(KEY, "b") }
  end
end
