class GenericPreflight

  attr_reader :port

  def initialize(port, runner)
    @started_at = Time.now
    @runner = runner
    @port = port
  end

  def flash_firmware
    puts Rainbow(%{#####
## Flashing firmware on port #{port}"
##
}).green

    file_parts = if firmwares.is_a?(Array)
      firmwares.map do |part|
        "#{part[:offset]} ~/Downloads/#{part[:file]}"
      end.join(' ')
    else
      "0x0 ~/Downloads/#{firmwares}"
    end

    esptool_output = []
    IO.popen("esptool.py --port=#{port} --baud 115200 write_flash --flash_mode dio #{file_parts}").each do |line|
      # puts Rainbow(line.chomp).aqua
      esptool_output << line.chomp
      @runner.update_status(port, Rainbow(line.chomp).aqua)
    end
    @device_id = esptool_output.detect{|line| line.start_with?('MAC:')}.match(/^MAC: (.*)/)[1].gsub(':','')
    puts Rainbow("## Device ID: #{@device_id}\n").green
    sleep 1 # wait for device to reset after flashing
  end

  def wait_till_unplugged
    until !File.exist?(port) do
      sleep 1
    end
  end

end
