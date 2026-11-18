# Deterministic tests for the phased-release helper; no Apple calls or credentials.
require 'minitest/autorun'
require 'ostruct'
require_relative 'phased_release'

# The pinned deliver itself (pure Ruby, no Apple calls) for the regression below.
fastlane = Gem::Specification.find_by_name('fastlane', '= 2.241.1')
require File.join(fastlane.full_gem_path, 'deliver/lib/deliver/upload_metadata')

class PhasedReleaseTest < Minitest::Test
  class FakeAPI
    attr_accessor :app_value, :edit, :existing, :creatable, :failure
    attr_reader :calls

    def initialize
      @calls = []
      @creatable = true
    end

    def app = app_value

    def ensure_version(app, version)
      raise 'private API response must not leak' if failure == :ensure
      @calls << [:ensure, app.id, version]
    end

    def edit_version(_app) = edit

    def phased_release(version)
      @calls << [:read, version.id]
      existing
    end

    def create_phased_release(version)
      raise 'private API response must not leak' if failure == :create
      @calls << [:create, version.id]
      self.existing = OpenStruct.new(phased_release_state: 'INACTIVE') if creatable
    end
  end

  def setup
    @api = FakeAPI.new
    @api.app_value = OpenStruct.new(id: 'production-app', bundle_id: OrangeoneTestflight::BUNDLE_ID)
    @api.edit = OpenStruct.new(id: 'version-1', version_string: '1.2.0', platform: 'IOS')
    @helper = OrangeonePhasedRelease.new(api: @api)
  end

  def enable = @helper.enable(version: '1.2.0')
  def creates = @api.calls.select { |call| call.first == :create }

  def test_creates_it_for_the_exact_version_and_reads_it_back
    assert_equal 'INACTIVE', enable
    assert_equal [[:ensure, 'production-app', '1.2.0'], [:read, 'version-1'],
                  [:create, 'version-1'], [:read, 'version-1']], @api.calls
  end

  def test_an_existing_phased_release_is_kept_and_confirmed
    %w[INACTIVE ACTIVE PAUSED].each do |state|
      setup
      @api.existing = OpenStruct.new(phased_release_state: state)
      assert_equal state, enable
      assert_empty creates
    end
  end

  def test_a_create_that_cannot_be_read_back_fails
    @api.creatable = false
    error = assert_raises(OrangeonePhasedRelease::Error) { enable }
    assert_includes error.message, 'could not be confirmed'
  end

  def test_a_finished_phased_release_is_not_a_confirmation
    @api.existing = OpenStruct.new(phased_release_state: 'COMPLETE')
    assert_raises(OrangeonePhasedRelease::Error) { enable }
  end

  def test_another_version_or_platform_is_never_changed
    [{ version_string: '1.1.0' }, { platform: 'MAC_OS' }].each do |change|
      setup
      @api.edit = OpenStruct.new(@api.edit.to_h.merge(change))
      assert_raises(OrangeonePhasedRelease::Error) { enable }
      assert_empty creates
    end
    setup
    @api.edit = nil
    assert_raises(OrangeonePhasedRelease::Error) { enable }
  end

  def test_wrong_app_or_invalid_version_stops_before_any_change
    @api.app_value = OpenStruct.new(id: 'other', bundle_id: 'ch.example.other')
    assert_raises(OrangeonePhasedRelease::Error) { enable }
    assert_raises(OrangeonePhasedRelease::Error) { @helper.enable(version: '1.2') }
    assert_empty @api.calls
  end

  def test_api_errors_are_reported_without_their_details
    %i[ensure create].each do |stage|
      setup
      @api.failure = stage
      error = assert_raises(OrangeonePhasedRelease::Error) { enable }
      refute_includes error.message, 'private API response'
    end
  end

  # Why the helper exists: with skip_metadata the pinned deliver returns from
  # its metadata upload before the phased-release step, so the phased_release
  # option never reaches App Store Connect. If a fastlane upgrade changes
  # this, revisit the submit lane.
  def test_pinned_deliver_ignores_phased_release_when_metadata_is_skipped
    touched = []
    version = Object.new
    %i[fetch_app_store_version_phased_release create_app_store_version_phased_release].each do |name|
      version.define_singleton_method(name) { |**| touched << name }
    end
    upload = Deliver::UploadMetadata.new({ skip_metadata: true, phased_release: true })
    upload.define_singleton_method(:fetch_edit_app_store_version) { |*| version }
    assert_nil upload.upload
    assert_empty touched
  end
end
