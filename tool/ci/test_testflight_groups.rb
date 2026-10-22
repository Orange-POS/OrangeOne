# Deterministic tests for the real group coordinator; no Apple calls or credentials.
require 'minitest/autorun'
require 'ostruct'
require_relative 'testflight_groups'

# Load the actual pinned model and its mapping module, not a fake readiness API.
# These pure model files perform no authentication or network calls.
fastlane = Gem::Specification.find_by_name('fastlane', '= 2.241.1')
require File.join(fastlane.full_gem_path, 'spaceship/lib/spaceship/connect_api/models/build_beta_detail')

class TestflightGroupsTest < Minitest::Test
  Build = Struct.new(:id, :app_id, :bundle_id, :platform, :app_version, :version,
                     :processing_state, :expired, :build_beta_detail, keyword_init: true) do
    def ready_for_internal_testing? = build_beta_detail && build_beta_detail.ready_for_internal_testing?
    def missing_export_compliance? = build_beta_detail && build_beta_detail.missing_export_compliance?
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
    def assigned?(build, group)
      @calls << [:read_back, build.id, group.id]
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
                       expired: false, build_beta_detail: detail)
    @api.snapshots = [[@build]]
    @time = 0
    @helper = OrangeoneTestflight.new(api: @api, clock: -> { @time },
                                     sleeper: ->(seconds) { @time += seconds }, timeout: 30, interval: 10)
  end

  def detail(internal: 'READY_FOR_BETA_TESTING', external: 'READY_FOR_BETA_SUBMISSION')
    Spaceship::ConnectAPI::BuildBetaDetail.new('detail', {
      'internalBuildState' => internal, 'externalBuildState' => external
    })
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
    [[], [Build.new(**@build.to_h.merge(build_beta_detail: detail(internal: 'PROCESSING')))]].each do |snapshot|
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
     {build_beta_detail: detail(external: 'MISSING_EXPORT_COMPLIANCE')}].each do |change|
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
                      [Build.new(**@build.to_h.merge(build_beta_detail: detail(external: 'BETA_APPROVED')))]]
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
    original_spaceship = Object.send(:remove_const, :Spaceship)
    Object.const_set(:Spaceship, namespace)
    adapter = OrangeoneTestflight::AppleAPI.new
    adapter.app
    adapter.builds(@api.app_value, '1.0.0', '25')
    assert_equal [:app, 'ch.orangepos.productscanner'], calls.first
    assert_equal [:builds, {app_id: 'production-app', version: '1.0.0', build_number: '25', platform: 'IOS'}], calls.last
  ensure
    Object.send(:remove_const, :Spaceship) if namespace && Object.const_defined?(:Spaceship) && Object.const_get(:Spaceship).equal?(namespace)
    Object.const_set(:Spaceship, original_spaceship) if original_spaceship
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

  def test_real_internal_already_testing_assignment_succeeds_without_wait_or_mutation
    OrangeoneTestflight::GROUPS.each_key do |target|
      setup
      @build.build_beta_detail = detail(internal: 'IN_BETA_TESTING')
      # The pinned predicate is false despite this being an active testing build.
      refute @build.ready_for_internal_testing?
      @api.already_assigned = true
      assert_equal 'exact-build', distribute(target)
      assert_equal 0, @time
      assert_empty assignments
      assert_equal [:read_back, 'exact-build', target], @api.calls.last
    end
  end

  def test_existing_assignment_is_consulted_before_waiting_for_initial_readiness
    @build.build_beta_detail = detail(internal: 'PROCESSING')
    @api.already_assigned = true
    assert_equal 'exact-build', distribute
    assert_equal 0, @time
    assert_empty assignments
  end

  def test_real_internal_already_testing_build_can_receive_another_selected_group
    @build.build_beta_detail = detail(internal: 'IN_BETA_TESTING')
    refute @build.ready_for_internal_testing?
    assert_equal 'exact-build', distribute('staging')
    assert_equal [[:assign, 'exact-build', 'staging']], assignments
    assert_equal [:read_back, 'exact-build', 'staging'], @api.calls.last
    assert_equal 0, @time
  end

  def test_internal_already_testing_unconfirmed_assignment_never_repeats_mutation
    @build.build_beta_detail = detail(internal: 'IN_BETA_TESTING')
    @api.assignment_visible = false
    assert_raises(OrangeoneTestflight::Error) { distribute('dev') }
    assert_equal [[:assign, 'exact-build', 'dev']], assignments
    assert_equal 30, @time
  end

  def test_existing_assignment_does_not_bypass_invalid_builds_or_internal_compliance
    changes = [{expired: true}, {processing_state: 'INVALID'}, {processing_state: 'FAILED'}]
    %w[EXPIRED PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE IN_EXPORT_COMPLIANCE_REVIEW UNKNOWN].each do |state|
      changes << {build_beta_detail: detail(internal: state)}
    end
    changes.each do |change|
      setup
      @api.already_assigned = true
      @api.snapshots = [[Build.new(**@build.to_h.merge(change))]]
      assert_raises(OrangeoneTestflight::Error) { distribute }
      assert_empty assignments
      refute @api.calls.any? { |call| call.first == :read_back }
    end
  end

  def test_existing_assignment_does_not_bypass_wrong_identity_or_changed_group
    setup
    @api.already_assigned = true
    @build.version = '99'
    assert_raises(OrangeoneTestflight::Error) { distribute }
    refute @api.calls.any? { |call| call.first == :read_back }
    setup
    @api.already_assigned = true
    @helper.prepare('dev')
    @api.group_values = [OpenStruct.new(id: 'changed', name: 'Dev Testers',
                                       is_internal_group: true, has_access_to_all_builds: false)]
    assert_raises(OrangeoneTestflight::Error) { @helper.distribute(version: '1.0.0', number: '25') }
    refute @api.calls.any? { |call| call.first == :read_back }
    assert_empty assignments
  end

  def test_external_group_requires_existing_beta_review_eligibility
    @api.group_values.last.is_internal_group = false
    error = assert_raises(OrangeoneTestflight::Error) { distribute }
    assert_includes error.message, 'Beta App Review'
    assert_empty assignments
    @build.build_beta_detail.external_build_state = 'BETA_APPROVED'
    assert_equal 'exact-build', distribute
    assert_equal [[:assign, 'exact-build', 'production']], assignments
  end

  def test_real_pinned_detail_supports_approved_ready_and_already_testing_states
    %w[BETA_APPROVED READY_FOR_BETA_TESTING IN_BETA_TESTING].each do |state|
      OrangeoneTestflight::GROUPS.each_key do |target|
        setup
        @api.group_values.find { |group| group.id == target }.is_internal_group = false
        @build.build_beta_detail = detail(external: state)
        assert_instance_of Spaceship::ConnectAPI::BuildBetaDetail, @build.build_beta_detail
        # The previous fake supplied this nonexistent dependency method and hid the bug.
        refute_respond_to @build.build_beta_detail, :ready_for_external_testing?
        refute_respond_to @build, :ready_for_external_testing?
        assert_equal 'exact-build', distribute(target)
        assert_equal [[:assign, 'exact-build', target]], assignments
        assert_equal [:read_back, 'exact-build', target], @api.calls.last
      end
    end
  end

  def test_real_external_processing_and_missing_state_wait_within_deadline
    [nil, 'PROCESSING'].each do |state|
      setup
      @api.group_values.last.is_internal_group = false
      @api.snapshots = [[Build.new(**@build.to_h.merge(build_beta_detail: detail(external: state)))],
                        [Build.new(**@build.to_h.merge(build_beta_detail: detail(external: 'BETA_APPROVED')))]]
      assert_equal 'exact-build', distribute
      assert_equal 10, @time
      assert_equal [[:assign, 'exact-build', 'production']], assignments
    end
    setup
    @api.group_values.last.is_internal_group = false
    @build.build_beta_detail = detail(external: 'PROCESSING')
    error = assert_raises(OrangeoneTestflight::Error) { distribute }
    assert_includes error.message, 'Timed out'
    assert_equal 30, @time
    assert_empty assignments
  end

  def test_real_external_review_compliance_and_terminal_failures_are_actionable
    {
      'READY_FOR_BETA_SUBMISSION' => 'manual Beta App Review',
      'WAITING_FOR_BETA_REVIEW' => 'Beta App Review is pending',
      'IN_BETA_REVIEW' => 'Beta App Review is pending',
      'BETA_REJECTED' => 'Beta App Review rejected',
      'MISSING_EXPORT_COMPLIANCE' => 'export compliance',
      'IN_EXPORT_COMPLIANCE_REVIEW' => 'export compliance',
      'PROCESSING_EXCEPTION' => 'failed',
      'EXPIRED' => 'expired',
      'UNRECOGNIZED_STATE' => 'Unrecognized external build state'
    }.each do |state, message|
      setup
      @api.group_values.last.is_internal_group = false
      @build.build_beta_detail = detail(external: state)
      error = assert_raises(OrangeoneTestflight::Error) { distribute }
      assert_includes error.message, message
      assert_empty assignments
      assert_equal 0, @time
      assert @api.calls.all? { |call| call.first == :query }
    end
  end

  def test_pinned_external_state_vocabulary_is_fully_accounted_for
    states = Spaceship::ConnectAPI::BuildBetaDetail::ExternalState
    assert_equal %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE
                    READY_FOR_BETA_TESTING IN_BETA_TESTING EXPIRED READY_FOR_BETA_SUBMISSION
                    IN_EXPORT_COMPLIANCE_REVIEW WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW
                    BETA_REJECTED BETA_APPROVED].sort,
                 states.constants.map { |name| states.const_get(name) }.sort
  end
end
