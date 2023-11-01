require 'zebra/zpl'
require 'labelary'
require './lib/generic_preflight.rb'

class ProPreflight < GenericPreflight

  @product_name = 'Alarm Panel Pro'

  def modelnum
    'APPROv1'
  end

  def self.download_firmware
    mainfest_url = 'https://install.konnected.io/manifest.json'
    manifest_json = JSON.parse(Net::HTTP.get(URI(mainfest_url)))
    build = manifest_json['builds'].detect{|build| build['chipFamily'] == 'ESP32' }
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
    flash_firmware
    erase_lfs_region
    if @runner.config.label_printer[:enabled]
      generate_label
      print_label
    end
    finish
  end

  def erase_lfs_region
    IO.popen("esptool.py --port=#{port} --baud 115200 erase_region 0x310000 0x58000").each do |line|
      @runner.update_status port, Rainbow(line.chomp).aqua
    end
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
