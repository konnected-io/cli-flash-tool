require 'zebra/zpl'
require 'labelary'
require 'ssdp'
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
    # get_device_id
    return unless network_check
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

  def network_check
    ssdp_result = nil

    begin
      # connect to network
      Timeout.timeout(30) do |sec|
        start_time = Time.now.to_i
        countdown = sec
        until ssdp_result do
          @runner.update_status port, Rainbow("CONNECT ETHERNET NOW. Timeout in #{countdown} sec.").yellow.inverse
          st = 'urn:schemas-konnected-io:device:Security:2'
          res = SSDP::Consumer.new(timeout: 3).search(service: st)
          ssdp_result = res.detect do |r|
            r[:params]['ST'] == 'urn:schemas-konnected-io:device:Security:2' &&
              r[:params]['USN'].match(/\w{2}#{@device_id[0,10]}/)
          end
          countdown = sec - (Time.now.to_i - start_time)
        end
      end
    rescue Timeout::Error
      @runner.update_status port, Rainbow("FAILED: No network connection!").red
      return false
    end

    ip = ssdp_result[:address]
    @runner.update_status port, Rainbow("Ethernet connected with IP #{ip}. Running ping test...").aqua

    # ping test
    ping = `ping #{ip} -i 0.5 -c 15 -q`
    packet_loss = ping.match(/(\d+\.\d+)% packet loss/)[1].to_i
    if packet_loss > 0
      @runner.update_status port, Rainbow("FAILED: Packet loss #{packet_loss}%").red
      return false
    end
    true
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
