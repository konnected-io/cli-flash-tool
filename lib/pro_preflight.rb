require 'zebra/zpl'
require 'labelary'
require 'ssdp'
require 'zeroconf'
require './lib/generic_preflight.rb'

class ProPreflight < GenericPreflight

  @product_name = 'Alarm Panel Pro'

  def modelnum
    'APPROv1'
  end

  def device_type
    'AlarmPanel'
  end

  def chip
    'ESP32'
  end

  def firmware_type
    'esphome'
  end

  def self.download_firmware
    github_releases_url = 'https://api.github.com/repos/konnected-io/konnected-esphome/releases/latest'
    key = 'konnected-esphome-alarm-panel-pro-v1.8-ethernet'
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

  def self.firmwares
    @filename
  end

  def start
    if @runner.config.flash
      return unless flash_firmware
    else
      get_device_id
    end
    if @runner.config.network_check
      return unless network_check
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

  def erase_lfs_region
    IO.popen("esptool.py --port=#{port} --baud 115200 erase_region 0x310000 0x58000").each do |line|
      @runner.update_status port, Rainbow(line.chomp).aqua
    end
  end

  def network_check
    if firmware_type == 'esphome'
      if RUBY_PLATFORM.include?('linux')
        network_check_avahi
      else
        network_check_zeroconf
      end
    else
      network_check_ssdp
    end
  end

  def network_check_zeroconf
    mdns_result = nil
    begin
      Timeout.timeout(30) do |sec|
        start_time = Time.now.to_i
        countdown = sec

        until mdns_result do
          @runner.update_status port, Rainbow("CONNECT ETHERNET NOW. Timeout in #{countdown} sec.").yellow.inverse
          ZeroConf.browse('_konnected._tcp.local') do |res|
            if res.answer.find{|r| r[2].is_a?(Resolv::DNS::Resource::IN::TXT)}[2].strings.include?("mac=#{@device_id}")
              mdns_result = res
            end
          end
          countdown = sec - (Time.now.to_i - start_time)
        end
      end
    rescue Timeout::Error
      @runner.update_status port, Rainbow("FAILED: No network connection!").red
      return false
    end

    ip = mdns_result.additional[0][2].address
    @runner.update_status port, Rainbow("Ethernet connected with IP #{ip}. Running ping test...").aqua

    packet_loss = ping_test(ip)
    if packet_loss > 0 && packet_loss < 10
      @runner.update_status port, Rainbow("RETRY: Packet loss #{packet_loss}% Trying again...").yellow
      packet_loss = ping_test(ip)
    end
    if packet_loss > 0
      @runner.update_status port, Rainbow("FAILED: Packet loss #{packet_loss}%").red
      return false
    end
    true
  end

  def network_check_avahi
    ip = nil
    begin
      Timeout.timeout(30) do |sec|
        start_time = Time.now.to_i
        countdown = sec

        until ip do
          @runner.update_status port, Rainbow("CONNECT ETHERNET NOW. Timeout in #{countdown} sec.").yellow.inverse
          IO.popen("avahi-browse -r -t _konnected._tcp") do |io|
            while line = io.gets
              if line.strip.start_with?('address')
                addr = line.match(/\[([\d\.]+)\]/)[1]
              end
              if line.strip.start_with?('txt')
                if line.match(/mac=#{@device_id}/)
                  ip = addr
                end
              end
            end
          end
          countdown = sec - (Time.now.to_i - start_time)
        end
      end
    rescue Timeout::Error
      @runner.update_status port, Rainbow("FAILED: No network connection!").red
      return false
    end

    @runner.update_status port, Rainbow("Ethernet connected with IP #{ip}. Running ping test...").aqua

    packet_loss = ping_test(ip)
    if packet_loss > 0 && packet_loss < 10
      @runner.update_status port, Rainbow("RETRY: Packet loss #{packet_loss}% Trying again...").yellow
      packet_loss = ping_test(ip)
    end
    if packet_loss > 0
      @runner.update_status port, Rainbow("FAILED: Packet loss #{packet_loss}%").red
      return false
    end
    true
  end


  # deprecated for nodemcu firmware
  def network_check_ssdp
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

    packet_loss = ping_test(ip)
    if packet_loss > 0 && packet_loss < 10
      @runner.update_status port, Rainbow("RETRY: Packet loss #{packet_loss}% Trying again...").yellow
      packet_loss = ping_test(ip)
    end
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

  private

  def ping_test(ip)
    if RUBY_PLATFORM.include?('linux')
      ping_on_linux(ip)
    else
      ping_on_mac(ip)
    end
  end

  def ping_on_mac(ip)
    ping = `ping #{ip} -g 56 -G 1500 -h 256 -i 0.5 -q`
    packet_loss = ping.match(/(\d+\.\d+)% packet loss/)[1].to_i
    return packet_loss
  end

  def ping_on_linux(ip)
    ping = `ping #{ip} -s 1088 -c 6 -W 3 -q`
    packet_loss = ping.match(/(\d*\.?\d+)% packet loss/)[1].to_i
    return packet_loss
  end

end
