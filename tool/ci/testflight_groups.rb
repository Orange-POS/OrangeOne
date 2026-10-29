# Trusted-main helper. Spaceship wraps Apple's official App Store Connect API;
# no app code, Apple-ID sessions or new credentials are used here.
require 'json'

class OrangeoneTestflight
  CONFIG = JSON.parse(File.read(File.join(__dir__, 'testflight_targets.json'))).freeze
  BUNDLE_ID = CONFIG.fetch('bundle_id').freeze
  GROUPS = CONFIG.fetch('groups').freeze
  class Error < StandardError; end
  # The exact build is uploaded and valid, but Apple still has to finish export
  # compliance or beta review. Distribution resumes later without a new upload.
  class Pending < Error; end

  def self.group_name(target)
    GROUPS.fetch(target) { raise Error, 'Unsupported TestFlight target group.' }
  end

  # No dependency on Spaceship until used on the protected signing runner.
  class AppleAPI
    def app
      Spaceship::ConnectAPI::App.find(BUNDLE_ID)
    end

    def groups(app)
      app.get_beta_groups
    end

    def builds(app, version, number)
      Spaceship::ConnectAPI::Build.all(app_id: app.id, version: version,
                                      build_number: number, platform: 'IOS')
    end

    def assign(build, group)
      build.add_beta_groups(beta_groups: [group])
    end

    def assigned?(build, group)
      group.fetch_builds.any? { |item| item.id == build.id }
    end
  end

  def initialize(api: AppleAPI.new, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                 sleeper: ->(seconds) { sleep(seconds) }, timeout: 900, interval: 15)
    @api, @clock, @sleeper, @timeout, @interval = api, clock, sleeper, timeout, interval
  end

  # Preflight before uploading, so a missing/automatic group doesn't waste a build.
  def prepare(target)
    @name = self.class.group_name(target)
    @app = request { @api.app }
    raise Error, 'Production App Store Connect app was not found.' unless @app && @app.bundle_id == BUNDLE_ID
    @group = selected_group
    self
  end

  # DEV/STG channel builds must reach exactly one tester group. Apple adds every
  # new build to each group with access to all builds, so no other group may
  # have it, or a development build could reach Production Testers.
  def prepare_channel(target)
    prepare(target)
    others = request { @api.groups(@app) }.reject { |group| group.name == @name }
    if others.any?(&:has_access_to_all_builds)
      raise Error, 'Disable automatic distribution (access to all builds) on every other tester group before channel delivery; otherwise new builds would reach them too.'
    end
    self
  end

  def distribute(version:, number:)
    raise Error, 'TestFlight group was not prepared.' unless @group
    unless version.match?(/\A\d+\.\d+\.\d+\z/) && number.match?(/\A[1-9]\d{0,3}\z/)
      raise Error, 'Invalid version or build number.'
    end
    deadline = @clock.call + @timeout
    build_id = nil
    loop do
      raise Error, 'Timed out waiting for the exact uploaded build; no latest-build fallback is allowed.' if @clock.call >= deadline
      candidates = request { @api.builds(@app, version, number) }.select do |build|
        build.app_id == @app.id && build.bundle_id == BUNDLE_ID && build.platform == 'IOS' &&
          build.app_version == version && build.version == number
      end
      raise Error, 'More than one build matched the release identity.' if candidates.length > 1
      build = candidates.first
      if build
        raise Error, 'Exact build identity changed during processing.' if build_id && build.id != build_id
        build_id = build.id
        raise Error, 'Exact uploaded build failed processing or is expired.' if build.expired || %w[FAILED INVALID].include?(build.processing_state)
        if build.processing_state == 'VALID' && build.build_beta_detail
          detail = build.build_beta_detail
          compliance_states = %w[MISSING_EXPORT_COMPLIANCE IN_EXPORT_COMPLIANCE_REVIEW]
          if [detail.internal_build_state, detail.external_build_state].any? { |state| compliance_states.include?(state) }
            raise Pending, 'Complete export compliance for this exact build in App Store Connect, then run distribute_existing with the same version/build; do not reupload. No compliance answer is assumed.'
          end
          group = selected_group
          raise Error, 'Selected tester group changed during processing.' unless group.id == @group.id
          ready = group.is_internal_group ? internal_testing_ready?(build) : external_testing_ready?(build)
          # Existing access is authoritative even while initial readiness lags.
          # Identity, validity, compliance and group checks must precede this.
          return build.id if request { @api.assigned?(build, group) }
          if ready
            # Relationship POST is additive and receives only the allowlisted group.
            request { @api.assign(build, group) }
            loop do
              confirmed_group = selected_group
              raise Error, 'Selected tester group changed during assignment verification.' unless confirmed_group.id == @group.id
              return build.id if request { @api.assigned?(build, group) }
              pause(deadline)
            end
          end
        end
      end
      pause(deadline)
    end
  end

  private

  def internal_testing_ready?(build)
    detail = build.build_beta_detail
    return false unless detail
    case detail.internal_build_state
    when nil, 'PROCESSING'
      false
    when 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'
      true
    when 'MISSING_EXPORT_COMPLIANCE', 'IN_EXPORT_COMPLIANCE_REVIEW'
      raise Pending, 'Complete or await export compliance for this exact build in App Store Connect, then run distribute_existing; do not reupload. No compliance answer is assumed.'
    when 'PROCESSING_EXCEPTION', 'EXPIRED'
      raise Error, 'Internal processing failed or this exact build expired. Inspect the build in App Store Connect.'
    else
      raise Error, 'Unrecognized internal build state. Inspect this exact build in App Store Connect before distribution.'
    end
  end

  def external_testing_ready?(build)
    # Fastlane 2.241.1 Build delegates external readiness to a nonexistent
    # BuildBetaDetail method. Read the dependency's supported state instead.
    detail = build.build_beta_detail
    return false unless detail
    case detail.external_build_state
    when nil, 'PROCESSING'
      false # Missing/eventually consistent details share the existing deadline.
    when 'BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'
      true
    when 'READY_FOR_BETA_SUBMISSION'
      raise Pending, 'This exact build requires manual Beta App Review submission in App Store Connect; no automatic review is submitted.'
    when 'WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW'
      raise Pending, 'Beta App Review is pending for this exact build. Wait for Apple review in App Store Connect, then run distribute_existing for this same version/build; do not reupload.'
    when 'BETA_REJECTED'
      raise Error, 'Beta App Review rejected this exact build. Resolve the rejection in App Store Connect before external distribution.'
    when 'MISSING_EXPORT_COMPLIANCE', 'IN_EXPORT_COMPLIANCE_REVIEW'
      raise Pending, 'Complete or await export compliance for this exact build in App Store Connect, then run distribute_existing; do not reupload. No compliance answer is assumed.'
    when 'PROCESSING_EXCEPTION', 'EXPIRED'
      raise Error, 'External processing failed or this exact build expired. Inspect the build in App Store Connect.'
    else
      raise Error, 'Unrecognized external build state. Inspect this exact build in App Store Connect before distribution.'
    end
  end

  def selected_group
    matches = request { @api.groups(@app) }.select { |group| group.name == @name }
    raise Error, 'Selected TestFlight group is missing or ambiguous.' unless matches.length == 1
    group = matches.first
    unless [true, false].include?(group.is_internal_group)
      raise Error, 'Could not determine internal/external tester eligibility.'
    end
    if group.has_access_to_all_builds
      raise Error, 'Disable automatic/all-build access on the selected group before explicit assignment.'
    end
    group
  end

  def pause(deadline)
    remaining = deadline - @clock.call
    raise Error, 'Timed out waiting for processing or verified group assignment.' if remaining <= 0
    @sleeper.call([@interval, remaining].min)
  end

  def request
    yield
  rescue StandardError
    # Do not print API errors, responses, credentials or tester information.
    raise Error, 'App Store Connect group operation failed. Verify API access and the selected app/build/group in App Store Connect.', cause: nil
  end
end
