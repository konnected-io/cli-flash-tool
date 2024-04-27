require './lib/generic_preflight.rb' 

class GdoPreflight < GenericPreflight
  def self.firmwares 
    @filename
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
      data: modelnum,
      position: [20,20],
      font_size: Zebra::Zpl::FontSize::SIZE_2
    )
    label << Zebra::Zpl::Text.new(
        data:       "ID: #{@device_id}",
        position:   [20, 50],
        font_size:  Zebra::Zpl::FontSize::SIZE_1,
      )
  
    label << Zebra::Zpl::Text.new(
        data: "Batch: #{@runner.batchnum}",
        position: [20, 70],
        font_size: Zebra::Zpl::FontSize::SIZE_1
      )
  
    label << Zebra::Zpl::Datamatrix.new(
        data:             @device_id,
        position:         [150,20],
        symbol_height:     3
      )
  
    @label = label
  end

end
