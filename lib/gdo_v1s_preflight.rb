class GdoV1sPreflight < GdoPreflight
  @product_name = 'Garage Door Opener (v1) w/ Sensor'

  def modelnum
    'GDOv1-S'
  end

  def device_type
    'GarageDoor'
  end

  def chip
    'ESP8266'
  end

  def firmware_type
    'nodemcu'
  end

  def self.download_firmware
    mainfest_url = 'https://install.konnected.io/manifests/konnected-garage-door-opener.json'
    manifest_json = JSON.parse(Net::HTTP.get(URI(mainfest_url)))
    build = manifest_json['builds'].detect{|build| build['chipFamily'] == 'ESP8266' }
    download_url = build['parts'][0]['path']
    @filename = download_url.split('/').last
    puts Rainbow("Downloading #{download_url}").yellow
    URI.open(download_url) do |file|
      File.open("#{Dir.home}/Downloads/#{@filename}", "wb") do |f|
        f.write(file.read)
      end
    end
  end

end