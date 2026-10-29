# Deterministic tests for build-number allocation and the channel group preflight.
require 'minitest/autorun'
require 'ostruct'
require_relative 'testflight_build_number'

class TestflightBuildNumberTest < Minitest::Test
  class FakeAPI
    attr_accessor :app_value, :build_values, :failure
    def app
      raise 'private API response must not leak' if failure
      app_value
    end

    def builds(_app) = build_values
  end

  def setup
    @api = FakeAPI.new
    @api.app_value = OpenStruct.new(id: 'app', bundle_id: OrangeoneTestflight::BUNDLE_ID)
    @api.build_values = []
    @numbers = OrangeoneBuildNumber.new(api: @api)
  end

  def builds(*versions) = versions.map { |version| OpenStruct.new(version: version) }

  def test_next_number_is_above_every_build_of_every_version
    @api.build_values = builds('8', '9', '33', '10', '35')
    assert_equal 36, @numbers.allocate(floor: 34)
  end

  def test_the_repository_floor_wins_when_app_store_connect_lags
    @api.build_values = builds('8', '9')
    assert_equal 35, @numbers.allocate(floor: 34)
  end

  def test_no_builds_starts_above_the_floor
    assert_equal 35, @numbers.allocate(floor: 34)
    assert_equal 1, @numbers.allocate(floor: 0)
  end

  def test_non_numeric_build_values_are_ignored
    @api.build_values = builds('abc', '12', nil, '1.2', '')
    assert_equal 13, @numbers.allocate(floor: 0)
  end

  def test_two_allocations_without_an_upload_are_equal_and_an_upload_moves_on
    @api.build_values = builds('40')
    assert_equal 41, @numbers.allocate(floor: 34)
    assert_equal 41, @numbers.allocate(floor: 34)
    @api.build_values = builds('40', '41')
    assert_equal 42, @numbers.allocate(floor: 34)
  end

  def test_the_limit_is_enforced
    @api.build_values = builds('9999')
    assert_raises(OrangeoneBuildNumber::Error) { @numbers.allocate(floor: 34) }
    @api.build_values = []
    assert_equal 9999, @numbers.allocate(floor: 9998)
    assert_raises(OrangeoneBuildNumber::Error) { @numbers.allocate(floor: 9999) }
  end

  def test_an_allocated_number_is_only_valid_while_nothing_newer_exists
    @api.build_values = builds('35')
    assert @numbers.assert_unused(number: 36, floor: 34)
    assert_raises(OrangeoneBuildNumber::Error) { @numbers.assert_unused(number: 35, floor: 34) }
    @api.build_values = builds('36')
    assert_raises(OrangeoneBuildNumber::Error) { @numbers.assert_unused(number: '36', floor: 34) }
    @api.build_values = []
    assert_raises(OrangeoneBuildNumber::Error) { @numbers.assert_unused(number: 34, floor: 34) }
  end

  def test_missing_or_wrong_app_fails
    [nil, OpenStruct.new(id: 'x', bundle_id: 'ch.orangepos.productscanner.dev')].each do |app|
      @api.app_value = app
      assert_raises(OrangeoneBuildNumber::Error) { @numbers.allocate(floor: 1) }
    end
  end

  def test_api_failures_are_sanitized
    @api.failure = true
    error = assert_raises(OrangeoneBuildNumber::Error) { @numbers.allocate(floor: 1) }
    refute_includes error.message, 'private API response'
  end

  def test_the_adapter_queries_all_ios_builds_of_the_production_app
    # Only the two Spaceship entry points are supplied; HTTP stays a hosted check.
    calls = []
    namespace = Module.new
    client = Class.new
    apps = Class.new
    builds = Class.new
    apps.define_singleton_method(:find) { |bundle| calls << [:app, bundle] }
    builds.define_singleton_method(:all) { |**args| calls << [:builds, args]; [] }
    client.const_set(:App, apps)
    client.const_set(:Build, builds)
    namespace.const_set(:ConnectAPI, client)
    original = Object.const_defined?(:Spaceship) ? Object.send(:remove_const, :Spaceship) : nil
    Object.const_set(:Spaceship, namespace)
    adapter = OrangeoneBuildNumber::AppleAPI.new
    adapter.app
    adapter.builds(OpenStruct.new(id: 'app-1'))
    assert_equal [:app, 'ch.orangepos.productscanner'], calls.first
    assert_equal [:builds, { app_id: 'app-1', platform: 'IOS' }], calls.last
  ensure
    Object.send(:remove_const, :Spaceship) if namespace && Object.const_defined?(:Spaceship) && Object.const_get(:Spaceship).equal?(namespace)
    Object.const_set(:Spaceship, original) if original
  end
end

# The channel preflight keeps a DEV/STG build from reaching any other tester group.
class TestflightChannelPreflightTest < Minitest::Test
  class FakeAPI
    attr_accessor :app_value, :group_values
    def app = app_value
    def groups(*) = group_values
  end

  def setup
    @api = FakeAPI.new
    @api.app_value = OpenStruct.new(id: 'production-app', bundle_id: OrangeoneTestflight::BUNDLE_ID)
    @api.group_values = OrangeoneTestflight::GROUPS.map do |key, name|
      OpenStruct.new(id: key, name: name, is_internal_group: true, has_access_to_all_builds: false)
    end
    @helper = OrangeoneTestflight.new(api: @api)
  end

  def test_channels_pass_when_no_group_has_automatic_distribution
    %w[dev staging].each { |target| assert_same @helper, @helper.prepare_channel(target) }
  end

  def test_automatic_distribution_on_the_production_group_blocks_dev_and_staging
    production = @api.group_values.find { |group| group.id == 'production' }
    production.has_access_to_all_builds = true
    %w[dev staging].each do |target|
      error = assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel(target) }
      assert_includes error.message, 'automatic distribution'
    end
  end

  def test_automatic_distribution_on_the_other_channel_group_also_blocks
    @api.group_values.find { |group| group.id == 'staging' }.has_access_to_all_builds = true
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel('dev') }
  end

  def test_the_selected_group_itself_must_not_be_automatic
    @api.group_values.find { |group| group.id == 'dev' }.has_access_to_all_builds = true
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel('dev') }
  end

  def test_unknown_missing_or_ambiguous_groups_and_wrong_app_fail
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel('unknown') }
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel(nil) }
    @api.group_values = []
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel('dev') }
    @api.app_value = nil
    assert_raises(OrangeoneTestflight::Error) { @helper.prepare_channel('dev') }
  end

  def test_the_existing_prepare_behavior_is_unchanged_for_the_production_flow
    # Production/manual distribution does not require the other groups to be clean.
    @api.group_values.find { |group| group.id == 'production' }.has_access_to_all_builds = true
    assert_same @helper, @helper.prepare('dev')
  end
end
