require "net/http"
require "uri"

module Storage
  module S3
    # Minimal HTTP transport over Net::HTTP. Kept behind a tiny interface so
    # the adapter can be tested with a fake.
    class HttpClient
      Response = Struct.new(:status, :body, :headers, keyword_init: true)

      METHODS = {
        get: Net::HTTP::Get,
        put: Net::HTTP::Put,
        delete: Net::HTTP::Delete,
        head: Net::HTTP::Head
      }.freeze

      def initialize(open_timeout: 5, read_timeout: 30)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def call(method, uri, headers, body = nil)
        uri = URI(uri)
        request = METHODS.fetch(method).new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body if body

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        response = http.start { |conn| conn.request(request) }
        Response.new(status: response.code.to_i, body: response.body.to_s, headers: response.to_hash)
      end
    end
  end
end
