require "test_helper"

class LocalAdapterTest < ActiveSupport::TestCase
  KEY = Digest::SHA256.hexdigest("hello")

  setup do
    @dir = Dir.mktmpdir("simple-drive-local")
    @adapter = Storage::LocalAdapter.new(root: @dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "stores and retrieves binary data in a sharded layout" do
    data = "\x00\xFFbinary\n".b
    @adapter.store(KEY, data)

    assert_equal data, @adapter.retrieve(KEY)
    assert File.exist?(File.join(@dir, KEY[0, 2], KEY[2, 2], KEY))
  end

  test "leaves no temp files behind" do
    @adapter.store(KEY, "x")
    assert_equal [KEY], Dir.glob(File.join(@dir, "**", "*"), File::FNM_DOTMATCH).map { |f| File.basename(f) }.grep(/\A[^.]/).select { |f| f.size == 64 }
    assert_empty Dir.glob(File.join(@dir, "**", "*.tmp"), File::FNM_DOTMATCH)
  end

  test "raises NotFound for missing keys" do
    assert_raises(Storage::NotFound) { @adapter.retrieve(KEY) }
  end

  test "rejects keys that could escape the root" do
    assert_raises(ArgumentError) { @adapter.store("../../etc/passwd", "x") }
  end

  test "delete removes the file and is idempotent" do
    @adapter.store(KEY, "x")
    @adapter.delete(KEY)
    @adapter.delete(KEY)
    assert_raises(Storage::NotFound) { @adapter.retrieve(KEY) }
  end
end
