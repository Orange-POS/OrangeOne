# Trusted-main helper: allocate the next TestFlight build number from App Store
# Connect. One app serves the Dev, Staging and Production groups, so the number
# must be above every build the app already has, whatever its version or flavor.
require_relative 'testflight_groups'

class OrangeoneBuildNumber
  MAX = 9999
  class Error < StandardError; end

  class AppleAPI
    def app
      Spaceship::ConnectAPI::App.find(OrangeoneTestflight::BUNDLE_ID)
    end

    def builds(app)
      Spaceship::ConnectAPI::Build.all(app_id: app.id, platform: 'IOS')
    end
  end

  def initialize(api: AppleAPI.new)
    @api = api
  end

  # Highest numeric build number of the production app (0 when it has none).
  def highest
    app = request { @api.app }
    raise Error, 'Production App Store Connect app was not found.' unless app && app.bundle_id == OrangeoneTestflight::BUNDLE_ID
    request { @api.builds(app) }.filter_map { |build| Integer(build.version.to_s, 10, exception: false) }.max || 0
  end

  # Next free number: above App Store Connect and above [floor], the highest
  # number the repository ledger or pubspec already used.
  def allocate(floor:)
    number = [highest, Integer(floor)].max + 1
    raise Error, "Build numbers are limited to #{MAX}; reset the numbering deliberately." if number > MAX
    number
  end

  # A number allocated earlier is only valid while nothing newer was uploaded.
  def assert_unused(number:, floor:)
    latest = [highest, Integer(floor)].max
    return true if Integer(number) > latest
    raise Error, 'The allocated build number is no longer free; another upload used it. Run the workflow again.'
  end

  private

  def request
    yield
  rescue Error
    raise
  rescue StandardError
    # Never print API errors, responses or credentials.
    raise Error, 'App Store Connect build query failed. Verify API access and the production app.', cause: nil
  end
end
