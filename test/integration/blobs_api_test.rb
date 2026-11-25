require "test_helper"

class BlobsApiTest < ActionDispatch::IntegrationTest
  include AuthHelpers

  HELLO = "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh".freeze # "Hello Simple Storage World!"

  setup do
    _token, @raw_token = ApiToken.generate!(name: "test")
  end

  def post_blob(body, headers: auth_headers)
    post "/v1/blobs", params: body.is_a?(String) ? body : body.to_json, headers: headers
  end

  test "stores and retrieves a blob (example from the spec)" do
    post_blob({ id: "any_valid_string_or_identifier", data: HELLO })
    assert_response :created

    get "/v1/blobs/any_valid_string_or_identifier", headers: auth_headers
    assert_response :ok

    body = response.parsed_body
    assert_equal %w[id data size created_at], body.keys
    assert_equal "any_valid_string_or_identifier", body["id"]
    assert_equal HELLO, body["data"]
    assert_equal "27", body["size"]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body["created_at"])
  end

  test "ids can be paths and UUIDs" do
    ["photos/2026/cat.png", "550e8400-e29b-41d4-a716-446655440000"].each do |id|
      post_blob({ id: id, data: HELLO })
      assert_response :created

      get "/v1/blobs/#{id}", headers: auth_headers
      assert_response :ok
      assert_equal id, response.parsed_body["id"]
    end
  end

  # Encodes each path segment, as an HTTP client would.
  def blob_path(id)
    "/v1/blobs/" + id.split("/", -1).map { |segment| ERB::Util.url_encode(segment) }.join("/")
  end

  test "ids with Arabic, spaces and URL-special characters round-trip" do
    ids = [
      "تقرير المشروع.pdf",
      "file with spaces.txt",
      "hash#tag",
      "query?a=1&b=2",
      "100%real",
      "plus+sign",
      "مجلد/ملف #1?.txt",
      "emoji-📦"
    ]

    ids.each do |id|
      post_blob({ id: id, data: HELLO })
      assert_response :created, "store failed for #{id.inspect}"

      get blob_path(id), headers: auth_headers
      assert_response :ok, "fetch failed for #{id.inspect}"
      assert_equal id, response.parsed_body["id"]
      assert_equal HELLO, response.parsed_body["data"]
    end
  end

  test "only the Bearer scheme is accepted" do
    post_blob({ id: "scheme", data: HELLO })
    assert_response :created

    get "/v1/blobs/scheme", headers: { "Authorization" => "bearer #{@raw_token}" }
    assert_response :ok # scheme name is case-insensitive (RFC 7235)

    ["Token token=#{@raw_token}", "Basic #{@raw_token}", @raw_token, "Bearer", "Bearer #{@raw_token} extra"].each do |value|
      get "/v1/blobs/scheme", headers: { "Authorization" => value }
      assert_response :unauthorized, "expected #{value.inspect} to be rejected"
    end
  end

  test "there are no unauthenticated routes" do
    get "/up"
    assert_response :not_found
  end

  test "rejects blobs larger than the limit with 413" do
    previous = Rails.configuration.x.simple_drive[:max_blob_size]
    Rails.configuration.x.simple_drive[:max_blob_size] = 16

    post_blob({ id: "ok", data: Base64.strict_encode64("a" * 16) })
    assert_response :created

    post_blob({ id: "big", data: Base64.strict_encode64("a" * 17) })
    assert_response 413
    assert_nil Blob.find_by(identifier: "big")

    # Content-Length far over the limit is refused before the JSON is parsed
    post_blob({ id: "huge", data: Base64.strict_encode64("a" * 200_000) })
    assert_response 413
  ensure
    Rails.configuration.x.simple_drive[:max_blob_size] = previous
  end

  test "requires a valid bearer token" do
    post_blob({ id: "x", data: HELLO }, headers: { "Content-Type" => "application/json" })
    assert_response :unauthorized
    assert_equal 'Bearer realm="Simple Drive"', response.headers["WWW-Authenticate"]

    get "/v1/blobs/x", headers: auth_headers("not-a-real-token")
    assert_response :unauthorized
    assert_equal 0, Blob.count
  end

  test "rejects data that is not valid Base64" do
    post_blob({ id: "bad", data: "this is not base64!!" })
    assert_response 422
    assert_equal "data is not valid Base64", response.parsed_body["error"]
    assert_equal 0, Blob.count
  end

  test "rejects missing fields" do
    post_blob({ data: HELLO })
    assert_response 422

    post_blob({ id: "no-data" })
    assert_response 422
  end

  test "rejects malformed JSON" do
    post_blob("{not json")
    assert_response :bad_request
  end

  test "returns 409 for a duplicate id" do
    post_blob({ id: "dup", data: HELLO })
    post_blob({ id: "dup", data: HELLO })
    assert_response :conflict
  end

  test "returns 404 for an unknown id" do
    get "/v1/blobs/nope", headers: auth_headers
    assert_response :not_found
  end

  test "works with the database backend end to end" do
    Rails.configuration.x.simple_drive[:backend] = "database"
    Storage.reset!

    post_blob({ id: "db-blob", data: HELLO })
    assert_response :created
    assert_equal "database", Blob.last.backend
    assert_equal 1, BlobContent.count

    get "/v1/blobs/db-blob", headers: auth_headers
    assert_equal HELLO, response.parsed_body["data"]
  ensure
    Rails.configuration.x.simple_drive[:backend] = "local"
    Storage.reset!
  end

  test "returns 502 when the storage backend is down" do
    Rails.configuration.x.simple_drive[:backend] = "s3"
    Storage.reset!
    broken = Storage::S3Adapter.new(endpoint: "http://localhost:9", bucket: "b", region: "us-east-1",
                                    access_key_id: "k", secret_access_key: "s", http_client: FakeS3.new(fail_with: 503))
    Storage.instance_variable_set(:@adapters, { "s3" => broken })

    post_blob({ id: "s3-down", data: HELLO })
    assert_response :bad_gateway
    assert_equal 0, Blob.count
  ensure
    Rails.configuration.x.simple_drive[:backend] = "local"
    Storage.reset!
  end
end
