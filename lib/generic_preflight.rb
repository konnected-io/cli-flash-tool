class GenericPreflight

  attr_reader :port
  
  def self.product_name
    @product_name
  end

  def initialize(port, runner)
    @started_at = Time.now
    @runner = runner
    @port = port
  end

  def flash_firmware
    file_parts = if self.class.firmwares.is_a?(Array)
      self.class.firmwares.map do |part|
        "#{part[:offset]} #{Dir.home}/Downloads/#{part[:file]}"
      end.join(' ')
    else
      "0x0 #{Dir.home}/Downloads/#{self.class.firmwares}"
    end

    esptool_output = []
    IO.popen("esptool.py --port=#{port} --baud 460800 write_flash -e --flash_mode dio #{file_parts}") do |io|
      while line = io.gets
        esptool_output << line.chomp!
        @runner.update_status(port, Rainbow(line).aqua)
      end
    end

    if $?.success?
      @device_id = esptool_output.detect{|line| line.start_with?('MAC:')}.match(/^MAC:\s+(.*)/)[1].gsub(':','')
      @runner.update_status(port, Rainbow(@device_id).blue)
      sleep 1 # wait for device to reset after flashing
      true
    else
      @runner.update_status(port, Rainbow("Failed to flash the firmware!").red)
      false
    end
  end

  def get_device_id
    esptool_output = []
    IO.popen("esptool.py --port=#{port} --baud 460800 chip_id").each do |line|
      esptool_output << line.chomp
      @runner.update_status(port, Rainbow(line.chomp).aqua)
    end
    @device_id = esptool_output.detect{|line| line.start_with?('MAC:')}.match(/^MAC:\s+(.*)/)[1].gsub(':','')
  end

  def print_label
    @runner.update_status port, Rainbow("Printing label: #{@device_id}").yellow
    case @runner.config.label_printer[:type]
    when 'pdf'
      print_pdf_label
    when 'zpl'
      print_zpl_label
    else
      puts Rainbow("Invalid label type `#{@runner.config.label_printer[:type]}`!").red
    end
  end

  def preregister
    @runner.update_status port, Rainbow("Pre-registering in Konnected Cloud").yellow
    lambda_client = Aws::Lambda::Client.new(
      region: 'us-east-1', credentials: @runner.sso_credentials
    )
    resp = lambda_client.invoke({
      function_name: 'konnected-cloud-prod-device_job-preregister',
      payload: {
        id: @device_id,
        batch: @runner.batchnum,
        type: device_type,
        firmware: firmware_type,
        chip: chip
      }.to_json
    })

    unless resp.status_code == 200
      @runner.update_status port, Rainbow(resp.payload).red
      return false
    end
    payload = JSON.parse(resp.payload.read)
    @batchnum = payload['batch']&.to_i
    true
  end

  def finish
    @runner.update_status port, Rainbow("#{@device_id}").green.inverse
    @runner.increment_success
  end

  def wait_till_unplugged
    until !File.exist?(port) do
      sleep 1
    end
  end

  private

  def print_zpl_label
    print_job = Zebra::PrintJob.new @runner.config.label_printer[:name]
    ip = @runner.config.label_printer[:ip]
    print_job.print @label, ip, print_service: 'lp'
  end

  def print_pdf_label
    zpl = ''
    @label.dump_contents zpl
    png = Labelary::Label.render zpl: zpl, content_type: 'application/pdf', dpmm: 8, width: 1, height: 0.5
    file = Tempfile.new(['label', '.pdf'])
    file.write(png)
    file.close
    `lp -d #{@runner.config.label_printer[:name]} -o orientation-requested=4 -o media='0.5x1.1' #{file.path}`
    file.unlink
  end

end

