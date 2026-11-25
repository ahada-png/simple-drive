require "test_helper"

class S3AdapterTest < ActiveSupport::TestCase
  KEY = Digest::SHA256.hexdigest("some/blob")

  def build_adapter(http: FakeS3.new, force_path_style: true)
    Storage::S3Adapter.new(
      endpoint: "http://localhost:9000", bucket: "drive", region: "us-east-1",
      access_key_id: "minio", secret_access_key: "minio-secret",
      force_path_style: force_path_style, http_client: http,
      clock: -> { Time.utc(2026, 1, 1) }
    )
  end

  test "round-trips binary data with signed PUT and GET requests" do
    http = FakeS3.new
    adapter = build_adapter(http: http)
    data = (0..255).map(&:chr).join.b

    adapter.store(KEY, data)
    assert_equal data, adapter.retrieve(KEY)

    put, get = http.requests
    assert_equal :put, put[:method]
    assert_equal "http://localhost:9000/drive/blobs/#{KEY}", put[:uri]
    assert_match(/\AAWS4-HMAC-SHA256 Credential=minio\/20260101\/us-east-1\/s3\/aws4_request/, put[:headers]["authorization"])
    assert_equal OpenSSL::Digest::SHA256.hexdigest(data), put[:headers]["x-amz-content-sha256"]
    assert_equal :get, get[:method]
  end

  test "uses virtual-hosted style URLs when path style is off" do
    adapter = build_adapter(force_path_style: false)
    assert_equal "http://drive.localhost:9000/blobs/#{KEY}", adapter.object_uri(KEY).to_s
  end

  test "raises NotFound on 404" do
    assert_raises(Storage::NotFound) { build_adapter.retrieve(KEY) }
  end

  test "raises Storage::Error with the S3 error code on failure" do
    error = assert_raises(Storage::Error) { build_adapter(http: FakeS3.new(fail_with: 500)).store(KEY, "x") }
    assert_includes error.message, "InternalError"
  end

  test "wraps network failures" do
    broken = Object.new
    def broken.call(*) = raise(Errno::ECONNREFUSED)

    assert_raises(Storage::Error) { build_adapter(http: broken).store(KEY, "x") }
  end

  test "requires credentials" do
    assert_raises(Storage::ConfigurationError) do
      Storage::S3Adapter.new(endpoint: "http://x", bucket: "b", region: "r", access_key_id: "", secret_access_key: "s")
    end
  end
end
