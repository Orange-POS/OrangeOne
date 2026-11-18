# Trusted-main helper: allocate the next TestFlight build number from App Store
# Connect. One app serves the Dev, Staging and Production groups, so the number
# must be above every build the app already has, whatever its version or flavor.
require_relative 'testflight_groups'
require_relative 'app_store_connect_errors'

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

  # Waits between attempts of a read that failed temporarily.
  RETRY_WAITS = [5, 10].freeze

  def initialize(api: AppleAPI.new, sleeper: ->(seconds) { sleep(seconds) })
    @api = api
    @sleeper = sleeper
  end

  # Highest numeric build number of the production app (0 when it has none).
  def highest
    app = request('finding the production app') { @api.app }
    raise Error, 'Production App Store Connect app was not found.' unless app && app.bundle_id == OrangeoneTestflight::BUNDLE_ID
    request('listing the uploaded builds') { @api.builds(app) }
      .filter_map { |build| Integer(build.version.to_s, 10, exception: false) }.max || 0
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

  # Read-only queries: repeated after temporary Apple or network errors. A
  # failure names the operation and its reason only; API errors, responses
  # and credentials are never printed.
  def request(operation)
    attempt = 0
    begin
      yield
    rescue Error
      raise
    rescue StandardError => error
      if OrangeoneConnectErrors.transient?(error) && attempt < RETRY_WAITS.length
        @sleeper.call(RETRY_WAITS[attempt])
        attempt += 1
        retry
      end
      raise Error, "App Store Connect build query failed while #{operation}: " \
                   "#{OrangeoneConnectErrors.reason(error)}", cause: nil
    end
  end
end
