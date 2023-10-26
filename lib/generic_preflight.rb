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
    IO.popen("esptool.py --port=#{port} --baud 115200 write_flash --flash_mode dio #{file_parts}").each do |line|
      esptool_output << line.chomp
      @runner.update_status(port, Rainbow(line.chomp).aqua)
    end
    @device_id = esptool_output.detect{|line| line.start_with?('MAC:')}.match(/^MAC: (.*)/)[1].gsub(':','')
    sleep 1 # wait for device to reset after flashing
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
    print_job.print @label, ip
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

