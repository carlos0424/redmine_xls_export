module XlseAssetHelpers
  PLUGIN_NAME = 'redmine_xls_export'.to_sym

  def self.settings
    Setting["plugin_#{PLUGIN_NAME.to_s}"]
  end

  def self.plugin_asset_link(asset_name, options = {})
    plugin_name = options[:plugin] ? options[:plugin] : PLUGIN_NAME
    File.join(Redmine::Utils.relative_url_root, 'plugin_assets', plugin_name.to_s, asset_name)
  end
end
