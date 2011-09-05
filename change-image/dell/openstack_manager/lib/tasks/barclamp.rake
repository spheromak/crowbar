# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: RobHirschfeld
#

namespace :barclamp do

  MODEL_SOURCE = File.join 'lib', 'barclamp_model'
  MODEL_SUBSTRING_BASE = '==BC-MODEL=='
  MODEL_SUBSTRING_CAMEL = '==^BC-MODEL=='
  MODEL_TARGET = File.join '..', 'barclamps'
  BASE_PATH = File.join '/opt', 'dell'
  BARCLAMP_PATH = File.join BASE_PATH, 'chef'
  CROWBAR_PATH = File.join BASE_PATH, 'openstack_manager'
  BIN_PATH = File.join BASE_PATH, 'bin'
  
  desc "Create a new barclamp"
  task :create, :name, :entity, :target, :needs=>[] do |t, args|
    puts args.inspect
    args.with_defaults(:entity => 'Dell', :target => MODEL_TARGET)
    bc = args.name
    target = File.join args.target, bc
    if bc.nil?
      puts "You must supply a name to create a barclamp"
    elsif File.exist? File.join target, "crowbar.yml"
      puts "Aborting! A barclamp already exists in '#{target}'."
    else
      puts "Creating barclamp '#{bc}' into '#{target}' as entity '#{args.entity}'."
      FileUtils.mkdir target
      clone = Dir.entries(MODEL_SOURCE).find_all { |e| !e.start_with? '.'}
      clone.each do |item|
        bc_cloner(item, bc, args.entity, MODEL_SOURCE, target)
      end
    end
  end
  
  def bc_cloner(item, bc, entity, source, target)
    new_item = bc_replacer(item, bc, entity)
    new_file = File.join target, new_item
    new_source = File.join(source, item)
    if File.directory? new_source
      #puts "\tcreating directory #{new_file}."
      FileUtils.mkdir new_file, :verbose => true
      clone = Dir.entries(new_source).find_all { |e| !e.start_with? '.'}
      clone.each do |recurse|
        bc_cloner(recurse, bc, entity, new_source, new_file)
      end
    else
      #need to inject into the file
      puts "\t\tcreating file #{new_file}."
      t = File.open(new_file, 'w')
      File.open(new_source, 'r') do |f|
        s = f.read
        t.write(bc_replacer(s, bc, entity))
      end
      t.close
    end
  end
  
  def bc_replacer(item, bc, entity)
    item = item.gsub(MODEL_SUBSTRING_BASE, bc)
    item = item.gsub(MODEL_SUBSTRING_CAMEL, bc.capitalize)
    item = item.gsub('Copyright 2011, Dell', "Copyright #{Time.now.year}, #{entity}")
    return item
  end
  
  desc "Install a barclamp into an active system"
  task :install, [:path] do |t, args|
    path = args.path || "."
    version = File.join path, 'crowbar.yml'
    unless File.exist? version
      puts "ERROR: could not install barclamp - failed to find required #{version} file"
    else
      barclamp = YAML.load_file(version)
      bc = barclamp["barclamp"]["name"].chomp.strip
      
      case barclamp["crowbar"]["layout"].to_i
      when 1
        bc_install_layout_1 bc, path, barclamp
      else
        puts "ERROR: could not install barclamp #{bc} because #{barclamp["barclamp"]["crowbar_layout"]} is unknown layout."
      end

      puts "done."

    end
  end

  desc "Install a barclamp into an active system"
  task :bootstrap, [:path] do |t, args|
    path = args.path
    puts "Boostrapping starting in #{path}."
    clone = Dir.entries(path).find_all { |e| !e.start_with? '.'}
    clone.each do |bc|
      bc_path = File.join path, bc
      if File.exist? File.join bc_path, "crowbar.yml"
        puts "Boostrapping from #{bc_path}"
        Rake::Task['barclamp:install'].invoke()
      else
        puts "Skipping #{bc_path} because no crowbar.yml file was found"
      end
    end
    puts "Boostrapping done."
  end

  desc "Install a barclamp into an active system"
  task :install, [:path] do |t, args|
    path = args.path || "."
    version = File.join path, 'crowbar.yml'
    unless File.exist? version
      puts "ERROR: could not install barclamp - failed to find required #{version} file"
    else
      barclamp = YAML.load_file(version)
      bc = barclamp["barclamp"]["name"].chomp.strip
      
      case barclamp["crowbar"]["layout"].to_i
      when 1
        bc_install_layout_1 bc, path, barclamp
      else
        puts "ERROR: could not install barclamp #{bc} because #{barclamp["barclamp"]["crowbar_layout"]} is unknown layout."
      end

      puts "done."

    end
  end

  #merges localizations from config into the matching translation files
  def merge_i18n(barclamp)
    locales = barclamp['locale_additions']
    locales.each do |key, value|
      #translation file (can be multiple)
      f = File.join CROWBAR_PATH, 'config', 'locales', "#{key}.yml"
      if File.exist? f
        puts "merging tranlation for #{f}"
        master = YAML.load_file f
        master = merge_tree(key, value, master)
        File.open( f, 'w' ) do |out|
          YAML.dump( master, out )
        end
      else
        puts "WARNING: Did not attempt tranlation merge for #{f} because file was not found."
      end
    end
  end
  
  def merge_tree(key, value, target)
    if target.key? key
      if target[key].class == Hash
        value.each do |k, v|
          #puts "recursing into tree at #{key} for #{k}"
          target[key] = merge_tree(k, v, target[key])
        end
      else
        #puts "replaced key #{key} value #{value}"
        target[key] = value      
      end
    else
      #puts "added key #{key} value #{value}"
      target[key] = value
    end
    return target
  end

  def bc_install_layout_1(bc, path, barclamp)
    
    #TODO - add a roll back so there are NOT partial results if a step fails
    debug = true  #verbose file ops
    
    puts "Installing barclamp #{bc} from #{path}"

    #merge i18n information (least invasive operations first)
    merge_i18n barclamp
    
    #copy the rails parts (required for render BEFORE import into chef)
    dirs = Dir.entries(path)
    FileUtils.cp_r File.join(path, 'app'), CROWBAR_PATH, :verbose => debug if dirs.include? 'app'
    FileUtils.cp_r File.join(path, 'public'), CROWBAR_PATH, :verbose => debug if dirs.include? 'public'
    FileUtils.cp_r File.join(path, 'command_line'), BIN_PATH, :verbose => debug if dirs.include? 'command_line'
    puts "\tcopied app & command line files"

    # copy all the files to the target
    FileUtils.cp_r File.join(path, 'chef'), BASE_PATH
    puts "\tcopied over chef parts from #{path} to #{BARCLAMP_PATH}"
    
    #upload the cookbooks
    FileUtils.cd File.join BARCLAMP_PATH, 'cookbooks'
    knife_cookbook = "knife cookbook upload -o . #{bc}"
    system knife_cookbook
    puts "\texecuted: #{knife_cookbook}"
    
    #upload the databags
    FileUtils.cd File.join BARCLAMP_PATH, 'data_bags', 'crowbar'
    knife_databag  = "knife data bag from file crowbar bc-template-#{bc}.json"
    system knife_databag
    puts "\texecuted: #{knife_databag}"

    #upload the roles
    roles = Dir.entries(File.join(path, 'chef', 'roles')).find_all { |r| r.end_with?(".rb") }
    FileUtils.cd File.join BARCLAMP_PATH, 'roles'
    roles.each do |role|
      knife_role = "knife role from file #{role}"
      system knife_role
      puts "\texecuted: #{knife_role}"
    end
    
    if File.directory File.join '/etc', 'redhat-release'
      system "service httpd reload"
    else
      system "service apache2 reload"
    end
    puts "\trestarted the web server"

  end
end