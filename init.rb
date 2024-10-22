require 'redmine'

# Cargar las dependencias necesarias de manera más robusta
begin
  require 'spreadsheet' # Asegurarse de que la gema spreadsheet está disponible
  require 'zip' # Para el manejo de archivos ZIP
rescue LoadError => e
  Rails.logger.error "XLS export plugin: #{e.message}"
end

# Cargar los helpers y librerías del plugin
require File.expand_path('../lib/xls_export', __FILE__)
require File.expand_path('../lib/xlse_asset_helpers', __FILE__)
require File.expand_path('../lib/xls_export_hooks', __FILE__)


# Registro del Plugin en Redmine
Redmine::Plugin.register :redmine_xls_export do
  name 'Issues XLS export'
  author 'Vitaly Klimov'
  author_url 'mailto:vitaly.klimov@snowbirdgames.com'
  description 'Export issues to XLS files including journals, descriptions, etc. This plugin requires spreadsheet gem.'
  version '0.2.1.t11'

  # Configuraciones del Plugin
  settings(:partial => 'settings/xls_export_settings',
           :default => {
             'relations' => '1',
             'watchers' => '1',
             'description' => '1',
             'journal' => '0',
             'journal_worksheets' => '0',
             'time' => '0',
             'attachments' => '0',
             'query_columns_only' => '0',
             'group' => '0',
             'generate_name' => '1',
             'strip_html_tags' => '0',
             'export_attached' => '0',
             'separate_journals' => '0',
             'export_status_histories' => '0',
             'issues_limit' => '0',
             'export_name' => 'issues_export',
             'created_format' => "dd.mm.yyyy hh:mm:ss",
             'updated_format' => "dd.mm.yyyy hh:mm:ss",
             'start_date_format' => "dd.mm.yyyy",
             'due_date_format' => "dd.mm.yyyy",
             'closed_date_format' => "dd.mm.yyyy hh:mm:ss"
           })

  requires_redmine version_or_higher: '3.2.0'
end

# Configuración de MIME types usando el nuevo estilo de Rails
unless Mime::Type.lookup_by_extension(:xls)
  Mime::Type.register('application/vnd.ms-excel', :xls, ['application/vnd.ms-excel'])
end

unless Mime::Type.lookup_by_extension(:zip)
  Mime::Type.register('application/zip', :zip, ['application/zip'])
end

# Cargar los assets
Rails.configuration.to_prepare do
  # Asegurarse de que los assets se cargan correctamente
#  require_dependency 'issue'
#  require_dependency 'query'
#  require_dependency 'issue_query'
end