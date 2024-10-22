require 'redmine'

# Carga el archivo helpers desde la ruta correcta
require File.expand_path('../lib/xlse_asset_helpers', __FILE__)

# Cargar la gema rubyzip
begin
  require 'zip' # La forma actualizada de requerir la gema
rescue LoadError
  Rails.logger.info 'XLS export controller: rubyzip gem not available'
end

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

# Requiere hooks si el archivo existe
require File.expand_path('../config/xls_export_hooks', __FILE__) if File.exist?(File.expand_path('../config/xls_export_hooks', __FILE__))

# Registrando MIME types
Mime::Type.register('application/vnd.ms-excel', :xls, %w(application/vnd.ms-excel)) unless defined?(Mime::XLS)
Mime::Type.register('application/zip', :zip, %w(application/zip)) unless defined?(Mime::ZIP)
