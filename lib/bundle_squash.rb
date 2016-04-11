require "bundle_squash/version"
require 'bundler'

class BundleSquash
  def self.run
    b = self.new
    b.bundler_dependencies_to_specs
  end

  def initialize
    bundler = Bundler.setup
    @definition = bundler.instance_variable_get(:@definition)
    @definition.resolve
  end

  def bundler_dependencies_to_specs
    @specs = {}
    @specs[:default] = @definition.specs_for([:default])
    @definition.groups.each do |group|
      @specs[group] = Bundler::SpecSet.new(@definition.specs_for([group]).to_a - @specs[:default].to_a) unless group == :default
    end
  end
end
