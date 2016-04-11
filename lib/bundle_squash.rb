require "bundle_squash/version"
require 'fileutils'
require 'find'
require 'bundler'

class BundleSquash
  DEST = './vendor/bundle_squash'

  def self.run
    b = self.new
    b.bundler_dependencies_to_specs
    b.cleanup
    b.cp_r
    b.write_gemspecs
    b.write_require_files
  end

  def initialize
    bundler = Bundler.setup
    @definition = bundler.instance_variable_get(:@definition)
    @definition.resolve
    @copied_specs = {}
  end

  def bundler_dependencies_to_specs
    @specs = {}
    @specs[:default] = @definition.specs_for([:default])
    @definition.groups.each do |group|
      @specs[group] = Bundler::SpecSet.new(@definition.specs_for([group]).to_a - @specs[:default].to_a) unless group == :default
    end
  end

  def cleanup
    FileUtils.rm_r DEST if File.exists? DEST
    FileUtils.mkdir_p DEST
  end

  def cp_r
    $LOAD_PATH.grep(%r{/lib$}).sort.select {|lp| FileTest.directory? lp}.select do |lp|
      gem = gemname(lp)
      puts "copying #{lp} ..."

      @specs.each_pair do |group, specs|
        FileUtils.mkdir_p "#{DEST}/#{group}/lib"
        if (spec = specs.detect {|d| d.name == gem})
          if (overlaps = (files_in(lp) & bundled_files_for(group))).any?
            if (same_filenames = overlaps.select {|f| !FileUtils.cmp "#{lp}#{f}", "#{DEST}/#{group}/lib#{f}"}).any?
              puts "skipping  #{lp}: these files already exist!\n #{same_filenames.inspect}"
              next
            end
          end
          `rsync -a --exclude=.git #{lp} #{DEST}/#{group}`
          #TODO overwrite check?
          %w(data vendor frameworks ui).each do |dir|
            FileUtils.cp_r "#{lp}/../#{dir}", "#{DEST}/#{group}" if File.exists?("#{lp}/../#{dir}")
          end
          (@copied_specs[group] ||= []) << spec
        end
      end
    end
  end

  def write_gemspecs
    @copied_specs.keys.each do |group|
      File.open("#{DEST}/#{group}/bundle_squash-#{group}.gemspec", 'w') {|f| f.write <<-GEMSPEC }
# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |gem|
  gem.name = 'bundle_squash-#{group}'
  gem.version = '0'
  gem.summary = gem.authors = ''
  gem.require_paths = ['lib']
end
GEMSPEC
    end
  end

  def write_require_files
    @specs.each_pair do |group, specs|
      requires = specs.map {|s| require_string(s).map {|r| "require '#{r}'"}}.flatten.join("\n")
      File.open("#{DEST}/#{group}/lib/bundle_squash-#{group}.rb", 'w') {|f| f.write requires + "\n"}
    end
  end

  def require_string(spec)
    ret = Array(spec.respond_to?(:autorequire) ? spec.autorequire : [])
    return ret if ret.any?

    begin
      Kernel.require spec.name
      ret << spec.name
    rescue LoadError
      if spec.name.include?('-')
        namespaced_file = spec.name.gsub('-', '/')
        begin
          Kernel.require namespaced_file
          ret << namespaced_file
        rescue LoadError
        end
      end
    end
    ret
  end

  private
  def files_in(dir)
    Find.find(dir).select {|e| FileTest.file? e}.reject {|f| f.include?('/.git/')}.map {|f| f.sub(%r{^#{dir}}, '')}
  end

  def bundled_files_for(group)
    files_in "#{DEST}/#{group}/lib"
  end

  def gemname(filename)
    filename.match(%r{.*/(.*)-.*/lib}) { $1 }
  end
end
