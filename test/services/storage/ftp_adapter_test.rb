require "test_helper"

class FtpAdapterTest < ActiveSupport::TestCase
  KEY = Digest::SHA256.hexdigest("ftp blob")

  setup do
    @ftp = FakeFtp.new
    @adapter = Storage::FtpAdapter.new(host: "ftp.example.test", username: "u", password: "p",
                                       directory: "/simple-drive/blobs", connection_factory: @ftp.factory)
  end

  test "creates the storage directory and round-trips binary data" do
    data = (0..255).map(&:chr).join.b * 50
    @adapter.store(KEY, data)

    assert_includes @ftp.dirs, "/simple-drive/blobs"
    assert_equal data, @ftp.files["/simple-drive/blobs/#{KEY}"]
    assert_equal data, @adapter.retrieve(KEY)
    assert_equal Encoding::BINARY, @adapter.retrieve(KEY).encoding
  end

  test "closes the connection after every operation" do
    @adapter.store(KEY, "x")
    @adapter.retrieve(KEY)
    assert_equal 2, @ftp.closed_count
  end

  test "maps 550 to NotFound" do
    assert_raises(Storage::NotFound) { @adapter.retrieve(KEY) }
  end

  test "wraps connection failures" do
    adapter = Storage::FtpAdapter.new(host: "x", username: "u", connection_factory: -> { raise Errno::ECONNREFUSED })
    assert_raises(Storage::Error) { adapter.store(KEY, "x") }
  end
end
