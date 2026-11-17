# Roughly where in the world is this visitor? Used only when the browser has
# not told us (it asks the visitor for their location first; see views/script.coffee).
#
# The visitor's IP address is sent to a public lookup service (default
# https://ipwho.is, no key needed). It is only done for public addresses, at most
# once an hour per address (answers are cached in memory), and never stored.
# Turn it off with GEOIP=false, or point GEOIP_URL at another service that answers
# with JSON containing "latitude" and "longitude" (use %{ip} where the address goes).
require 'net/http'
require 'json'
require 'ipaddr'
require 'uri'

module GeoIP
  DEFAULT_URL = 'https://ipwho.is/%{ip}'.freeze
  CACHE_FOR   = 3600
  TIMEOUT     = 3
  PRIVATE_RANGES = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16
                      100.64.0.0/10 ::1/128 fc00::/7 fe80::/10].map { |r| IPAddr.new(r) }.freeze
  LOCK  = Mutex.new
  CACHE = {}

  class << self
    # Replace the lookup in tests: a callable taking an ip string, returning [lng, lat] or nil.
    attr_accessor :provider

    def enabled?; AppEnv.geoip?; end

    def public_ip?(ip)
      addr = IPAddr.new(ip.to_s)
      PRIVATE_RANGES.none? { |range| range.include?(addr) }
    rescue IPAddr::Error
      false
    end

    # [lng, lat] for this address, or nil when unknown, private or disabled.
    def locate(ip)
      return nil unless enabled? && public_ip?(ip)
      now = Time.now.to_i
      LOCK.synchronize do
        hit = CACHE[ip]
        return hit[1] if hit && now - hit[0] < CACHE_FOR
      end
      found = (provider || method(:lookup)).call(ip)
      LOCK.synchronize do
        CACHE.clear if CACHE.size > 5000
        CACHE[ip] = [now, found]
      end
      found
    end

    def reset!; LOCK.synchronize { CACHE.clear }; end

    def lookup(ip)
      url = URI(ENV.fetch('GEOIP_URL', DEFAULT_URL) % { ip: URI.encode_www_form_component(ip) })
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = url.scheme == 'https'
      http.open_timeout = http.read_timeout = TIMEOUT
      response = http.get(url.request_uri, 'Accept' => 'application/json')
      return nil unless response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      return nil if data['success'] == false
      lng = Float(data['longitude']) rescue nil
      lat = Float(data['latitude']) rescue nil
      lng && lat && lng.between?(-180, 180) && lat.between?(-85, 85) ? [lng, lat] : nil
    rescue StandardError
      nil
    end
  end
end
