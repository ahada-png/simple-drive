require "openssl"
require "time"
require "uri"

module Storage
  module S3
    # AWS Signature Version 4, implemented from the spec:
    # https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html
    #
    #   1. Build the canonical request
    #   2. Build the string to sign
    #   3. Derive the signing key (HMAC chain over date/region/service)
    #   4. Sign and put it in the Authorization header
    class Signer
      ALGORITHM = "AWS4-HMAC-SHA256".freeze
      # S3 requires the payload hash header; generic SigV4 services do not.
      UNSIGNED_PAYLOAD = "UNSIGNED-PAYLOAD".freeze

      def initialize(access_key_id:, secret_access_key:, region:, service: "s3")
        @access_key_id = access_key_id
        @secret_access_key = secret_access_key
        @region = region
        @service = service
      end

      # Returns a Hash of headers (lower-case names) to send with the request,
      # including Authorization.
      def sign(method:, uri:, headers: {}, body: "", time: Time.now.utc, content_sha256_header: true)
        uri = URI(uri)
        amz_date = time.utc.strftime("%Y%m%dT%H%M%SZ")
        date = amz_date[0, 8]
        payload_hash = hex_sha256(body.to_s)

        signed = headers.to_h { |k, v| [k.to_s.downcase, v.to_s] }
        signed["host"] = host_header(uri)
        signed["x-amz-date"] = amz_date
        signed["x-amz-content-sha256"] = payload_hash if content_sha256_header

        signed_header_names = signed.keys.sort.join(";")
        canonical_request = [
          method.to_s.upcase,
          canonical_path(uri),
          canonical_query(uri),
          canonical_headers(signed),
          signed_header_names,
          payload_hash
        ].join("\n")

        scope = "#{date}/#{@region}/#{@service}/aws4_request"
        string_to_sign = [ALGORITHM, amz_date, scope, hex_sha256(canonical_request)].join("\n")
        signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key(date), string_to_sign)

        signed.merge(
          "authorization" => "#{ALGORITHM} Credential=#{@access_key_id}/#{scope}, " \
                             "SignedHeaders=#{signed_header_names}, Signature=#{signature}"
        )
      end

      # RFC 3986 encoding as AWS wants it: only A-Z a-z 0-9 - _ . ~ unescaped.
      def self.uri_escape(string, keep_slash: false)
        string.to_s.b.gsub(%r{[^A-Za-z0-9\-_.~#{keep_slash ? '/' : ''}]}n) { |c| format("%%%02X", c.ord) }
      end

      private

      def signing_key(date)
        k_date    = hmac("AWS4#{@secret_access_key}", date)
        k_region  = hmac(k_date, @region)
        k_service = hmac(k_region, @service)
        hmac(k_service, "aws4_request")
      end

      def canonical_path(uri)
        # Paths we build are already escaped once; S3 must not double-encode.
        uri.path.to_s.empty? ? "/" : uri.path
      end

      def canonical_query(uri)
        return "" if uri.query.to_s.empty?

        uri.query.split("&").map do |pair|
          name, value = pair.split("=", 2)
          [self.class.uri_escape(URI.decode_www_form_component(name)),
           self.class.uri_escape(URI.decode_www_form_component(value.to_s))]
        end.sort.map { |n, v| "#{n}=#{v}" }.join("&")
      end

      def canonical_headers(headers)
        headers.sort.map { |name, value| "#{name}:#{value.strip.gsub(/\s+/, ' ')}\n" }.join
      end

      def host_header(uri)
        default_port = uri.scheme == "https" ? 443 : 80
        uri.port == default_port ? uri.host : "#{uri.host}:#{uri.port}"
      end

      def hmac(key, data)
        OpenSSL::HMAC.digest("SHA256", key, data)
      end

      def hex_sha256(data)
        OpenSSL::Digest::SHA256.hexdigest(data)
      end
    end
  end
end
