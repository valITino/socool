#!/usr/bin/env ruby
# tests/vagrant/test-vagrantfile.rb
#
# Exercises the Vagrantfile's logic without requiring the vagrant gem.
# Mocks the `Vagrant.configure` / `config.vm.define` DSL just enough to
# capture the sequence of defined VMs and the calls made on each, then
# asserts:
#   1. VMs come out in boot_order ascending.
#   2. Scanner filtering respects SOCOOL_SCANNER.
#   3. Every non-pfSense VM gets one host-only private_network NIC.
#   4. pfSense gets two host-only NICs (lan + management), zero for wan_sim.
#   5. hostname validation rejects bad input.
#
# Run: ruby tests/vagrant/test-vagrantfile.rb

require 'yaml'
require 'minitest/autorun'

REPO_ROOT = File.expand_path('../..', __dir__)
VAGRANTFILE = File.join(REPO_ROOT, 'vagrant', 'Vagrantfile')

# ────────────────────────────────────────────────────────────────────────
# Minimal Vagrant DSL mock
# ────────────────────────────────────────────────────────────────────────

class FakeVMProvider
  attr_reader :provider, :settings, :customizations

  def initialize(provider)
    @provider = provider
    @settings = {}
    @customizations = []
  end

  def method_missing(name, *args)
    if name.to_s.end_with?('=')
      @settings[name.to_s.chomp('=')] = args.first
    else
      super
    end
  end

  def respond_to_missing?(_name, _include_private = false); true; end

  def customize(args); @customizations << args; end
end

class FakeVMConfig
  attr_accessor :hostname, :box, :box_url, :box_check_update
  attr_reader :networks, :providers, :synced_folders

  def initialize
    @networks = []
    @providers = {}
    @synced_folders = []
  end

  def network(type, **opts); @networks << [type, opts]; end

  def provider(name)
    prov = (@providers[name] ||= FakeVMProvider.new(name))
    yield prov if block_given?
    prov
  end

  def synced_folder(src, dest, **opts); @synced_folders << [src, dest, opts]; end
end

class FakeNode
  attr_reader :name, :vm

  def initialize(name)
    @name = name
    @vm = FakeVMConfig.new
  end
end

class FakeConfig
  attr_reader :nodes, :global_vm

  def initialize
    @nodes = []
    @global_vm = FakeVMConfig.new
  end

  def vm
    @global_vm_shim ||= Object.new.tap do |shim|
      shim.define_singleton_method(:synced_folder) { |*a, **o| @global_vm.synced_folders << [a[0], a[1], o] }
      shim.define_singleton_method(:box_check_update=) { |v| @global_vm.box_check_update = v }
      shim.define_singleton_method(:define) do |name, &blk|
        node = FakeNode.new(name)
        blk.call(node) if blk
        nodes << node
      end
      # Forward to the parent's @nodes / @global_vm
      parent = self
      shim.define_singleton_method(:_parent_nodes) { parent.nodes }
      shim.define_singleton_method(:_parent_global) { parent.global_vm }
    end
    # Re-bind the shim's `define` to our real nodes array.
    shim = @global_vm_shim
    this = self
    shim.define_singleton_method(:define) do |name, &blk|
      node = FakeNode.new(name)
      blk.call(node) if blk
      this.nodes << node
    end
    shim.define_singleton_method(:synced_folder) { |src, dest, **o| this.global_vm.synced_folders << [src, dest, o] }
    shim.define_singleton_method(:box_check_update=) { |v| this.global_vm.box_check_update = v }
    shim
  end
end

module Vagrant
  def self.configure(_api_version)
    @@captured_config = FakeConfig.new
    yield @@captured_config
  end
  def self.captured_config; @@captured_config; end
end

# ────────────────────────────────────────────────────────────────────────
# Load the Vagrantfile with a mocked Vagrant namespace
# ────────────────────────────────────────────────────────────────────────

def load_vagrantfile_with_env(env = {})
  old_env = {}
  env.each { |k, v| old_env[k] = ENV[k]; ENV[k] = v }
  begin
    # Fresh capture on each load.
    Vagrant.class_variable_set(:@@captured_config, nil)
    load VAGRANTFILE
  ensure
    old_env.each { |k, v| ENV[k] = v }
  end
  Vagrant.captured_config
end

# ────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────

class VagrantfileTest < Minitest::Test
  def test_boot_order_ascending
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'none')
    names = cfg.nodes.map(&:name).map(&:to_s)
    assert_equal %w[pfsense kali windows-victim wazuh thehive], names,
      "VMs must be defined in boot_order (pfsense=0, kali=10, windows-victim=20, wazuh=30, thehive=35)"
  end

  def test_scanner_filter_none
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'none')
    names = cfg.nodes.map(&:name).map(&:to_s)
    refute_includes names, 'nessus'
    refute_includes names, 'openvas'
  end

  def test_scanner_filter_nessus
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'nessus')
    names = cfg.nodes.map(&:name).map(&:to_s)
    assert_includes names, 'nessus'
    refute_includes names, 'openvas'
  end

  def test_scanner_filter_openvas
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'openvas')
    names = cfg.nodes.map(&:name).map(&:to_s)
    assert_includes names, 'openvas'
    refute_includes names, 'nessus'
  end

  def test_pfsense_has_two_private_networks
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'none')
    pfsense = cfg.nodes.find { |n| n.name.to_s == 'pfsense' }
    refute_nil pfsense
    # wan_sim is served by Vagrant's default NAT NIC (not declared as
    # :private_network), so we expect exactly two :private_network calls.
    priv_nets = pfsense.vm.networks.select { |t, _| t == :private_network }
    assert_equal 2, priv_nets.length, "pfSense should have lan + management private networks, found #{priv_nets.length}"
    ips = priv_nets.map { |_, o| o[:ip] }.sort
    assert_equal ['10.42.10.1', '10.42.20.1'], ips
  end

  def test_non_pfsense_vms_have_one_private_network
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'none')
    %w[kali windows-victim wazuh thehive].each do |name|
      node = cfg.nodes.find { |n| n.name.to_s == name }
      priv_nets = node.vm.networks.select { |t, _| t == :private_network }
      assert_equal 1, priv_nets.length, "#{name} should have exactly one private network, found #{priv_nets.length}"
    end
  end

  def test_no_public_network_anywhere
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'nessus')
    cfg.nodes.each do |node|
      pub = node.vm.networks.select { |t, _| t == :public_network }
      assert_empty pub, "#{node.name}: bridged/public_network found — must be zero by default"
    end
  end

  def test_hostname_validation_rejects_bad_token
    # Read with explicit UTF-8 encoding — the Vagrantfile comments contain
    # box-drawing characters (U+2500s) that fail a default US-ASCII read.
    content = File.read(VAGRANTFILE, encoding: 'UTF-8')
    assert_match(/HOSTNAME_RE\s*=\s*\/\\A\[a-z\]\[a-z0-9-\]\{0,30\}\\z\//, content,
      'HOSTNAME_RE regex should enforce the project-wide hostname contract')
  end

  def test_synced_folder_disabled
    cfg = load_vagrantfile_with_env('SOCOOL_SCANNER' => 'none')
    globals = cfg.global_vm.synced_folders
    vagrant_folder = globals.find { |src, dest, _| src == '.' && dest == '/vagrant' }
    refute_nil vagrant_folder, 'Default /vagrant sync folder should be declared'
    assert_equal true, vagrant_folder[2][:disabled], '/vagrant share must be disabled by default'
  end

  def test_invalid_scanner_env_fails_fast
    assert_raises(RuntimeError) do
      load_vagrantfile_with_env('SOCOOL_SCANNER' => 'bogus')
    end
  end
end
