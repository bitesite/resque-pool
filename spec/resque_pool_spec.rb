require 'spec_helper'

RSpec.configure do |config|
  config.include PoolSpecHelpers
  config.after {
    Object.send(:remove_const, :RAILS_ENV) if defined? RAILS_ENV
    ENV.delete 'RACK_ENV'
    ENV.delete 'RAILS_ENV'
    ENV.delete 'RESQUE_ENV'
    ENV.delete 'RESQUE_POOL_CONFIG'
  }
end

describe Resque::Pool, "when loading a simple pool configuration" do
  let(:config) do
    { 'foo' => 1, 'bar' => 2, 'foo,bar' => 3, 'bar,foo' => 4, }
  end
  subject { Resque::Pool.new(config) }

  context "when ENV['RACK_ENV'] is set" do
    before { ENV['RACK_ENV'] = 'development' }

    it "should load the values from the Hash" do
      expect(subject.config["foo"]).to eq 1
      expect(subject.config["bar"]).to eq 2
      expect(subject.config["foo,bar"]).to eq 3
      expect(subject.config["bar,foo"]).to eq 4
    end
  end

end

describe Resque::Pool, "when loading the pool configuration from a Hash" do

  let(:config) do
    {
      'foo' => 8,
      'test'        => { 'bar' => 10, 'foo,bar' => 12 },
      'development' => { 'baz' => 14, 'foo,bar' => 16 },
    }
  end

  subject { Resque::Pool.new(config) }

  context "when RAILS_ENV is set" do
    before { RAILS_ENV = "test" }

    it "should load the default values from the Hash" do
      expect(subject.config["foo"]).to eq(8)
    end

    it "should merge the values for the correct RAILS_ENV" do
      expect(subject.config["bar"]).to eq(10)
      expect(subject.config["foo,bar"]).to eq(12)
    end

    it "should not load the values for the other environments" do
      expect(subject.config["foo,bar"]).to eq(12)
      expect(subject.config["baz"]).to be_nil
    end

  end

  context "when Rails.env is set" do
    before(:each) do
      module Rails; end
      allow(Rails).to receive(:env) { 'test' }
    end

    it "should load the default values from the Hash" do
      expect(subject.config["foo"]).to eq(8)
    end

    it "should merge the values for the correct RAILS_ENV" do
      expect(subject.config["bar"]).to eq(10)
      expect(subject.config["foo,bar"]).to eq(12)
    end

    it "should not load the values for the other environments" do
      expect(subject.config["foo,bar"]).to eq(12)
      expect(subject.config["baz"]).to be_nil
    end

    after(:all) { Object.send(:remove_const, :Rails) }
  end


  context "when ENV['RESQUE_ENV'] is set" do
    before { ENV['RESQUE_ENV'] = 'development' }
    it "should load the config for that environment" do
      expect(subject.config["foo"]).to eq(8)
      expect(subject.config["foo,bar"]).to eq(16)
      expect(subject.config["baz"]).to eq(14)
      expect(subject.config["bar"]).to be_nil
    end
  end

  context "when there is no environment" do
    it "should load the default values only" do
      expect(subject.config["foo"]).to eq(8)
      expect(subject.config["bar"]).to be_nil
      expect(subject.config["foo,bar"]).to be_nil
      expect(subject.config["baz"]).to be_nil
    end
  end

end

describe Resque::Pool, "given no configuration" do
  subject { Resque::Pool.new(nil) }
  it "should have no worker types" do
    expect(subject.config).to eq({})
  end
end

describe Resque::Pool, "when loading the pool configuration from a file" do

  subject { Resque::Pool.new("spec/resque-pool.yml") }

  context "when RAILS_ENV is set" do
    before { RAILS_ENV = "test" }

    it "should load the default YAML" do
      expect(subject.config["foo"]).to eq(1)
    end

    it "should merge the YAML for the correct RAILS_ENV" do
      expect(subject.config["bar"]).to eq(5)
      expect(subject.config["foo,bar"]).to eq(3)
    end

    it "should not load the YAML for the other environments" do
      expect(subject.config["foo"]).to eq(1)
      expect(subject.config["bar"]).to eq(5)
      expect(subject.config["foo,bar"]).to eq(3)
      expect(subject.config["baz"]).to be_nil
    end

  end

  context "when ENV['RACK_ENV'] is set" do
    before { ENV['RACK_ENV'] = 'development' }
    it "should load the config for that environment" do
      expect(subject.config["foo"]).to eq(1)
      expect(subject.config["foo,bar"]).to eq(4)
      expect(subject.config["baz"]).to eq(23)
      expect(subject.config["bar"]).to be_nil
    end
  end

  context "when there is no environment" do
    it "should load the default values only" do
      expect(subject.config["foo"]).to eq(1)
      expect(subject.config["bar"]).to be_nil
      expect(subject.config["foo,bar"]).to be_nil
      expect(subject.config["baz"]).to be_nil
    end
  end

  context "when a custom file is specified" do
    before { ENV["RESQUE_POOL_CONFIG"] = 'spec/resque-pool-custom.yml.erb' }
    subject { Resque::Pool.new }
    it "should find the right file, and parse the ERB" do
      expect(subject.config["foo"]).to eq(2)
    end
  end

  context "when the file changes" do
    require 'tempfile'

    let(:config_file_path) {
      config_file = Tempfile.new("resque-pool-test")
      config_file.write "orig: 1"
      config_file.close
      config_file.path
    }

    subject {
      no_spawn(Resque::Pool.new(config_file_path))
    }

    it "should not automatically load the changes" do
      expect(subject.config.keys).to eq(["orig"])

      File.open(config_file_path, "w"){|f| f.write "changed: 1"}
      expect(subject.config.keys).to eq(["orig"])
      subject.load_config
      expect(subject.config.keys).to eq(["orig"])
    end

    it "should reload the changes on HUP signal" do
      expect(subject.config.keys).to eq(["orig"])

      File.open(config_file_path, "w"){|f| f.write "changed: 1"}
      expect(subject.config.keys).to eq(["orig"])
      subject.load_config
      expect(subject.config.keys).to eq(["orig"])

      simulate_signal subject, :HUP

      expect(subject.config.keys).to eq(["changed"])
    end

  end

end

describe Resque::Pool, "the pool configuration custom loader" do
  it "should retrieve the config based on the environment" do
    custom_loader = double(call: Hash.new)
    RAILS_ENV = "env"

    Resque::Pool.new(custom_loader)

    expect(custom_loader).to have_received(:call).with("env")
  end

  it "should reset the config loader on HUP" do
    custom_loader = double(call: Hash.new, reset!: true)

    pool = no_spawn(Resque::Pool.new(custom_loader))
    expect(custom_loader).to have_received(:call).once

    pool.sig_queue.push :HUP
    pool.handle_sig_queue!
    expect(custom_loader).to have_received(:reset!)
    expect(custom_loader).to have_received(:call).twice
  end

  it "can be a lambda" do
    RAILS_ENV = "fake"
    count = 1
    pool = no_spawn(Resque::Pool.new(lambda {|env|
      {env.reverse => count}
    }))
    expect(pool.config).to eq({"ekaf" => 1})

    count = 3
    pool.sig_queue.push :HUP
    pool.handle_sig_queue!

    expect(pool.config).to eq({"ekaf" => 3})
  end
end

describe "the class-level .config_loader attribute" do
  context "when not provided" do
    subject { Resque::Pool.create_configured }

    it "created pools use config file and hash loading logic" do
      expect(subject.config_loader).to be_instance_of Resque::Pool::FileOrHashLoader
    end
  end

  context "when provided with a custom config loader" do
    let(:custom_config_loader) {
      double(call: Hash.new)
    }
    before(:each) { Resque::Pool.config_loader = custom_config_loader }
    after(:each) { Resque::Pool.config_loader = nil }
    subject { Resque::Pool.create_configured }

    it "created pools use the specified config loader" do
      expect(subject.config_loader).to eq(custom_config_loader)
    end
  end
end

describe Resque::Pool, "given after_prefork hook" do
  subject { Resque::Pool.new(nil) }

  let(:worker) { double }

  context "with a single hook" do
    before { Resque::Pool.after_prefork { @called = true } }

    it "should call prefork" do
      subject.call_after_prefork!(worker)
      expect(@called).to eq(true)
    end
  end

  context "with a single hook by attribute writer" do
    before { Resque::Pool.after_prefork = Proc.new { @called = true } }

    it "should call prefork" do
      subject.call_after_prefork!(worker)
      expect(@called).to eq(true)
    end
  end

  context "with multiple hooks" do
    before {
      Resque::Pool.after_prefork { @called_first = true }
      Resque::Pool.after_prefork { @called_second = true }
    }

    it "should call both" do
      subject.call_after_prefork!(worker)
      expect(@called_first).to eq(true)
      expect(@called_second).to eq(true)
    end
  end

  it "passes the worker instance to the hook" do
    val = nil
    Resque::Pool.after_prefork { |w| val = w }
    subject.call_after_prefork!(worker)
    expect(val).to eq(worker)
  end
end
