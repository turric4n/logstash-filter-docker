# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/docker_labels"
require "json"

describe LogStash::Filters::DockerLabels do
  let(:plugin) { LogStash::Filters::DockerLabels.new(config) }
  
  describe "Basic configuration" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es",
        "api_url" => "http://localhost:5000/docker-services",
        "input_label" => "logstash.docker.input",
        "output_label" => "logstash.docker.output"
      }
    end

    before do
      plugin.register
    end

    context "when processing an event with matching input field" do
      let(:event) { LogStash::Event.new("hostname" => "whoami.turrican.top") }
      
      # Mock HTTP API response
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return(
          '[{"id":"988y1stob4ljjeq5wssg7p6q9","name":"whoami_ui","labels":{"com.docker.stack.image":"traefik/whoami","com.docker.stack.namespace":"whoami","logstash.docker.output":"localhost:9200","logstash.docker.input":"whoami.turrican.top","traefik.docker.network":"traefik_swarm","traefik.enable":"true","traefik.http.routers.whoami_ui.rule":"Host(`whoami.turrican.top`)","traefik.http.routers.whoami_ui.service":"whoami_ui","traefik.http.routers.whoami_ui.tls.certresolver":"myresolver","traefik.http.services.whoami_ui.loadbalancer.server.port":"80"}}]'
        )
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field with the Docker label value" do
        plugin.filter(event)
        expect(event.get("target_es")).to eq("localhost:9200")
      end
    end

    context "when processing an event with no matching container" do
      let(:event) { LogStash::Event.new("hostname" => "non-existent-host") }
      
      # Mock HTTP API response
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return('[]')
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field to nil" do
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end

    context "when input field is missing" do
      let(:event) { LogStash::Event.new("some_other_field" => "value") }
      
      it "doesn't modify the event" do
        original_event = event.clone
        plugin.filter(event)
        # The output field should not be set
        expect(event.get("target_es")).to be_nil
        # The rest of the event should be unchanged
        expect(event.to_hash.reject{|k,v| k == "@timestamp"}).to eq(original_event.to_hash.reject{|k,v| k == "@timestamp"})
      end
    end
    
    context "when API call fails" do
      let(:event) { LogStash::Event.new("hostname" => "whoami.turrican.top") }
      
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return(500)
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field to nil" do
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
  end
  
  describe "Cache functionality" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es",
        "cache_ttl" => 5
      }
    end

    before do
      plugin.register
    end

    context "when processing multiple events with same input value" do
      let(:event1) { LogStash::Event.new("hostname" => "cache-test") }
      let(:event2) { LogStash::Event.new("hostname" => "cache-test") }
      
      it "calls API only once" do
        # Mock the API response
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return(
          '[{"id":"test","name":"test_service","labels":{"logstash.docker.input":"cache-test","logstash.docker.output":"cached-value"}}]'
        )
        
        # Expect only one call to get_response
        expect(Net::HTTP).to receive(:get_response).once.and_return(mock_response)
        
        plugin.filter(event1)
        plugin.filter(event2)
        
        expect(event1.get("target_es")).to eq("cached-value")
        expect(event2.get("target_es")).to eq("cached-value")
      end
    end
  end
end