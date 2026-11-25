# In-memory stand-in for an S3 server, plugged in as the S3Adapter's HTTP
# client. Records every request so tests can assert on signing headers.
class FakeS3
  Response = Storage::S3::HttpClient::Response

  attr_reader :requests, :objects

  def initialize(fail_with: nil)
    @objects = {}
    @requests = []
    @fail_with = fail_with
  end

  def call(method, uri, headers, body = nil)
    @requests << { method: method, uri: uri.to_s, headers: headers, body: body }
    return Response.new(status: @fail_with, body: "<Error><Code>InternalError</Code></Error>", headers: {}) if @fail_with

    path = URI(uri).path
    case method
    when :put
      @objects[path] = body.dup
      Response.new(status: 200, body: "", headers: {})
    when :get
      if @objects.key?(path)
        Response.new(status: 200, body: @objects[path], headers: {})
      else
        Response.new(status: 404, body: "<Error><Code>NoSuchKey</Code></Error>", headers: {})
      end
    when :delete
      @objects.delete(path)
      Response.new(status: 204, body: "", headers: {})
    end
  end
end
