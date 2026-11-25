namespace :api_tokens do
  desc "Create an API token: bin/rails \"api_tokens:create[name]\""
  task :create, [:name] => :environment do |_t, args|
    name = args[:name].presence || "default"
    token, raw = ApiToken.generate!(name: name)
    puts "Created token ##{token.id} (#{name}). Store it now, it will not be shown again:"
    puts
    puts "  #{raw}"
    puts
    puts "Use it as:  Authorization: Bearer #{raw}"
  end

  desc "List API tokens (names only)"
  task list: :environment do
    ApiToken.order(:id).each do |t|
      puts "##{t.id}  #{t.name}  created #{t.created_at.utc.iso8601}  last used #{t.last_used_at&.utc&.iso8601 || 'never'}"
    end
  end

  desc "Revoke an API token by id: bin/rails \"api_tokens:revoke[3]\""
  task :revoke, [:id] => :environment do |_t, args|
    ApiToken.find(args[:id]).destroy!
    puts "Revoked token ##{args[:id]}"
  end
end
