# Evaluate the real Fastfile with recording actions; model tests never call Apple services.
require 'minitest/autorun'
require 'minitest/mock'
require 'tempfile'
require_relative 'test_testflight_groups'
require_relative 'test_testflight_build_number'

class FastfileHarness
  attr_reader :lanes, :calls
  def initialize
    @lanes = {}
    @calls = []
  end
  def default_platform(*) = nil
  def desc(*) = nil
  def platform(*) = yield
  def lane(name, &block) = @lanes[name] = block
  def app_store_connect_api_key(**options)
    @calls << [:key, options]
    { fixture: true }
  end
  def update_code_signing_settings(**options) = @calls << [:signing, options]
  def sh(*arguments)
    @calls << [:export, arguments]
  end
  def build_app(**options)
    @calls << [:build, options]
    'fixture.ipa'
  end
  def upload_to_testflight(**options) = @calls << [:testflight, options]
  def upload_to_app_store(**options) = @calls << [:submit, options]
end

module UI
  def self.success(message) = nil
  def self.important(message) = nil
  def self.user_error!(message) = raise(ArgumentError, message)
end

class FastfileTest < Minitest::Test
  def test_frozen_bundle_has_current_lockfile_and_exact_fastlane_pin
    require 'bundler'
    root = File.expand_path('../..', __dir__)
    lockfile = File.join(root, 'Gemfile.lock')
    assert File.file?(lockfile), 'Frozen CI installation requires Gemfile.lock'
    parser = Bundler::LockfileParser.new(File.read(lockfile))
    assert_equal '= 2.241.1', parser.dependencies.fetch('fastlane').requirement.to_s
    assert_equal ['2.241.1'], parser.specs.select { |spec| spec.name == 'fastlane' }.map { |spec| spec.version.to_s }.uniq
    Dir.chdir(root) { Bundler.definition.ensure_equivalent_gemfile_and_lockfile }
    %w[x86_64-linux arm64-darwin x86_64-darwin].each do |platform|
      assert_includes parser.platforms.map(&:to_s), platform
    end
  end

  def setup
    @previous = ENV.to_h
    ENV.delete('RELEASE_FLAVOR')
    ENV.delete('TARGET_GROUP')
    ENV.update('GITHUB_REF' => 'refs/heads/main', 'GITHUB_EVENT_NAME' => 'workflow_dispatch',
               'APP_STORE_CONNECT_KEY_ID' => 'fixture', 'APP_STORE_CONNECT_ISSUER_ID' => 'fixture',
               'APP_STORE_CONNECT_KEY_FILE' => 'fixture.p8', 'APPLE_TEAM_ID' => 'ABC123DE45',
               'IOS_PROFILE_UUID' => 'fixture-uuid', 'IOS_PROFILE_NAME' => 'fixture-profile',
               'RELEASE_VERSION' => '1.0.0', 'RELEASE_BUILD_NUMBER' => '12',
               'PR_NUMBER' => '', 'SOURCE_SHA' => 'a' * 40)
    @harness = FastfileHarness.new
    file = File.expand_path('../../fastlane/Fastfile', __dir__)
    @harness.instance_eval(File.read(file), file)
    @distribution = Object.new
    calls = @harness.calls
    @distribution.define_singleton_method(:prepare) { |target| calls << [:prepare, target]; self }
    @distribution.define_singleton_method(:distribute) { |**values| calls << [:assign, values] }
    @ipa_stub = proc { ['fixture.ipa'] }
  end
  def run_beta
    OrangeoneTestflight.stub(:new, @distribution) { @harness.lanes[:beta].call }
  end
  def teardown
    ENV.replace(@previous)
  end
  def test_nonmain_or_automatic_runs_cannot_distribute
    ENV['GITHUB_REF'] = 'refs/heads/feature'
    assert_raises(ArgumentError) { run_beta }
    ENV['GITHUB_REF'] = 'refs/heads/main'
    ENV['GITHUB_EVENT_NAME'] = 'push'
    assert_raises(ArgumentError) { run_beta }
    assert_empty @harness.calls
  end
  def test_submit_rejects_nonmain_and_nonmanual_before_loading_key
    ENV['IPHONE_SMOKE_TEST_CONFIRMED'] = 'true'
    ENV['GITHUB_REF'] = 'refs/heads/feature'
    assert_raises(ArgumentError) { @harness.lanes[:submit].call }
    ENV['GITHUB_REF'] = 'refs/heads/main'
    ENV['GITHUB_EVENT_NAME'] = 'workflow_run'
    assert_raises(ArgumentError) { @harness.lanes[:submit].call }
    assert_empty @harness.calls
  end
  def test_beta_exports_selected_pr_without_rebuilding_and_uploads_internal_testflight
    ENV['PR_NUMBER'] = '42'
    Dir.stub(:[], @ipa_stub) { run_beta }
    command = @harness.calls.assoc(:export).last
    assert_equal 'python3', command.first
    assert command.last.end_with?('/tool/ci/export_ipa.py')
    refute @harness.calls.assoc(:build)
    refute @harness.calls.assoc(:signing)
    upload = @harness.calls.assoc(:testflight).last
    assert_equal 'ch.orangepos.productscanner', upload[:app_identifier]
    assert_equal 'fixture.ipa', upload[:ipa]
    assert_equal '1.0.0', upload[:app_version]
    assert_equal '12', upload[:build_number]
    assert upload[:skip_submission]
    refute upload[:submit_beta_review]
    assert_equal [:assign, { version: '1.0.0', number: '12' }], @harness.calls.last
    refute upload[:distribute_external]
    assert upload[:skip_waiting_for_build_processing]
    refute @harness.calls.assoc(:submit)
  end
  def test_ipa_discovery_is_repository_relative_from_fastlane_directory
    expected = File.expand_path('../../build/ios/ipa/*.ipa', __dir__)
    checked = []
    Dir.chdir(File.expand_path('../../fastlane', __dir__)) do
      Dir.stub(:[], proc { |pattern| checked << pattern; ['fixture.ipa'] }) { run_beta }
    end
    assert_equal [expected], checked
    assert @harness.calls.assoc(:testflight)
  end
  def test_missing_or_ambiguous_ipa_never_uploads
    [[], ['one.ipa', 'two.ipa']].each do |paths|
      Dir.stub(:[], proc { paths }) do
        error = assert_raises(ArgumentError) { run_beta }
        assert_includes error.message, "found #{paths.length} candidate(s)"
        assert_includes error.message, File.expand_path('../../build/ios/ipa', __dir__)
      end
      refute @harness.calls.assoc(:testflight)
    end
  end
  def test_failed_export_never_uploads
    @harness.define_singleton_method(:sh) { |*| raise 'synthetic export failure' }
    assert_raises(RuntimeError) { run_beta }
    refute @harness.calls.assoc(:testflight)
  end
  def test_all_groups_upload_only_production_without_rebuilding
    { 'dev' => 'Dev Testers', 'staging' => 'Staging Testers', 'production' => 'Production Testers' }.each do |target, name|
      ENV['TARGET_GROUP'] = target
      @harness.calls.clear
      Dir.stub(:[], @ipa_stub) { run_beta }
      assert_equal name, OrangeoneTestflight.group_name(target)
      assert_equal 'ch.orangepos.productscanner', @harness.calls.assoc(:testflight).last[:app_identifier]
      assert_equal [:prepare, target], @harness.calls.assoc(:prepare)
      refute @harness.calls.assoc(:build)
      refute @harness.calls.assoc(:submit)
    end
  end
  def test_group_errors_fail_the_lane
    ENV['TARGET_GROUP'] = 'unknown'
    assert_raises(ArgumentError) { run_beta }
    assert_empty @harness.calls
    ENV['TARGET_GROUP'] = 'dev'
    @distribution.define_singleton_method(:prepare) { |*| raise OrangeoneTestflight::Error, 'Missing group' }
    assert_raises(ArgumentError) { run_beta }
    refute @harness.calls.assoc(:testflight)
  end
  def test_assignment_failure_after_upload_fails_lane
    @distribution.define_singleton_method(:distribute) { |**| raise OrangeoneTestflight::Error, 'Assignment failed' }
    Dir.stub(:[], @ipa_stub) { assert_raises(ArgumentError) { run_beta } }
    assert @harness.calls.assoc(:testflight)
    refute @harness.calls.assoc(:submit)
  end
  def test_nonproduction_submission_and_unknown_flavor_fail_before_key_loading
    ENV['IPHONE_SMOKE_TEST_CONFIRMED'] = 'true'
    ['development', 'staging', 'unknown', ''].each do |flavor|
      ENV['RELEASE_FLAVOR'] = flavor
      assert_raises(ArgumentError) { @harness.lanes[:submit].call }
      assert_empty @harness.calls
    end
    ENV['RELEASE_FLAVOR'] = 'unknown'
    assert_raises(ArgumentError) { run_beta }
    assert_empty @harness.calls
  end
  def run_existing
    OrangeoneTestflight.stub(:new, @distribution) { @harness.lanes[:distribute_existing].call }
  end
  def test_existing_distribution_all_groups_never_export_sign_upload_or_submit
    %w[dev staging production].each do |target|
      ENV['TARGET_GROUP'] = target
      ENV['RELEASE_VERSION'] = '1.0.6'
      ENV['RELEASE_BUILD_NUMBER'] = '33'
      @harness.calls.clear
      success = []
      UI.stub(:success, proc { |message| success << message }) { run_existing }
      assert_equal [:prepare, target], @harness.calls.assoc(:prepare)
      assert_equal [:assign, { version: '1.0.6', number: '33' }], @harness.calls.last
      assert_equal [:key, :prepare, :assign], @harness.calls.map(&:first)
      assert_equal 1, success.length
    end
  end
  def test_existing_distribution_accepts_whitespace_only_pr_number
    ["   ", "\t \n"].each do |number|
      ENV['PR_NUMBER'] = number
      @harness.calls.clear
      run_existing
      assert_equal [:key, :prepare, :assign], @harness.calls.map(&:first)
    end
  end
  def test_existing_distribution_failure_never_reports_success
    @distribution.define_singleton_method(:distribute) { |**| raise OrangeoneTestflight::Error, 'Compliance pending' }
    success = []
    UI.stub(:success, proc { |message| success << message }) do
      assert_raises(ArgumentError) { run_existing }
    end
    assert_empty success
    refute @harness.calls.assoc(:testflight)
    refute @harness.calls.assoc(:submit)
  end
  def test_existing_distribution_is_manual_main_production_and_has_no_pr
    [ ['GITHUB_REF', 'refs/heads/feature'], ['GITHUB_EVENT_NAME', 'push'],
      ['RELEASE_FLAVOR', 'development'], ['RELEASE_FLAVOR', 'staging'],
      ['PR_NUMBER', '42'], ['PR_NUMBER', ' 42 '], ['TARGET_GROUP', 'unknown'] ].each do |key, value|
      previous = ENV[key]
      ENV[key] = value
      assert_raises(ArgumentError) { run_existing }
      assert_empty @harness.calls
      if previous.nil?
        ENV.delete(key)
      else
        ENV[key] = previous
      end
    end
  end
  def test_submit_requires_iphone_attestation_and_does_not_rebuild_or_release
    ENV['IPHONE_SMOKE_TEST_CONFIRMED'] = 'false'
    assert_raises(ArgumentError) { @harness.lanes[:submit].call }
    assert_empty @harness.calls
    ENV['IPHONE_SMOKE_TEST_CONFIRMED'] = 'true'
    @harness.lanes[:submit].call
    submit = @harness.calls.assoc(:submit).last
    assert_equal 'ch.orangepos.productscanner', submit[:app_identifier]
    assert_equal '1.0.0', submit[:app_version]
    assert_equal '12', submit[:build_number]
    assert submit[:skip_binary_upload]
    assert submit[:submit_for_review]
    refute submit[:automatic_release]
    refute @harness.calls.assoc(:build)
  end
end

# DEV/STG channel lanes: branch -> flavor -> one tester group, dry run by default.
class ChannelLaneTest < Minitest::Test
  def setup
    @previous = ENV.to_h
    ENV.delete('RELEASE_FLAVOR')
    ENV.update('GITHUB_REF' => 'refs/heads/develop', 'GITHUB_EVENT_NAME' => 'push',
               'CHANNEL_FLAVOR' => 'development', 'TARGET_GROUP' => 'dev', 'DRY_RUN' => 'true',
               'TESTFLIGHT_CD_ENABLED' => 'false', 'RELEASE_VERSION' => '1.1.0',
               'RELEASE_BUILD_NUMBER' => '36', 'BUILD_NUMBER_FLOOR' => '35',
               'APP_STORE_CONNECT_KEY_ID' => 'fixture', 'APP_STORE_CONNECT_ISSUER_ID' => 'fixture',
               'APP_STORE_CONNECT_KEY_FILE' => 'fixture.p8')
    ENV.delete('GITHUB_OUTPUT')
    @harness = FastfileHarness.new
    file = File.expand_path('../../fastlane/Fastfile', __dir__)
    @harness.instance_eval(File.read(file), file)
    calls = @harness.calls
    @distribution = Object.new
    @distribution.define_singleton_method(:prepare_channel) { |target| calls << [:prepare_channel, target]; self }
    @distribution.define_singleton_method(:distribute) { |**values| calls << [:assign, values] }
    @numbers = Object.new
    @numbers.define_singleton_method(:allocate) { |floor:| calls << [:allocate, floor]; floor + 1 }
    @numbers.define_singleton_method(:assert_unused) { |number:, floor:| calls << [:unused, number, floor]; true }
    @ipa_stub = proc { ['fixture.ipa'] }
  end

  def teardown
    ENV.replace(@previous)
  end

  def run_lane(name)
    OrangeoneTestflight.stub(:new, @distribution) do
      OrangeoneBuildNumber.stub(:new, @numbers) { @harness.lanes[name].call }
    end
  end

  def run_with_ipa(name)
    Dir.stub(:[], @ipa_stub) { run_lane(name) }
  end

  CHANNELS = { 'refs/heads/develop' => %w[development dev], 'refs/heads/staging' => %w[staging staging] }.freeze

  def use_channel(ref)
    flavor, group = CHANNELS.fetch(ref)
    ENV.update('GITHUB_REF' => ref, 'CHANNEL_FLAVOR' => flavor, 'TARGET_GROUP' => group)
    @harness.calls.clear
  end

  def test_only_develop_and_staging_pushes_or_dispatches_can_run_either_lane
    [['refs/heads/main', 'push'], ['refs/heads/feature/x', 'push'], ['refs/tags/v1.0.0', 'push'],
     ['refs/heads/develop', 'pull_request'], ['refs/heads/develop', 'release'],
     ['refs/heads/staging', 'workflow_run'], ['', 'push']].each do |ref, event|
      ENV.update('GITHUB_REF' => ref, 'GITHUB_EVENT_NAME' => event)
      %i[allocate_build testflight_channel].each do |lane|
        assert_raises(ArgumentError, "#{ref} #{event} #{lane}") { run_with_ipa(lane) }
      end
    end
    assert_empty @harness.calls
  end

  def test_flavor_group_and_signing_identity_must_match_the_branch
    [['CHANNEL_FLAVOR', 'staging'], ['CHANNEL_FLAVOR', 'production'], ['CHANNEL_FLAVOR', ''],
     ['TARGET_GROUP', 'staging'], ['TARGET_GROUP', 'production'], ['TARGET_GROUP', 'Dev Testers'],
     ['RELEASE_FLAVOR', 'development'], ['RELEASE_FLAVOR', 'staging']].each do |key, value|
      use_channel('refs/heads/develop')
      ENV[key] = value
      %i[allocate_build testflight_channel].each do |lane|
        assert_raises(ArgumentError, "#{key}=#{value} #{lane}") { run_with_ipa(lane) }
      end
      assert_empty @harness.calls, "#{key}=#{value}"
    end
  end

  def test_staging_branch_cannot_use_the_dev_group
    use_channel('refs/heads/staging')
    ENV['TARGET_GROUP'] = 'dev'
    assert_raises(ArgumentError) { run_with_ipa(:testflight_channel) }
    ENV['TARGET_GROUP'] = 'production'
    assert_raises(ArgumentError) { run_with_ipa(:testflight_channel) }
    assert_empty @harness.calls
  end

  def test_allocation_checks_the_groups_then_allocates_above_the_floor
    CHANNELS.each do |ref, (_, group)|
      use_channel(ref)
      assert_equal 36, run_lane(:allocate_build)
      assert_equal [:key, :prepare_channel, :allocate], @harness.calls.map(&:first)
      assert_equal [:prepare_channel, group], @harness.calls.assoc(:prepare_channel)
      assert_equal [:allocate, 35], @harness.calls.assoc(:allocate)
      refute @harness.calls.assoc(:testflight)
      refute @harness.calls.assoc(:export)
    end
  end

  def test_allocation_publishes_the_number_for_the_next_job
    Tempfile.create('github_output') do |file|
      ENV['GITHUB_OUTPUT'] = file.path
      run_lane(:allocate_build)
      assert_equal "build_number=36\n", File.read(file.path)
    end
  end

  def test_group_or_number_errors_stop_allocation
    @distribution.define_singleton_method(:prepare_channel) { |*| raise OrangeoneTestflight::Error, 'Group has automatic distribution' }
    assert_raises(ArgumentError) { run_lane(:allocate_build) }
    refute @harness.calls.assoc(:allocate)
    @distribution.define_singleton_method(:prepare_channel) { |*| self }
    @numbers.define_singleton_method(:allocate) { |**| raise OrangeoneBuildNumber::Error, 'No free number' }
    assert_raises(ArgumentError) { run_lane(:allocate_build) }
  end

  def test_dry_run_signs_and_verifies_but_never_uploads_or_assigns
    CHANNELS.each_key do |ref|
      use_channel(ref)
      success = []
      UI.stub(:success, proc { |message| success << message }) { run_with_ipa(:testflight_channel) }
      assert_equal [:key, :prepare_channel, :unused, :export], @harness.calls.map(&:first)
      refute @harness.calls.assoc(:testflight)
      refute @harness.calls.assoc(:assign)
      refute @harness.calls.assoc(:submit)
      assert_match(/Dry run/, success.last)
    end
  end

  def test_real_uploads_are_refused_until_the_repository_switch_is_on
    ENV['DRY_RUN'] = 'false'
    assert_raises(ArgumentError) { run_with_ipa(:testflight_channel) }
    assert_empty @harness.calls
  end

  def test_real_run_uploads_one_production_app_build_and_assigns_only_its_channel_group
    ENV.update('DRY_RUN' => 'false', 'TESTFLIGHT_CD_ENABLED' => 'true')
    CHANNELS.each do |ref, (_, group)|
      use_channel(ref)
      run_with_ipa(:testflight_channel)
      assert_equal [:key, :prepare_channel, :unused, :export, :testflight, :assign], @harness.calls.map(&:first)
      assert_equal [:prepare_channel, group], @harness.calls.assoc(:prepare_channel)
      upload = @harness.calls.assoc(:testflight).last
      assert_equal 'ch.orangepos.productscanner', upload[:app_identifier]
      assert_equal '1.1.0', upload[:app_version]
      assert_equal '36', upload[:build_number]
      assert upload[:skip_submission]
      refute upload[:submit_beta_review]
      refute upload[:distribute_external]
      refute upload[:notify_external_testers]
      assert_equal [:assign, { version: '1.1.0', number: '36' }], @harness.calls.last
      assert_equal 1, @harness.calls.count { |call| call.first == :assign }
      refute @harness.calls.assoc(:submit)
    end
  end

  def test_a_stale_build_number_stops_before_any_export_or_upload
    ENV.update('DRY_RUN' => 'false', 'TESTFLIGHT_CD_ENABLED' => 'true')
    @numbers.define_singleton_method(:assert_unused) { |**| raise OrangeoneBuildNumber::Error, 'Number no longer free' }
    assert_raises(ArgumentError) { run_with_ipa(:testflight_channel) }
    refute @harness.calls.assoc(:export)
    refute @harness.calls.assoc(:testflight)
  end

  def test_missing_or_ambiguous_ipa_and_failed_export_never_upload
    ENV.update('DRY_RUN' => 'false', 'TESTFLIGHT_CD_ENABLED' => 'true')
    [[], ['one.ipa', 'two.ipa']].each do |paths|
      Dir.stub(:[], proc { paths }) { assert_raises(ArgumentError) { run_lane(:testflight_channel) } }
      refute @harness.calls.assoc(:testflight)
    end
    @harness.define_singleton_method(:sh) { |*| raise 'synthetic export failure' }
    assert_raises(RuntimeError) { run_with_ipa(:testflight_channel) }
    refute @harness.calls.assoc(:testflight)
  end

  def use_release(tag = 'v1.2.0')
    ENV.update('GITHUB_REF' => "refs/tags/#{tag}", 'GITHUB_EVENT_NAME' => 'release',
               'CHANNEL_FLAVOR' => 'production', 'TARGET_GROUP' => 'production',
               'RELEASE_VERSION' => '1.2.0')
    @harness.calls.clear
  end

  def test_production_is_reachable_only_from_a_published_release_of_a_version_tag
    [['refs/tags/v1.2.0', 'push'], ['refs/tags/v1.2.0', 'workflow_dispatch'],
     ['refs/heads/main', 'release'], ['refs/heads/develop', 'release'],
     ['refs/tags/release-1', 'release'], ['refs/tags/v1.2', 'release'],
     ['refs/tags/v1.2.0-rc1', 'release']].each do |ref, event|
      use_release
      ENV.update('GITHUB_REF' => ref, 'GITHUB_EVENT_NAME' => event)
      %i[allocate_build testflight_channel].each do |lane|
        assert_raises(ArgumentError, "#{ref} #{event} #{lane}") { run_with_ipa(lane) }
      end
    end
    assert_empty @harness.calls
  end

  def test_a_release_run_is_production_only_and_checks_every_other_group
    use_release
    assert_equal 36, run_lane(:allocate_build)
    assert_equal [:prepare_channel, 'production'], @harness.calls.assoc(:prepare_channel)
    [['CHANNEL_FLAVOR', 'development'], ['TARGET_GROUP', 'dev'], ['TARGET_GROUP', 'staging']].each do |key, value|
      use_release
      ENV[key] = value
      assert_raises(ArgumentError, "#{key}=#{value}") { run_with_ipa(:testflight_channel) }
      assert_empty @harness.calls
    end
  end

  def test_a_release_dry_run_never_uploads
    use_release
    run_with_ipa(:testflight_channel)
    assert_equal [:key, :prepare_channel, :unused, :export], @harness.calls.map(&:first)
  end

  def test_a_pending_compliance_keeps_the_upload_and_reports_how_to_resume
    ENV.update('DRY_RUN' => 'false', 'TESTFLIGHT_CD_ENABLED' => 'true')
    @distribution.define_singleton_method(:distribute) do |**|
      raise OrangeoneTestflight::Pending, 'Complete export compliance for this exact build.'
    end
    Tempfile.create('summary') do |file|
      ENV['GITHUB_STEP_SUMMARY'] = file.path
      output, = capture_io { run_with_ipa(:testflight_channel) }
      assert_match(/::warning/, output)
      text = File.read(file.path)
      assert_includes text, 'uploaded but not yet in the dev group'
      assert_includes text, 'distribute_existing'
      assert_includes text, 'version 1.1.0, build 36'
      assert_includes text, 'without rebuilding or uploading'
    end
    assert_equal 1, @harness.calls.count { |call| call.first == :testflight }
    refute @harness.calls.assoc(:assign)
  ensure
    ENV.delete('GITHUB_STEP_SUMMARY')
  end

  def test_the_resume_lane_still_fails_while_compliance_is_pending
    ENV.update('GITHUB_REF' => 'refs/heads/main', 'GITHUB_EVENT_NAME' => 'workflow_dispatch',
               'TARGET_GROUP' => 'dev', 'RELEASE_BUILD_NUMBER' => '36')
    ENV.delete('PR_NUMBER')
    @distribution.define_singleton_method(:prepare) { |*| self }
    @distribution.define_singleton_method(:distribute) { |**| raise OrangeoneTestflight::Pending, 'pending' }
    assert_raises(ArgumentError) { run_lane(:distribute_existing) }
    refute @harness.calls.assoc(:testflight)
    refute @harness.calls.assoc(:export)
  end

  def test_a_group_or_assignment_failure_fails_the_lane
    ENV.update('DRY_RUN' => 'false', 'TESTFLIGHT_CD_ENABLED' => 'true')
    @distribution.define_singleton_method(:distribute) { |**| raise OrangeoneTestflight::Error, 'Assignment failed' }
    assert_raises(ArgumentError) { run_with_ipa(:testflight_channel) }
    assert @harness.calls.assoc(:testflight)
    refute @harness.calls.assoc(:submit)
  end

  def test_production_lanes_still_refuse_channel_branches
    %w[refs/heads/develop refs/heads/staging].each do |ref|
      ENV.update('GITHUB_REF' => ref, 'GITHUB_EVENT_NAME' => 'workflow_dispatch',
                 'RELEASE_VERSION' => '1.0.0', 'RELEASE_BUILD_NUMBER' => '12')
      ENV.delete('PR_NUMBER')
      %i[beta distribute_existing submit].each do |lane|
        assert_raises(ArgumentError) { OrangeoneTestflight.stub(:new, @distribution) { @harness.lanes[lane].call } }
      end
    end
    assert_empty @harness.calls
  end
end
