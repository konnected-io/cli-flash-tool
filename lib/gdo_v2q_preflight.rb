class GdoV2qPreflight < GdoPreflight
  @product_name = 'Garage Door Opener blaQ'

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

  def self.download_firmware
    github_releases_url = 'https://api.github.com/repos/konnected-io/konnected-esphome/releases/latest'
    key = 'konnected-esphome-garage-door-GDOv2-Q'
    release_json = JSON.parse(Net::HTTP.get(URI(github_releases_url)))
    release = release_json['assets'].detect{|asset| asset['name'].start_with?(key) }
    download_url = release['browser_download_url']
    @filename = download_url.split('/').last
    puts Rainbow("Downloading #{download_url}").yellow
    URI.open(download_url) do |file|
      File.open("#{Dir.home}/Downloads/#{@filename}", "wb") do |f|
        f.write(file.read)
      end
    end
  end

end