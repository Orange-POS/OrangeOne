# Evaluate the real Fastfile with recording actions; never load Fastlane or Apple services.
require 'minitest/autorun'

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
  def setup
    @previous = ENV.to_h
    ENV.update('GITHUB_REF' => 'refs/heads/main', 'GITHUB_EVENT_NAME' => 'workflow_dispatch',
               'APP_STORE_CONNECT_KEY_ID' => 'fixture', 'APP_STORE_CONNECT_ISSUER_ID' => 'fixture',
               'APP_STORE_CONNECT_KEY_FILE' => 'fixture.p8', 'APPLE_TEAM_ID' => 'ABC123DE45',
               'IOS_PROFILE_UUID' => 'fixture-uuid', 'IOS_PROFILE_NAME' => 'fixture-profile',
               'RELEASE_VERSION' => '1.0.0', 'RELEASE_BUILD_NUMBER' => '12',
               'PR_NUMBER' => '', 'SOURCE_SHA' => 'a' * 40)
    @harness = FastfileHarness.new
    file = File.expand_path('../../fastlane/Fastfile', __dir__)
    @harness.instance_eval(File.read(file), file)
    @ipa_stub = proc { ['fixture.ipa'] }
  end
  def teardown
    ENV.replace(@previous)
  end
  def test_nonmain_or_automatic_runs_cannot_distribute
    ENV['GITHUB_REF'] = 'refs/heads/feature'
    assert_raises(ArgumentError) { @harness.lanes[:beta].call }
    ENV['GITHUB_REF'] = 'refs/heads/main'
    ENV['GITHUB_EVENT_NAME'] = 'push'
    assert_raises(ArgumentError) { @harness.lanes[:beta].call }
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
    Dir.stub(:[], @ipa_stub) { @harness.lanes[:beta].call }
    command = @harness.calls.assoc(:export).last
    assert_equal 'python3', command.first
    assert command.last.end_with?('/tool/ci/export_ipa.py')
    refute @harness.calls.assoc(:build)
    refute @harness.calls.assoc(:signing)
    upload = @harness.calls.assoc(:testflight).last
    assert_equal 'ch.orangepos.productscanner', upload[:app_identifier]
    assert_equal 'fixture.ipa', upload[:ipa]
    assert_equal 'Production PR #42 @ ' + 'a' * 40, upload[:changelog]
    refute upload[:distribute_external]
    refute upload[:skip_waiting_for_build_processing]
    refute @harness.calls.assoc(:submit)
  end
  def test_missing_or_ambiguous_ipa_never_uploads
    [[], ['one.ipa', 'two.ipa']].each do |paths|
      Dir.stub(:[], proc { paths }) do
        assert_raises(ArgumentError) { @harness.lanes[:beta].call }
      end
      refute @harness.calls.assoc(:testflight)
    end
  end
  def test_failed_export_never_uploads
    @harness.define_singleton_method(:sh) { |*| raise 'synthetic export failure' }
    assert_raises(RuntimeError) { @harness.lanes[:beta].call }
    refute @harness.calls.assoc(:testflight)
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
