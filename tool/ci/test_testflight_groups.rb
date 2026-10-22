# Deterministic tests for the real group coordinator; no Apple calls or credentials.
require 'minitest/autorun'
require 'ostruct'
require_relative 'testflight_groups'

class TestflightGroupsTest < Minitest::Test
  Build = Struct.new(:id, :app_id, :bundle_id, :platform, :app_version, :version,
                     :processing_state, :expired, :build_beta_detail, :internal_ready,
                     :external_ready, :compliance_missing, keyword_init: true) do
    def ready_for_internal_testing? = internal_ready
    def ready_for_external_testing? = external_ready
    def missing_export_compliance? = compliance_missing
  end

  class FakeAPI
    attr_accessor :app_value, :group_values, :snapshots, :failure, :assignment_visible, :already_assigned
    attr_reader :calls
    def initialize
      @calls = []
      @assignment_visible = true
      @already_assigned = false
    end
    def app = app_value
    def groups(*) = group_values
    def builds(app, version, number)
      @calls << [:query, app.id, version, number]
      snapshots.length > 1 ? snapshots.shift : snapshots.first
    end
    def assign(build, group)
      raise 'private API response must not leak' if failure
      @calls << [:assign, build.id, group.id]
      @assigned = true
    end
    def assigned?(*args)
      already_assigned || (@assigned && assignment_visible)
    end
  end

  def setup
    @api = FakeAPI.new
    @api.app_value = OpenStruct.new(id: 'production-app', bundle_id: OrangeoneTestflight::BUNDLE_ID)
    @api.group_values = OrangeoneTestflight::GROUPS.map do |key, name|
      OpenStruct.new(id: key, name: name, is_internal_group: true, has_access_to_all_builds: false)
    end
    @build = Build.new(id: 'exact-build', app_id: 'production-app', bundle_id: OrangeoneTestflight::BUNDLE_ID,
                       platform: 'IOS', app_version: '1.0.0', version: '25', processing_state: 'VALID',
                       expired: false, build_beta_detail: true, internal_ready: true, external_ready: false,
                       compliance_missing: false)
    @api.snapshots = [[@build]]
    @time = 0
    @helper = OrangeoneTestflight.new(api: @api, clock: -> { @time },
                                     sleeper: ->(seconds) { @time += seconds }, timeout: 30, interval: 10)
  end

  def distribute(target = 'production')
    @helper.prepare(target).distribute(version: '1.0.0', number: '25')
  end

  def assignments = @api.calls.select { |call| call.first == :assign }

  def test_all_allowlisted_groups_receive_only_the_exact_production_build
    OrangeoneTestflight::GROUPS.each_key do |target|
      setup
      assert_equal 'exact-build', distribute(target)
      assert_equal [[:assign, 'exact-build', target]], assignments
      assert_equal [:query, 'production-app', '1.0.0', '25'], @api.calls.first
    end
  end

  def test_arbitrary_names_ids_empty_and_unknown_inputs_rejected
    ['', 'development', 'Dev Testers', 'group-id', 'production;bad', nil].each do |target|
      assert_raises(OrangeoneTestflight::Error) { @helper.prepare(target) }
    end
    assert_empty @api.calls
  end

  def test_missing_ambiguous_automatic_or_ineligible_groups_fail_preflight
    group = @api.group_values.first
    [[], [group, group], [OpenStruct.new(group.to_h.merge(has_access_to_all_builds: true))],
     [OpenStruct.new(group.to_h.merge(is_internal_group: nil))]].each do |groups|
      @api.group_values = groups
      assert_raises(OrangeoneTestflight::Error) { @helper.prepare('dev') }
    end
    assert_empty assignments
  end

  def test_missing_or_wrong_production_app_fails_preflight
    [nil, OpenStruct.new(id: 'other', bundle_id: 'ch.orangepos.productscanner.dev')].each do |app|
      @api.app_value = app
      assert_raises(OrangeoneTestflight::Error) { @helper.prepare('dev') }
    end
  end

  def test_processing_delays_never_select_unrelated_latest_build
    unrelated = Build.new(**@build.to_h.merge(id: 'newest', version: '99'))
    processing = Build.new(**@build.to_h.merge(processing_state: 'PROCESSING'))
    @api.snapshots = [[], [unrelated], [processing], [@build]]
    # Four probes within a bounded fake deadline.
    @helper = OrangeoneTestflight.new(api: @api, clock: -> { @time },
                                     sleeper: ->(seconds) { @time += seconds }, timeout: 60, interval: 10)
    assert_equal 'exact-build', distribute('staging')
    assert_equal [[:assign, 'exact-build', 'staging']], assignments
    assert_equal 30, @time
  end

  def test_timeout_missing_build_or_never_ready_does_not_assign
    [[], [Build.new(**@build.to_h.merge(internal_ready: false))]].each do |snapshot|
      setup
      @api.snapshots = [snapshot]
      assert_raises(OrangeoneTestflight::Error) { distribute }
      assert_empty assignments
      assert_equal 30, @time
    end
  end

  def test_wrong_app_platform_version_or_bundle_cannot_match
    [{app_id: 'other'}, {platform: 'MAC_OS'}, {app_version: '2.0.0'},
     {bundle_id: 'ch.orangepos.productscanner.dev'}].each do |change|
      setup
      @api.snapshots = [[Build.new(**@build.to_h.merge(change))]]
      assert_raises(OrangeoneTestflight::Error) { distribute }
      assert_empty assignments
    end
  end

  def test_invalid_expired_ambiguous_or_changed_build_rejected
    [{processing_state: 'FAILED'}, {processing_state: 'INVALID'}, {expired: true},
     {compliance_missing: true}].each do |change|
      setup
      @api.snapshots = [[Build.new(**@build.to_h.merge(change))]]
      assert_raises(OrangeoneTestflight::Error) { distribute }
      assert_empty assignments
    end
    setup
    @api.snapshots = [[@build, @build]]
    assert_raises(OrangeoneTestflight::Error) { distribute }
    setup
    @api.snapshots = [[Build.new(**@build.to_h.merge(processing_state: 'PROCESSING'))],
                      [Build.new(**@build.to_h.merge(id: 'changed'))]]
    assert_raises(OrangeoneTestflight::Error) { distribute }
    assert_empty assignments
  end

  def test_assignment_failure_is_fatal_and_sanitized
    @api.failure = true
    error = assert_raises(OrangeoneTestflight::Error) { distribute }
    refute_includes error.message, 'private API response'
    assert_nil error.cause
  end

  def test_external_detail_processing_delay_is_not_mistaken_for_review_rejection
    @api.group_values.last.is_internal_group = false
    @api.snapshots = [[Build.new(**@build.to_h.merge(build_beta_detail: nil))],
                      [Build.new(**@build.to_h.merge(external_ready: true))]]
    assert_equal 'exact-build', distribute
    assert_equal 10, @time
  end

  def test_group_removed_or_replaced_after_upload_is_rejected
    @helper.prepare('dev')
    @api.group_values = [OpenStruct.new(id: 'new-id', name: 'Dev Testers',
                                       is_internal_group: true, has_access_to_all_builds: false)]
    assert_raises(OrangeoneTestflight::Error) { @helper.distribute(version: '1.0.0', number: '25') }
    assert_empty assignments
    @api.group_values = []
    assert_raises(OrangeoneTestflight::Error) { @helper.distribute(version: '1.0.0', number: '25') }
    assert_empty assignments
  end

  def test_adapter_posts_only_selected_group_and_checks_exact_build_id
    adapter = OrangeoneTestflight::AppleAPI.new
    group = OpenStruct.new(id: 'dev')
    build = OpenStruct.new(id: 'exact-build')
    received = nil
    build.define_singleton_method(:add_beta_groups) { |**args| received = args }
    adapter.assign(build, group)
    assert_equal({ beta_groups: [group] }, received)
    group.define_singleton_method(:fetch_builds) { [OpenStruct.new(id: 'unrelated')] }
    refute adapter.assigned?(build, group)
    group.define_singleton_method(:fetch_builds) { [build] }
    assert adapter.assigned?(build, group)
  end

  def test_adapter_queries_the_production_app_and_explicit_ios_version_build
    # Supply only the two Spaceship model entry points used by the adapter.
    # Actual HTTP integration remains a hosted verification step.
    calls = []
    namespace = Module.new
    client = Class.new
    apps = Class.new
    builds = Class.new
    apps.define_singleton_method(:find) { |bundle| calls << [:app, bundle] }
    builds.define_singleton_method(:all) { |**args| calls << [:builds, args] }
    client.const_set(:App, apps)
    client.const_set(:Build, builds)
    namespace.const_set(:ConnectAPI, client)
    Object.const_set(:Spaceship, namespace)
    adapter = OrangeoneTestflight::AppleAPI.new
    adapter.app
    adapter.builds(@api.app_value, '1.0.0', '25')
    assert_equal [:app, 'ch.orangepos.productscanner'], calls.first
    assert_equal [:builds, {app_id: 'production-app', version: '1.0.0', build_number: '25', platform: 'IOS'}], calls.last
  ensure
    Object.send(:remove_const, :Spaceship) if namespace && Object.const_defined?(:Spaceship) && Object.const_get(:Spaceship).equal?(namespace)
  end

  def test_unconfirmed_assignment_fails_without_repeating_mutation
    @api.assignment_visible = false
    assert_raises(OrangeoneTestflight::Error) { distribute }
    assert_equal [[:assign, 'exact-build', 'production']], assignments
  end

  def test_existing_assignment_is_idempotent
    @api.already_assigned = true
    assert_equal 'exact-build', distribute
    assert_empty assignments
  end

  def test_external_group_requires_existing_beta_review_eligibility
    @api.group_values.last.is_internal_group = false
    error = assert_raises(OrangeoneTestflight::Error) { distribute }
    assert_includes error.message, 'Beta App Review'
    assert_empty assignments
    @build.external_ready = true
    assert_equal 'exact-build', distribute
    assert_equal [[:assign, 'exact-build', 'production']], assignments
  end
end
