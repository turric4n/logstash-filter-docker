Gem::Specification.new do |s|
  s.name          = 'logstash-filter-docker-labels'
  s.version       = '0.1.0'
  s.licenses      = ['Apache-2.0']
  s.summary       = 'Logstash Filter Plugin to map input values to output values using Docker service labels'
  s.description   = 'This filter allows you to map values from an input field to output values defined in Docker service labels. It supports caching to reduce Docker API load.'
  s.homepage      = 'https://github.com/your-username/logstash-filter-docker-labels'
  s.authors       = ['Your Name']
  s.email         = 'your_email@example.com'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "filter" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0.0"
  s.add_runtime_dependency "docker-api", "~> 2.2"
  s.add_development_dependency 'logstash-devutils'
end