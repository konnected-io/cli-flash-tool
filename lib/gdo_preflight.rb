require './lib/generic_preflight.rb' 

class GdoPreflight < GenericPreflight

  def firmwares 
    [{ file: 'konnected-esphome-garage-door-esp32-0.3.1.bin', offset: '0x0'}]
  end

  # def detect_port
  #   @port = %w{ /dev/ttyUSB[0-9]* /dev/cu.SLAB_USBtoUART* /dev/cu.usbserial* }.map do |pattern|
  #     Dir[pattern].first
  #   end.compact.first
  # end

  def start
    flash_firmware
    print_label
  end

  def print_label
    batchnum = Time.now.strftime "%y%m"
    label = Zebra::Zpl::Label.new(
      width:        203,
      length:       101,
      print_speed:  3
    )
  
    label << Zebra::Zpl::Text.new(
      data: "GDOv2-S",
      position: [20,20],
      font_size: Zebra::Zpl::FontSize::SIZE_2
    )
    label << Zebra::Zpl::Text.new(
        data:       "ID: #{@device_id}",
        position:   [20, 50],
        font_size:  Zebra::Zpl::FontSize::SIZE_1,
      )
  
    label << Zebra::Zpl::Text.new(
        data: "Batch: #{batchnum}",
        position: [20, 70],
        font_size: Zebra::Zpl::FontSize::SIZE_1
      )
  
    label << Zebra::Zpl::Datamatrix.new(
        data:             @device_id,
        position:         [150,20],
        symbol_height:     3
      )
  
    zpl = ''
    label.dump_contents zpl
    puts "\n"
    puts zpl
    puts "\n"
  end

end
