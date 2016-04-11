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
        end
      end
    end
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
