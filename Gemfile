source "https://rubygems.org"

ruby ">= 3.1"

gem "rails", "~> 7.2.0"
gem "sqlite3", ">= 1.4"
gem "puma", ">= 5.0"

# FTP storage backend (net-ftp is no longer a default gem since Ruby 3.1)
gem "net-ftp"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end
