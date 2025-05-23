# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

Logstash provides infrastructure to automatically generate documentation for this plugin. We use the asciidoc format to write documentation so any comments in the source code will be first converted into asciidoc and then into html. All plugin documentation are placed under one [central location](http://www.elastic.co/guide/en/logstash/current/).

- For formatting code or config example, you can use the asciidoc `[source,ruby]` directive
- For more asciidoc formatting tips, see the excellent reference here https://github.com/elastic/docs#asciidoc-guide

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-filter-awesome", :path => "/your/local/logstash-filter-awesome"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e 'filter {awesome {}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-awesome.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/logstash-plugin install /your/local/plugin/logstash-filter-awesome.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/main/CONTRIBUTING.md) file.

# Logstash Docker Labels Filter Plugin

This is a Logstash filter plugin that enriches events with Docker service label information. It allows you to look up Docker service labels based on a field in your event and add the corresponding label value to your event.

## Installation

### Using Logstash Plugin Manager

bin/logstash-plugin install logstash-filter-docker_labels

### Manual Installation

git clone https://github.com/yourusername/logstash-filter-docker.git cd logstash-filter-docker gem build logstash-filter-dockerlabels.gemspec bin/logstash-plugin install --no-verify --local ./logstash-filter-dockerlabels-0.1.0.gem

## Configuration

The plugin supports the following configuration options:

| Parameter | Description | Type | Required | Default |
| --- | --- | --- | --- | --- |
| `input` | Source field to read the lookup value from | string | Yes | - |
| `output` | Target field to write the matched Docker label value | string | Yes | - |
| `api_url` | URL of the HTTP API endpoint that returns Docker services | string | No | `http://localhost:5000/docker-services` |
| `cache_ttl` | Time to live in minutes for cached values | number | No | 5 |
| `input_label` | Label name in Docker service to match against | string | No | `logstash.docker.input` |
| `output_label` | Label name in Docker service to retrieve value from | string | No | `logstash.docker.output` |

## Example Configuration

```ruby
filter {
  docker_labels {
    input => "hostname"
    output => "elasticsearch_host"
    api_url => "http://docker-api:5000/docker-services"
    input_label => "logstash.docker.input"
    output_label => "logstash.docker.output"
    cache_ttl => 10
  }
}

HTTP API Requirements
The plugin requires an HTTP endpoint that returns a JSON array of Docker services. Each service should contain a labels object with the configured input and output label keys.

Example response from the API:

[
  {
    "id": "988y1stob4ljjeq5wssg7p6q9",
    "name": "whoami_ui",
    "labels": {
      "logstash.docker.input": "whoami.turrican.top",
      "logstash.docker.output": "localhost:9200",
      "com.docker.stack.namespace": "whoami",
      "traefik.enable": "true"
    }
  },
  {
    "id": "jdiuzzn3ltov7yi5yczo8yn8j",
    "name": "portainer_agent",
    "labels": {
      "com.docker.stack.namespace": "portainer"
    }
  }
]


GitHub Copilot
bin/logstash-plugin install logstash-filter-docker_labels

git clone https://github.com/yourusername/logstash-filter-docker.git cd logstash-filter-docker gem build logstash-filter-dockerlabels.gemspec bin/logstash-plugin install --no-verify --local ./logstash-filter-dockerlabels-0.1.0.gem

HTTP API Requirements
The plugin requires an HTTP endpoint that returns a JSON array of Docker services. Each service should contain a labels object with the configured input and output label keys.

Example response from the API:

Architecture
Example Use Case
You have various Docker services with specific configurations in their labels. In your log events, you have the service hostname, but you need to direct logs to different Elasticsearch clusters based on the service.

Configure each Docker service with labels:

logstash.docker.input = service hostname
logstash.docker.output = Elasticsearch endpoint
Configure this filter to:

Read the hostname from each log event
Look up the corresponding Elasticsearch endpoint
Add it to the event
Configure Elasticsearch output to use the dynamically added field.

Contributing
Fork the repository
Create a feature branch
Make your changes
Write tests for your changes
Submit a pull request