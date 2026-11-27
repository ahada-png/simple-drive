require "test_helper"

# Talks to a real S3-compatible server (moto in CI, see .github/workflows/ci.yml).
# Skipped unless S3_LIVE_TEST=1, so the default suite needs no network.
#
#   docker compose up -d s3
#   S3_LIVE_TEST=1 bin/rails test test/integration/s3_live_test.rb
class S3LiveTest < ActiveSupport::TestCase
  setup do
    skip "set S3_LIVE_TEST=1 to run against a real S3 server" unless ENV["S3_LIVE_TEST"] == "1"

    @config = {
      endpoint: ENV.fetch("S3_ENDPOINT", "http://localhost:5000"),
      bucket: "simple-drive-test-#{SecureRandom.hex(4)}",
      region: ENV.fetch("S3_REGION", "us-east-1"),
      access_key_id: ENV.fetch("S3_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("S3_SECRET_ACCESS_KEY", "test")
    }
    create_bucket!
    @adapter = Storage::S3Adapter.new(**@config)
  end

  test "round-trips binary data through a real S3 server" do
    key = Storage.key_for("live/test")
    data = SecureRandom.random_bytes(256 * 1024)

    @adapter.store(key, data)
    assert_equal data, @adapter.retrieve(key)

    @adapter.delete(key)
    assert_raises(Storage::NotFound) { @adapter.retrieve(key) }
  end

  test "a wrong secret is rejected by the server" do
    bad = Storage::S3Adapter.new(**@config.merge(secret_access_key: "wrong"))
    error = assert_raises(Storage::Error) { bad.store(Storage.key_for("x"), "x") }
    assert_includes error.message, "SignatureDoesNotMatch"
  end

  private

  # CreateBucket: a signed PUT on /<bucket>.
  def create_bucket!
    signer = Storage::S3::Signer.new(**@config.slice(:access_key_id, :secret_access_key, :region))
    uri = URI("#{@config[:endpoint]}/#{@config[:bucket]}")
    response = Storage::S3::HttpClient.new.call(:put, uri, signer.sign(method: "PUT", uri: uri, body: ""), "")
    flunk "could not create bucket: HTTP #{response.status} #{response.body}" unless response.status == 200
  end
end
