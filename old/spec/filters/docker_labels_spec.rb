# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/docker_labels"

describe LogStash::Filters::DockerLabels do
  let(:plugin) { LogStash::Filters::DockerLabels.new(config) }
  
  describe "Basic configuration" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es"
      }
    end

    before do
      plugin.register
    end

    context "when processing an event with matching input field" do
      let(:event) { LogStash::Event.new("hostname" => "web-server-1") }
      
      # Mock Docker container response
      before do
        allow_any_instance_of(LogStash::Filters::DockerLabels).to receive(:get_docker_label_output).with("web-server-1").and_return("elasticsearch-prod")
      end
      
      it "sets the output field with the Docker label value" do
        plugin.filter(event)
        expect(event.get("target_es")).to eq("elasticsearch-prod")
      end
    end

    context "when processing an event with no matching container" do
      let(:event) { LogStash::Event.new("hostname" => "non-existent-host") }
      
      # Mock Docker container response with no match
      before do
        allow_any_instance_of(LogStash::Filters::DockerLabels).to receive(:get_docker_label_output).with("non-existent-host").and_return(nil)
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
      
      it "calls Docker API only once" do
        expect_any_instance_of(LogStash::Filters::DockerLabels).to receive(:get_docker_label_output).with("cache-test").once.and_return("cached-value")
        
        plugin.filter(event1)
        plugin.filter(event2)
        
        expect(event1.get("target_es")).to eq("cached-value")
        expect(event2.get("target_es")).to eq("cached-value")
      end
    end
  end
end