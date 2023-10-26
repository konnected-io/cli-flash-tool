require 'zebra/zpl'
require 'labelary'
require './lib/generic_preflight.rb'

class ProPreflight < GenericPreflight

  @product_name = 'Alarm Panel Pro'

  def self.firmwares
    [ 
      { file: 'konnected-pro-fw_v1.3.3-53178cb_1674758493.bin', offset: '0x0'}, 
      { file: 'konnected-pro-fs_v1.3.3-53178cb_1674758828.bin', offset: '0x368000'} 
    ]
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
        position:   [25, 20],
        font_size:  Zebra::Zpl::FontSize::SIZE_2,
      )
  
    label << Zebra::Zpl::Text.new(
        data: "Batch: #{@runner.batchnum}",
        position: [25, 50],
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
