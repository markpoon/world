# Single source of truth for "which mode is this app in, and which optional
# features are on". Everything else asks AppEnv instead of reading ENV directly.
#
#   RACK_ENV                 development | production (what Puma/Sinatra use too)
#   RENDER                   set by Render; marks a public host
#   ENABLE_DEBUG_ROUTES      /binding (Pry) and /debug/error
#   SHOW_ERRORS              full stack-trace pages instead of the generic 500 page
#   RELOAD_CODE              Sinatra::Reloader
#   SEED_DEMO_USER           create the demo account on boot
#
# The first three default to "on in development", but never on a public host
# (Render) unless set explicitly, so development mode can be deployed safely.
module AppEnv
  TRUE_VALUES = %w[1 true yes on].freeze

  def self.name;          (ENV['RACK_ENV'] || 'development').to_s; end
  def self.development?;  name == 'development'; end
  def self.production?;   name == 'production'; end
  def self.on_render?;    !ENV['RENDER'].to_s.empty?; end

  def self.flag(var, default)
    value = ENV[var].to_s.strip.downcase
    value.empty? ? default : TRUE_VALUES.include?(value)
  end

  def self.local_dev?;      development? && !on_render?; end
  def self.debug_routes?;   flag('ENABLE_DEBUG_ROUTES', local_dev?); end
  def self.show_errors?;    flag('SHOW_ERRORS', local_dev?); end
  def self.reload_code?;    flag('RELOAD_CODE', local_dev?); end
  def self.seed_demo_user?; flag('SEED_DEMO_USER', false); end

  def self.flags
    { debug_routes: debug_routes?, show_errors: show_errors?,
      reload_code: reload_code?, seed_demo_user: seed_demo_user? }
  end

  def self.summary
    "env=#{name} on_render=#{on_render?} " + flags.map { |k, v| "#{k}=#{v}" }.join(' ')
  end
end
