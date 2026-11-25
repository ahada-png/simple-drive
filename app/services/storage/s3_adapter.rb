require "net/http"
require "openssl"
require "uri"

module Storage
  # Amazon S3 compatible backend (AWS S3, MinIO, DigitalOcean Spaces, ...)
  # using only an HTTP client and our own SigV4 signer. No S3 SDK.
  #
  # Uses the S3 REST API directly:
  #   PUT    /<bucket>/<key>   PutObject
  #   GET    /<bucket>/<key>   GetObject
  #   DELETE /<bucket>/<key>   DeleteObject
  class S3Adapter < Adapter
    KEY_PREFIX = "blobs/".freeze
    NETWORK_ERRORS = [SocketError, Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError, EOFError].freeze

    def self.from_config(options)
      new(
        endpoint: options[:endpoint],
        bucket: options[:bucket],
        region: options[:region],
        access_key_id: options[:access_key_id],
        secret_access_key: options[:secret_access_key],
        force_path_style: options.fetch(:force_path_style, true)
      )
    end

    def initialize(endpoint:, bucket:, region:, access_key_id:, secret_access_key:,
                   force_path_style: true, http_client: S3::HttpClient.new, clock: -> { Time.now.utc })
      opts = { endpoint:, bucket:, region:, access_key_id:, secret_access_key: }
      opts.each { |name, _| require_option!(opts, name) }

      @endpoint = URI(endpoint.to_s.chomp("/"))
      @bucket = bucket
      @force_path_style = force_path_style
      @http = http_client
      @clock = clock
      @signer = S3::Signer.new(access_key_id:, secret_access_key:, region:)
    end

    def store(key, data)
      data = data.b
      response = request(:put, key, data, "content-type" => "application/octet-stream",
                                          "content-length" => data.bytesize.to_s)
      return true if success?(response)

      raise Error, "S3 PutObject failed (HTTP #{response.status}): #{error_code(response)}"
    end

    def retrieve(key)
      response = request(:get, key)
      return response.body.b if success?(response)
      raise NotFound, "No blob stored for key #{key}" if response.status == 404

      raise Error, "S3 GetObject failed (HTTP #{response.status}): #{error_code(response)}"
    end

    def delete(key)
      response = request(:delete, key)
      return true if success?(response) || response.status == 404

      raise Error, "S3 DeleteObject failed (HTTP #{response.status}): #{error_code(response)}"
    end

    # Public for tests / debugging.
    def object_uri(key)
      object_path = S3::Signer.uri_escape("#{KEY_PREFIX}#{key}", keep_slash: true)
      base = @endpoint.dup

      if @force_path_style
        base.path = "#{@endpoint.path}/#{S3::Signer.uri_escape(@bucket)}/#{object_path}"
      else
        base.host = "#{@bucket}.#{@endpoint.host}"
        base.path = "#{@endpoint.path}/#{object_path}"
      end
      base
    end

    private

    def request(method, key, body = nil, extra_headers = {})
      uri = object_uri(key)
      headers = @signer.sign(method: method, uri: uri, headers: extra_headers, body: body.to_s, time: @clock.call)
      @http.call(method, uri, headers, body)
    rescue *NETWORK_ERRORS => e
      raise Error, "S3 endpoint unreachable: #{e.class}: #{e.message}"
    end

    def success?(response)
      (200..299).cover?(response.status)
    end

    # S3 errors are XML: <Error><Code>NoSuchBucket</Code>...</Error>
    def error_code(response)
      response.body.to_s[%r{<Code>([^<]+)</Code>}, 1] || "unknown error"
    end
  end
end
