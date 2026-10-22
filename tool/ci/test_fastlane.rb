# Evaluate the real Fastfile with recording actions; model tests never call Apple services.
require 'minitest/autorun'
require_relative 'test_testflight_groups'

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
  def test_missing_or_ambiguous_ipa_never_uploads
    [[], ['one.ipa', 'two.ipa']].each do |paths|
      Dir.stub(:[], proc { paths }) do
        assert_raises(ArgumentError) { run_beta }
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
