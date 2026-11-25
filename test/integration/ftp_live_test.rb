require "test_helper"

# Talks to a real FTP server. Skipped unless FTP_LIVE_TEST=1.
#
#   docker compose up -d ftp
#   FTP_LIVE_TEST=1 FTP_HOST=localhost FTP_USERNAME=drive FTP_PASSWORD=drivepass \
#     bin/rails test test/integration/ftp_live_test.rb
class FtpLiveTest < ActiveSupport::TestCase
  setup do
    skip "set FTP_LIVE_TEST=1 to run against a real FTP server" unless ENV["FTP_LIVE_TEST"] == "1"

    @adapter = Storage::FtpAdapter.new(
      host: ENV.fetch("FTP_HOST", "localhost"),
      port: ENV.fetch("FTP_PORT", "21").to_i,
      username: ENV.fetch("FTP_USERNAME", "drive"),
      password: ENV.fetch("FTP_PASSWORD", "drivepass"),
      directory: "/simple-drive-test/#{SecureRandom.hex(4)}",
      passive: ENV.fetch("FTP_PASSIVE", "true") == "true"
    )
  end

  test "round-trips binary data through a real FTP server" do
    key = Storage.key_for("live/ftp")
    data = SecureRandom.random_bytes(256 * 1024)

    @adapter.store(key, data)
    assert_equal data, @adapter.retrieve(key)

    @adapter.delete(key)
    assert_raises(Storage::NotFound) { @adapter.retrieve(key) }
  end

  test "missing files raise NotFound" do
    assert_raises(Storage::NotFound) { @adapter.retrieve(Storage.key_for("never stored")) }
  end

  test "bad credentials raise Storage::Error" do
    bad = Storage::FtpAdapter.new(host: ENV.fetch("FTP_HOST", "localhost"), port: ENV.fetch("FTP_PORT", "21").to_i,
                                  username: "nobody", password: "wrong")
    assert_raises(Storage::Error) { bad.store(Storage.key_for("x"), "x") }
  end

  test "works end to end through the API" do
    Storage.instance_variable_set(:@adapters, { "ftp" => @adapter })
    service = BlobService.new(backend_name: "ftp")

    service.create(identifier: "ftp/e2e", encoded_data: Base64.strict_encode64("over ftp"))
    assert_equal "over ftp", service.fetch("ftp/e2e").data
  end
end
