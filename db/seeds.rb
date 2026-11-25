# Lets you bootstrap a known token, e.g. in docker or CI:
#   API_TOKEN=my-secret bin/rails db:seed
if ENV["API_TOKEN"].present?
  digest = ApiToken.digest(ENV["API_TOKEN"])
  ApiToken.find_or_create_by!(token_digest: digest) { |t| t.name = "seeded" }
  puts "Seeded API token from API_TOKEN."
end
