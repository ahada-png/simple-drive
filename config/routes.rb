Rails.application.routes.draw do
  # Every route goes through ApplicationController#authenticate!, so the
  # whole service requires a bearer token (no public health-check route).
  scope "v1", module: "v1", defaults: { format: :json } do
    post "blobs", to: "blobs#create"
    # Glob so ids that look like paths ("photos/2024/cat.png") work unescaped.
    get "blobs/*id", to: "blobs#show", format: false, as: :blob
  end
end
