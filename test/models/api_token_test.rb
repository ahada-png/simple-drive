require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "stores only a digest and authenticates the raw token" do
    token, raw = ApiToken.generate!(name: "ci")

    assert_not_equal raw, token.token_digest
    assert_equal 64, token.token_digest.length
    assert_equal token, ApiToken.authenticate(raw)
    assert_not_nil token.reload.last_used_at
  end

  test "rejects unknown or blank tokens" do
    ApiToken.generate!(name: "ci")
    assert_nil ApiToken.authenticate("wrong")
    assert_nil ApiToken.authenticate("")
    assert_nil ApiToken.authenticate(nil)
  end
end
