# Turns App Store Connect API failures into safe, actionable CI messages.
# Only the error's class is inspected: Apple's response text, tokens, tester
# details and request data are never printed. Class names are compared as
# strings, so this file needs neither Spaceship nor Faraday to load.
module OrangeoneConnectErrors
  # Apple refused every request until the account accepts updated agreements
  # (403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED).
  AGREEMENT = %w[Spaceship::ProgramLicenseAgreementUpdated].freeze
  # 401 after Spaceship's own token refreshes.
  UNAUTHORIZED = %w[Spaceship::UnauthorizedAccessError].freeze
  # Any other 403.
  FORBIDDEN = %w[Spaceship::AccessForbiddenError Spaceship::InsufficientPermissions].freeze
  # Apple or the network was briefly unavailable; safe to repeat a read.
  TRANSIENT = %w[
    Spaceship::InternalServerError Spaceship::BadGatewayError Spaceship::GatewayTimeoutError
    Spaceship::AppleTimeoutError Spaceship::TooManyRequestsError
    Spaceship::ConnectAPI::APIClient::TooManyRequestsError
    Faraday::TimeoutError Faraday::ConnectionFailed Faraday::SSLError
    Net::OpenTimeout Net::ReadTimeout Errno::ECONNRESET Errno::ECONNREFUSED Errno::ETIMEDOUT
    SocketError
  ].freeze
  UNEXPECTED = %w[Spaceship::UnexpectedResponse].freeze

  def self.names(error) = error.class.ancestors.filter_map(&:name)

  def self.kind?(error, list) = names(error).intersect?(list)

  def self.transient?(error) = kind?(error, TRANSIENT)

  # Why the call failed and what to check, without any response content.
  def self.reason(error)
    if kind?(error, AGREEMENT)
      'Apple requires updated agreements to be accepted (403 REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED). ' \
        'The Account Holder must accept them in App Store Connect (Business) and on developer.apple.com; ' \
        'the API refuses every request until then.'
    elsif kind?(error, UNAUTHORIZED)
      'The API key was rejected (401). Check that APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and ' \
        "APP_STORE_CONNECT_KEY_BASE64 of this job's GitHub environment belong to one active key that was not revoked."
    elsif kind?(error, FORBIDDEN)
      'The API key is not allowed to do this (403). Give the key App Manager or Admin access to the app in ' \
        'App Store Connect (Users and Access > Integrations).'
    elsif transient?(error)
      'App Store Connect or the network was temporarily unavailable, also after retrying. Run the workflow again later.'
    elsif kind?(error, UNEXPECTED)
      'App Store Connect rejected the request. Check the app, build and tester group in App Store Connect.'
    else
      "Unexpected #{error.class.name || 'error'}. Check the App Store Connect API key and app."
    end
  end
end
