# Trusted-main helper: turn on phased release for the exact App Store version
# before it is submitted for review.
#
# The submit lane must not change metadata, so it runs deliver with
# skip_metadata: true. In the pinned fastlane 2.241.1, deliver applies its
# phased_release option inside the metadata upload, which returns at once when
# metadata is skipped, so the option alone would never take effect. This helper
# uses the same Spaceship calls deliver uses (ensure_version!, then the
# version's phased release) and reads the setting back before submission.
require_relative 'testflight_groups'

class OrangeonePhasedRelease
  class Error < StandardError; end

  PLATFORM = 'IOS'
  # A phased release that exists and has not finished. INACTIVE starts with
  # the manual release; ACTIVE or PAUSED means it is already rolling out.
  CONFIRMED_STATES = %w[INACTIVE ACTIVE PAUSED].freeze

  # No dependency on Spaceship until used on the protected signing runner.
  class AppleAPI
    def app
      Spaceship::ConnectAPI::App.find(OrangeoneTestflight::BUNDLE_ID)
    end

    # The same call deliver makes before submission; it creates or renames the
    # editable version and leaves an already matching version unchanged.
    def ensure_version(app, version)
      app.ensure_version!(version, platform: PLATFORM)
    end

    def edit_version(app)
      app.get_edit_app_store_version(platform: PLATFORM)
    end

    def phased_release(version)
      version.fetch_app_store_version_phased_release
    rescue StandardError
      # App Store Connect answers "no data" when the version has none.
      nil
    end

    def create_phased_release(version)
      version.create_app_store_version_phased_release(attributes: { phasedReleaseState: 'INACTIVE' })
    end
  end

  def initialize(api: AppleAPI.new)
    @api = api
  end

  # Enables phased release for [version] and returns the confirmed state.
  def enable(version:)
    raise Error, 'Invalid App Store version.' unless version.to_s.match?(/\A\d+\.\d+\.\d+\z/)

    app = request { @api.app }
    raise Error, 'Production App Store Connect app was not found.' unless app && app.bundle_id == OrangeoneTestflight::BUNDLE_ID

    request { @api.ensure_version(app, version) }
    edit = request { @api.edit_version(app) }
    unless edit && edit.version_string == version && edit.platform == PLATFORM
      raise Error, "The editable App Store version is not #{version}; phased release was not changed."
    end

    request { @api.create_phased_release(edit) } unless @api.phased_release(edit)
    state = @api.phased_release(edit)&.phased_release_state
    return state if CONFIRMED_STATES.include?(state)

    raise Error, "Phased release for #{version} could not be confirmed in App Store Connect; nothing was submitted."
  end

  private

  def request
    yield
  rescue Error
    raise
  rescue StandardError
    # Never print API errors, responses or credentials.
    raise Error, 'App Store Connect phased-release request failed. Verify API access and the App Store version.', cause: nil
  end
end
