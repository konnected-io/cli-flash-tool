require 'zebra/zpl'
require 'labelary'
require './lib/generic_preflight.rb'

class ApPreflight < GenericPreflight

  @product_name = '6-zone Alarm Panel'

  def modelnum
    'APv2'
  end

  def device_type
    'AlarmPanel'
  end

  def chip
    'ESP8266'
  end

  def firmware_type
    'nodemcu'
  end

  def self.download_firmware
    mainfest_url = 'https://install.konnected.io/manifest.json'
    manifest_json = JSON.parse(Net::HTTP.get(URI(mainfest_url)))
    build = manifest_json['builds'].detect{|build| build['chipFamily'] == 'ESP8266' }
    @firmwares = []
    build['parts'].each do |part|
      download_url = part['path']
      filename = download_url.split('/').last
      puts Rainbow("Downloading #{download_url}").yellow
      URI.open(download_url) do |file|
        File.open("#{Dir.home}/Downloads/#{filename}", "wb") do |f|
          f.write(file.read)
        end
      end
      @firmwares << { file: filename, offset: "0x#{part['offset'].to_i.to_s(16)}" }
    end
  end

  def self.firmwares
    @firmwares
  end

  def start
    if @runner.config.flash
      flash_firmware
    else
      get_device_id
    end
    if @runner.config.preregister
      return unless preregister
    end
    if @runner.config.label_printer[:enabled]
      generate_label
      print_label
    end
    finish
  end

  def generate_label
    @runner.update_status port, Rainbow("Generating label: #{@device_id}").yellow
    label = Zebra::Zpl::Label.new(
      width:        203,
      length:       101,
      print_speed:  3
    )

    label << Zebra::Zpl::Text.new(
      data:       "#{@device_id}",
      position:   [20, 20],
      font_size:  Zebra::Zpl::FontSize::SIZE_2,
      )

    label << Zebra::Zpl::Text.new(
      data: "Batch: #{@runner.batchnum}",
      position: [20, 50],
      font_size: Zebra::Zpl::FontSize::SIZE_2
    )

    label << Zebra::Zpl::Datamatrix.new(
      data:             @device_id,
      position:         [150,20],
      symbol_height:     3
    )

    @label = label
  end

end