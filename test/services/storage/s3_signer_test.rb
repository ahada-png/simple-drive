require "test_helper"

class S3SignerTest < ActiveSupport::TestCase
  # Credentials and expected values from AWS's published SigV4 test suite
  # ("get-vanilla" case), so this checks our signer against AWS's own output.
  AWS_TEST_KEY = "AKIDEXAMPLE".freeze
  AWS_TEST_SECRET = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY".freeze
  AWS_TEST_TIME = Time.utc(2015, 8, 30, 12, 36, 0)

  test "matches the AWS SigV4 test suite get-vanilla signature" do
    signer = Storage::S3::Signer.new(access_key_id: AWS_TEST_KEY, secret_access_key: AWS_TEST_SECRET,
                                     region: "us-east-1", service: "service")

    headers = signer.sign(method: "GET", uri: "https://example.amazonaws.com/",
                          time: AWS_TEST_TIME, content_sha256_header: false)

    assert_equal "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, " \
                 "SignedHeaders=host;x-amz-date, " \
                 "Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
                 headers["authorization"]
    assert_equal "20150830T123600Z", headers["x-amz-date"]
  end

  test "matches the AWS SigV4 test suite get-vanilla-query-order-key-case signature" do
    signer = Storage::S3::Signer.new(access_key_id: AWS_TEST_KEY, secret_access_key: AWS_TEST_SECRET,
                                     region: "us-east-1", service: "service")

    headers = signer.sign(method: "GET", uri: "https://example.amazonaws.com/?Param2=value2&Param1=value1",
                          time: AWS_TEST_TIME, content_sha256_header: false)

    assert_match(/Signature=b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500\z/,
                 headers["authorization"])
  end

  test "signs the payload hash and includes the port in host for S3" do
    signer = Storage::S3::Signer.new(access_key_id: "key", secret_access_key: "secret", region: "us-east-1")
    headers = signer.sign(method: "PUT", uri: "http://localhost:9000/bucket/blobs/abc", body: "hello", time: AWS_TEST_TIME)

    assert_equal "localhost:9000", headers["host"]
    assert_equal OpenSSL::Digest::SHA256.hexdigest("hello"), headers["x-amz-content-sha256"]
    assert_includes headers["authorization"], "SignedHeaders=host;x-amz-content-sha256;x-amz-date"
    assert_includes headers["authorization"], "/us-east-1/s3/aws4_request"
  end

  test "uri_escape follows the AWS encoding rules" do
    assert_equal "a%20b%2Fc~_-.", Storage::S3::Signer.uri_escape("a b/c~_-.")
    assert_equal "a%20b/c", Storage::S3::Signer.uri_escape("a b/c", keep_slash: true)
    assert_equal "%C3%A9", Storage::S3::Signer.uri_escape("é")
  end
end
