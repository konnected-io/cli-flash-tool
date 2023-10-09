require 'zebra/zpl'
require 'labelary'
require './lib/generic_preflight.rb'

class ProPreflight < GenericPreflight

  def firmwares
    [ 
      { file: 'konnected-pro-fw_v1.3.3-53178cb_1674758493.bin', offset: '0x0'}, 
      { file: 'konnected-pro-fs_v1.3.3-53178cb_1674758828.bin', offset: '0x368000'} 
    ]
  end

  def start
    flash_firmware
    erase_lfs_region
    generate_label
    print_label
  end

  def erase_lfs_region
    IO.popen("esptool.py --port=#{port} --baud 115200 erase_region 0x310000 0x58000").each do |line|
      puts Rainbow(line.chomp).aqua
    end
  end

  def generate_label
    # batchnum = Time.now.strftime "%y%m"
    batchnum = '2305'
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
        data: "Batch: #{batchnum}",
        position: [25, 50],
        font_size: Zebra::Zpl::FontSize::SIZE_2
      )
  
    label << Zebra::Zpl::Datamatrix.new(
        data:             @device_id,
        position:         [150,20],
        symbol_height:     3
      )
  
    @zpl = ''
    label.dump_contents @zpl
  end

  def print_label
    png = Labelary::Label.render zpl: @zpl, content_type: 'application/pdf', dpmm: 8, width: 1, height: 0.5
    file = Tempfile.new(['pro-label', '.pdf'])
    file.write(png)
    file.close
    puts file.path
    `lp -d Brother_QL_810W_2 -o orientation-requested=4 -o media='0.5x1.0\"' #{file.path}`
    file.unlink
  end

end
