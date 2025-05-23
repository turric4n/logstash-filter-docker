source 'https://rubygems.org'
gemspec

logstash_path = ENV['LOGSTASH_PATH'] || '/usr/share/logstash'

if Dir.exist?(logstash_path)
  gem 'logstash-core', :path => "#{logstash_path}/logstash-core"
  gem 'logstash-core-plugin-api', :path => "#{logstash_path}/logstash-core-plugin-api"
end

# Development dependencies
group :development, :test do
  gem 'rspec', '~> 3.0'
  gem 'pry'
  gem 'docker-api', '~> 2.2'
end