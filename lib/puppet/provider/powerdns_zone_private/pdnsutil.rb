# frozen_string_literal: true

# This file contains a provider for the resource type `powerdns_zone`,
#
require 'tempfile'
require 'fileutils'

Puppet::Type.type(:powerdns_zone_private).provide(
  :pdnsutil,
) do
  desc "A provider for the resource type `powerdns_zone`,
        which manages a zone on powerdns
        using the pdnsutil command."

  commands pdnsutil: 'pdnsutil'

  ZONES_DIR = '/etc/powerdns/puppet-zones'

  def zone_file_path
    "#{ZONES_DIR}/#{resource[:name]}.zone"
  end

  def pdnsutil_options
    options = []
    if resource[:config_name].to_s != ''
      options.insert(0, '--config-name')
      options.insert(1, resource[:config_name])
    end
    if resource[:config_dir].to_s != ''
      options.insert(0, '--config-dir')
      options.insert(1, resource[:config_dir])
    end
    options
  end

  def create
    pdnsutil pdnsutil_options, 'create-zone', resource[:name]
    pdnsutil_set_records('1') if resource[:manage_records]
  end

  def destroy
    pdnsutil pdnsutil_options, 'delete-zone', resource[:name]
  end

  def content=(_content)
    return unless resource[:manage_records]

    # Check if only SOA record changed or if actual DNS records changed
    current_records = extract_non_soa_records(content)
    File.open(zone_file_path + '.current', 'w') do |f|
      f.write(current_records)
    end
    new_records = extract_non_soa_records(_content)
    File.open(zone_file_path + '.new', 'w') do |f|
      f.write(new_records)
    end

    if content.empty? || current_records != new_records
      pdnsutil_set_records(@serial)
      pdnsutil(pdnsutil_options, 'increase-serial', resource[:name])
    end
  end

  def pdnsutil_set_records(serial)
    File.open(zone_file_path, 'w') do |f|
      f.write(resource[:content].gsub(%r{_SERIAL_}, serial))
    end
    pdnsutil(pdnsutil_options, 'load-zone', resource[:name], zone_file_path)
  end

  def find_soa(records)
    records.each_with_index do |r, idx|
      return idx if r.include?('SOA')
    end
    'notfound'
  end

  def extract_non_soa_records(content)
    # Extract all non-SOA records for comparison
    # This is used to detect if actual DNS records changed (vs. just SOA params)
    records = content.split("\n")
    records.reject { |r| r.include?('SOA') || r.strip.empty? }.sort.join("\n")
  end

  def content
    return '' unless resource[:manage_records]

    c = pdnsutil(pdnsutil_options, 'list-zone', resource[:name])
    records = c.split("\n")
    soanr = find_soa(records)
    if soanr == 'notfound'
      @serial = '1'
      return c
    end
    soarec = records[soanr].split
    @serial = soarec[-5]
    soarec[-5] = '_SERIAL_'
    records[soanr] = "#{soarec[0..3].join("\t")}\t#{soarec[4..10].join(' ')}"
    "#{records.sort.join("\n")}\n"
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def exists?
    pdnsutil(pdnsutil_options, 'list-all-zones').split("\n").each do |line|
      return true if line == resource[:name]
    end
    false
  end
end
