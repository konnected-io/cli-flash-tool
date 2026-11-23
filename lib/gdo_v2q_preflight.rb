require_relative 'gdo_preflight'
require_relative 'gdo_self_test'

class GdoV2qPreflight < GdoPreflight
  include GdoSelfTest

  @product_name = 'Garage Door Opener blaQ'

  # The published ESP Web Tools manifest is the source of truth for the current
  # customer firmware: it names exactly one factory image, so there is no risk
  # of picking the .ota.bin (or another asset) that sits beside it in a release.
  MANIFEST_URL = 'https://install.konnected.io/manifests/esphome-gdov2-q.json'.freeze

  RELEASES_URL = 'https://api.github.com/repos/konnected-io/konnected-esphome/releases/latest'.freeze
  SELF_TEST_ASSET = /\Akonnected-esphome-selftest-GDOv2-Q-[\d.]+\.bin\z/

  def modelnum
    'GDOv2-Q'
  end

  def device_type
    'GdoV2Q'
  end

  def chip
    'ESP32'
  end

  def firmware_type
    'esphome'
  end

  def start
    @runner.self_test? ? self_test_start : super
  end

  def self.download_firmware
    manifest = JSON.parse(Net::HTTP.get(URI(MANIFEST_URL)))
    download_url = manifest.dig('builds', 0, 'parts', 0, 'path')
    raise "No firmware image in #{MANIFEST_URL}" if download_url.blank?

    puts Rainbow("#{manifest['name']} #{manifest['version']}").green
    @filename = download(download_url)
  end

  def self.self_test_firmware
    @self_test_filename
  end

  # `override` is an optional local .bin path (config.yaml self_test.firmware),
  # for testing a self-test build before it's released.
  def self.download_self_test_firmware(override = nil)
    if override.present?
      path = File.expand_path(override)
      raise "Self-test firmware not found: #{path}" unless File.exist?(path)

      puts Rainbow("Self-test firmware (local): #{path}").green
      return @self_test_filename = path
    end

    release = JSON.parse(Net::HTTP.get(URI(RELEASES_URL)))
    asset = release['assets'].detect { |a| a['name'].match?(SELF_TEST_ASSET) }
    unless asset
      raise "Release #{release['tag_name']} has no self-test firmware (konnected-esphome-selftest-GDOv2-Q-*.bin). " \
            'Set self_test.firmware in config.yaml to a local build.'
    end
    @self_test_filename = download(asset['browser_download_url'])
  end

  def self.download(url)
    filename = url.split('/').last
    puts Rainbow("Downloading #{url}").yellow
    URI.open(url) do |file|
      File.open("#{Dir.home}/Downloads/#{filename}", 'wb') { |f| f.write(file.read) }
    end
    filename
  end
end
