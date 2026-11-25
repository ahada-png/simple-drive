class ApplicationController < ActionController::API
  # Only "Authorization: Bearer <token>" is accepted (RFC 6750). The scheme
  # name is case-insensitive per RFC 7235; other schemes are rejected.
  BEARER_PATTERN = /\ABearer +([A-Za-z0-9\-._~+\/]+=*)\s*\z/i

  before_action :authenticate!

  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render_error(:bad_request, "Request body is not valid JSON")
  end
  rescue_from BlobService::InvalidRequest do |e|
    render_error(422, e.message)
  end
  rescue_from BlobService::TooLarge do |e|
    render_error(413, e.message)
  end
  rescue_from BlobService::AlreadyExists do |e|
    render_error(:conflict, e.message)
  end
  rescue_from BlobService::NotFound do |e|
    render_error(:not_found, e.message)
  end
  # rescue_from handlers are matched last-declared-first, so the generic
  # Storage::Error goes before its more specific subclass.
  rescue_from Storage::Error do |e|
    Rails.logger.error("[storage] #{e.class}: #{e.message}")
    render_error(:bad_gateway, "Storage backend error")
  end
  rescue_from Storage::IntegrityError do |e|
    Rails.logger.error(e.message)
    render_error(:internal_server_error, "Stored data failed its integrity check")
  end

  private

  attr_reader :current_api_token

  def authenticate!
    token = request.authorization.to_s[BEARER_PATTERN, 1]
    @current_api_token = ApiToken.authenticate(token)
    return if @current_api_token

    response.headers["WWW-Authenticate"] = 'Bearer realm="Simple Drive"'
    render_error(:unauthorized, "Missing or invalid bearer token")
  end

  def render_error(status, message)
    render json: { error: message }, status: status
  end
end
