require "base64"

module V1
  class BlobsController < ApplicationController
    # Room for the JSON keys and an id of up to 1024 (possibly \u-escaped) chars.
    JSON_OVERHEAD = 64 * 1024

    # Reject oversized uploads from the Content-Length header, before the
    # body is parsed into memory. BlobService checks the decoded size again.
    before_action :reject_oversized_body, only: :create

    # POST /v1/blobs
    # { "id": "any string", "data": "<base64>" }
    def create
      result = BlobService.new.create(identifier: body_params[:id], encoded_data: body_params[:data])
      render json: metadata(result.blob), status: :created
    end

    # GET /v1/blobs/<id>
    def show
      result = BlobService.new.fetch(params[:id])
      render json: metadata(result.blob).merge(data: Base64.strict_encode64(result.data))
                                        .slice(:id, :data, :size, :created_at)
    end

    private

    def reject_oversized_body
      limit = BlobService.max_encoded_size + JSON_OVERHEAD
      return if request.content_length.to_i <= limit

      render_error(413, "Request body exceeds the maximum of #{limit} bytes")
    end

    # Read id/data straight from the JSON body, so a client can't swap in a
    # route or query-string value.
    def body_params
      @body_params ||= request.request_parameters.with_indifferent_access
    end

    def metadata(blob)
      {
        id: blob.identifier,
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }
    end
  end
end
