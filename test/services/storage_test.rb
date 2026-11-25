require "test_helper"

class StorageTest < ActiveSupport::TestCase
  test "builds the configured adapter" do
    assert_instance_of Storage::LocalAdapter, Storage.adapter
  end

  test "builds every backend from config" do
    assert_instance_of Storage::DatabaseAdapter, Storage.adapter_for("database")

    s3 = Storage::S3Adapter.from_config(endpoint: "http://localhost:9000", bucket: "b", region: "us-east-1",
                                        access_key_id: "k", secret_access_key: "s")
    assert_instance_of Storage::S3Adapter, s3

    ftp = Storage::FtpAdapter.from_config(host: "localhost", port: "2121", username: "u", password: "p")
    assert_instance_of Storage::FtpAdapter, ftp
  end

  test "rejects unknown backends" do
    assert_raises(Storage::ConfigurationError) { Storage.adapter_for("dropbox") }
  end

  test "key_for is deterministic, fixed-length hex" do
    key = Storage.key_for("../../etc/passwd")
    assert_match(/\A[0-9a-f]{64}\z/, key)
    assert_equal key, Storage.key_for("../../etc/passwd")
  end
end
