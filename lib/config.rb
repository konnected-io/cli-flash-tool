class Config
  def initialize
    YAML.load_file(File.join(File.dirname(__FILE__), '..', 'config.yaml')).each do |k,v|
      define_singleton_method(k.to_sym) { v.is_a?(Hash) ? v.with_indifferent_access : v }
    end
  end
end