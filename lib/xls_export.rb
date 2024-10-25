require_dependency 'spreadsheet'
require_dependency 'redmine/i18n'
require 'erb'
require 'uri'
require 'rubygems'
require 'nokogiri'

module XlsExport
  module Redmine
    module Export
      module XLS
        module StripHTML
          def strip_html(str, options)
            if options[:strip_html_tags] == '1'
              document = Nokogiri::HTML.parse(str)
              document.css("br").each { |node| node.replace("\n") }
              document.text
            else
              str
            end
          end
        end

        module Journals
          def get_visible_journals(issue)
            return issue.visible_journals_with_index if (issue.respond_to? :visible_journals_with_index)

            journals = issue.journals.includes(:user, :details).
              references(:user, :details).
              reorder(:created_on, :id).to_a
            journals.each_with_index {|j,i| j.indice = i+1}
            journals.reject!(&:private_notes?) unless User.current.allowed_to?(:view_private_notes, issue.project)
            Journal.preload_journals_details_custom_fields(journals)
            journals.select! {|journal| journal.notes? || journal.visible_details.any?}
            journals.reverse! if User.current.wants_comments_in_reverse_order?
            journals
          end
        end

        class XLS_QueryColumn
          attr_accessor :name, :sortable, :groupable, :default_order
          # Cambiar la inclusión del módulo I18n
          include ::I18n
          include ApplicationHelper

          def initialize(name, options={})
            self.name = name
            self.sortable = options[:sortable]
            self.groupable = options[:groupable] || false
            self.groupable = name.to_s if groupable == true
            self.default_order = options[:default_order]
            @caption_key = options[:caption] || "field_#{name}"
          end

          def caption
            case 
            when @caption_key.is_a?(Symbol)
              ::I18n.t(@caption_key.to_s, default: @caption_key.to_s.humanize)
            when @caption_key.start_with?("field_")
              ::I18n.t(@caption_key, default: name.to_s.humanize)
            else
              ::I18n.t("field_#{@caption_key}", default: @caption_key.to_s.humanize)
            end
          rescue
            name.to_s.humanize
          end

          def sortable?
            !@sortable.nil?
          end

          def sortable
            @sortable.is_a?(Proc) ? @sortable.call : @sortable
          end

          def value(issue)
            issue.send name
          end

          def css_classes
            name
          end
        end

        class XLS_SpentTimeQueryColumn < XLS_QueryColumn
          def caption
            l(:label_spent_time)
          end

          def value(issue)
            issue.spent_hours
          end
        end

        class XLS_JournalQueryColumn < XLS_QueryColumn
          include CustomFieldsHelper
          include IssuesHelper
          include XlsExport::Redmine::Export::XLS::StripHTML
          include XlsExport::Redmine::Export::XLS::Journals
        
          def caption
            l(:label_plugin_xlse_field_journal)
          end
        
          def value(issue, options)
            hist_str = ''
            journals = get_visible_journals(issue) || []
            options ||= {}
        
            journals.each do |journal|
              hist_str << "#{format_time(journal.created_on)} - #{journal.user.name}\n"
              journal.visible_details.each do |detail|
                hist_str << " - #{show_detail(detail, true)}"
                hist_str << "\n" unless detail == journal.visible_details.last
              end
              if journal.notes?
                hist_str << "\n" unless journal.visible_details.empty?
                hist_str << journal.notes.to_s
              end
              hist_str << "\n" unless journal == journals.last
            end
            
            strip_html(hist_str, options)
          end
        end

        class XLS_AttachmentQueryColumn < XLS_QueryColumn
          def caption
            l(:label_plugin_xlse_field_attachment)
          end
        
          def value(issue)
            issue.attachments.to_a.map { |a| a.filename }.join("\n")
          end
        end

        module_function


        def format_datetime(datetime)
          return nil unless datetime
          zone = User.current.time_zone
          zone ? datetime.in_time_zone(zone) : datetime.localtime
        end

        def format_column_value(issue, column, project, options)
          case column.name
            when :done_ratio
              (Float(issue.send(column.name))) / 100
            when :description
              strip_html(issue.description.to_s.gsub("\r", ""), options)
            when :relations
              format_relations(issue)
            when :watcher
              format_watchers(issue, project)
            when :spent_time
              column.value(issue) if User.current.allowed_to?(:view_time_entries, project)
            when :attachments
              format_attachments(column.value(issue))
            when :journal
              column.value(issue, options)
            when :project
              project = issue.send(column.name)
              project
            when :created_on, :updated_on, :closed_on
              datetime = issue.respond_to?(column.name) ? issue.send(column.name) : column.value(issue)
              format_datetime(datetime)
            when :"parent.subject"
              issue.parent&.subject.to_s
            else
              issue.respond_to?(column.name) ? issue.send(column.name) : column.value(issue)
          end
        end

        def l(*args)
          ::I18n.t(*args)
        rescue
          args.first.to_s.humanize
        end


        def show_value_for_xls(value)
          if CustomFieldsHelper.instance_method(:show_value).arity == 1
            show_value(value)
          else
            show_value(value, false)
          end
        end

        def add_date_format(date_formats, tag, format, default)
          date_formats[tag] = (format == nil) ? default : format
        end

        def init_date_formats(options)
          date_formats = {}
          add_date_format(date_formats, :created_on, options[:created_format], l("default_created_format"))
          add_date_format(date_formats, :updated_on, options[:updated_format], l("default_updated_format"))
          add_date_format(date_formats, :start_date, options[:start_date_format],l("default_start_date_format"))
          add_date_format(date_formats, :due_date, options[:due_date_format], l("default_due_date_format"))
          add_date_format(date_formats, :closed_on, options[:closed_date_format], l("default_closed_date_format"))
          date_formats
        end

        def has_in_query?(query, name)
          query.available_columns.each do |c|
            return true if c.name == name
          end
          false
        end

        def has_id?(query)
          has_in_query?(query, :id)
        end

        def has_description?(query)
          has_in_query?(query, :description)
        end

        def has_spent_time?(query)
          has_in_query?(query, :spent_time)
        end

        def use_export_description_setting?(query, options)
          has_description?(query) == false && options[:description] == '1'
        end

        def use_export_spent_time?(query, options)
          has_spent_time?(query) == false && options[:time] == '1'
        end

        def init_row(row, query, first)
          if has_id?(query)
            row.replace []
          else
            row.replace [first]
          end
        end

        def insert_issue_id(row, issue)
          issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
          row << Spreadsheet::Link.new(ERB::Util.url_encode(issue_url), issue.id.to_s)
          format_link = Spreadsheet::Format.new :color => :blue, :underline => :single
          row.set_format(row.size - 1, format_link)
        end

        def create_issue_columns(project, query, options)
          issue_columns = []
          
          (options[:query_columns_only] == '1' ? query.columns : query.available_columns).each do |c|
            case c.name
            when :relations
              issue_columns << c if options[:relations] == '1'
            when :estimated_hours
              issue_columns << XLS_SpentTimeQueryColumn.new(:spent_time) if use_export_spent_time?(query, options)
              issue_columns << c if column_exists_for_project?(c, project)
            else
              issue_columns << c if column_exists_for_project?(c, project)
            end
          end
          
          issue_columns << XLS_QueryColumn.new(:watcher) if options[:watchers] == '1'
          issue_columns << XLS_AttachmentQueryColumn.new(:attachments) if options[:attachments] == '1'
          issue_columns << XLS_JournalQueryColumn.new(:journal) if options[:journal] == '1'
          issue_columns << XLS_QueryColumn.new(:description) if use_export_description_setting?(query, options)
          
          issue_columns
        end

        def init_header_columns(query, sheet1, columns, date_formats)
          columns_width = has_id?(query) ? [] : [1]
          init_row(sheet1.row(0), query, "#")

          columns.each do |c|
            caption = case 
              when c.is_a?(QueryCustomFieldColumn)
                c.custom_field.name
              when c.respond_to?(:caption)
                c.caption.is_a?(Symbol) ? l(c.caption) : c.caption
              else
                l("field_#{c.name}", default: c.name.to_s.humanize)
            end

            sheet1.row(0) << caption.to_s
            columns_width << (get_value_width(caption) * 1.1)
          end

          # Formato base para la columna ID
          sheet1.column(0).default_format = Spreadsheet::Format.new(:number_format => "0")

          # Formato especial para la cabecera
          header_format = Spreadsheet::Format.new(
            weight: :bold,
            pattern: 1,
            pattern_fg_color: :gray,
            pattern_bg_color: :gray,
            color: :white,
            align: :center,
            text_wrap: true
          )

          # Aplicar formato a las cabeceras
          sheet1.row(0).count.times do |i|
            sheet1.row(0).set_format(i, header_format)
          end

          # Formatos específicos para cada columna
          columns.each_with_index do |c, idx|
            format_options = {}
            format_options[:number_format] = case
              when c.is_a?(QueryCustomFieldColumn)
                case c.custom_field.field_format
                when "int" then "0"
                when "float" then "0.00"
                when "date" then date_formats[:start_date]
                end
              when c.name == :done_ratio then "0%"
              when [:estimated_hours, :spent_time].include?(c.name) then "0.0"
              when [:created_on, :updated_on, :start_date, :due_date, :closed_on].include?(c.name)
                date_formats[c.name]
              end
            
            sheet1.column(idx).default_format = Spreadsheet::Format.new(format_options) if format_options[:number_format]
          end
          
          columns_width
        end

        def update_sheet_formatting(sheet1, columns_width)
          sheet1.row(0).count.times do |idx|
            width = columns_width[idx] > 60 ? 60 : columns_width[idx]
            sheet1.column(idx).width = width
            
            if width == 60
              fmt = Marshal::load(Marshal.dump(sheet1.column(idx).default_format))
              fmt.text_wrap = true
              sheet1.column(idx).default_format = fmt
            end
          end
        end

        def get_value_width(value)
          if %w(Time Date).include?(value.class.name)
            return 18 unless value.to_s.length < 18
          end

          tot_w = [Float(0)]
          idx = 0

          value.to_s.each_char do |c|
            case c
            when '1', '.', ';', ':', ',', ' ', 'i', 'I', 'j', 'J', '(', ')', '[', ']', '!', '-', 't', 'l'
              tot_w[idx] += 0.6
            when 'W', 'M', 'D'
              tot_w[idx] += 1.2
            when "\n"
              idx += 1
              tot_w << Float(0)
            else
              tot_w[idx] += 1.05
            end
          end

          tot_w.max || 0 + 1.5
        end

        def column_exists_for_project?(column, project)
          return true unless column.is_a?(QueryCustomFieldColumn) && project

          project.trackers.any? do |t|
            t.custom_fields.any? { |c| c.id == column.custom_field.id }
          end
        end

        def query_get_group_column_name(issue, query)
          gc = query.group_by_column
          return issue.send(query.group_by) unless gc.is_a?(QueryCustomFieldColumn)

          cf = issue.custom_values.detect { |c| c.custom_field_id == gc.custom_field.id }
          cf ? cf.value : l(:label_none)
        end

        def pretty_xls_tab_name(org_name)
          org_name.gsub(/[\\\/\[\]\?\*:"']/, '_')
        end

        def init_status_histories_book
          Spreadsheet.client_encoding = 'UTF-8'
          book = Spreadsheet::Workbook.new
          sheet = book.create_worksheet(name: "Status histories")
          [book, sheet]
        end

        def add_columns_header_for_status_histories(sheet)
          columns_width = []
          sheet.row(0).replace []
          [
            '#',
            l(:field_project),
            l(:plugin_xlse_field_issue_created_on),
            l(:field_updated_on),
            l(:plugin_xlse_field_status_from),
            l(:plugin_xlse_field_status_to)
          ].each do |c|
            sheet.row(0) << c
            columns_width << (get_value_width(c) * 1.1)
          end
          columns_width
        end

        def set_columns_default_format(sheet, options)
          date_formats = init_date_formats(options)
          number_formats = ['0', nil, date_formats[:created_on], date_formats[:updated_on], nil, nil]
          
          number_formats.each_with_index do |number_format, idx|
            next unless number_format
            sheet.column(idx).default_format = Spreadsheet::Format.new(number_format: number_format)
          end
        end

        def hash_issue_statuses
          IssueStatus.all.each_with_object({}) do |status, hash|
            hash[status.id.to_s] = status.name
          end
        end

        def get_issue_status(id, issue_statuses)
          issue_statuses[id] || id
        end

        def extract_status_histories(sheet, columns_width, issues)
          issue_statuses = hash_issue_statuses
          idx = 0

          issues.each do |issue|
            get_visible_journals(issue).each do |journal|
              journal.visible_details.each do |detail|
                next unless detail.prop_key == "status_id"

                row = sheet.row(idx + 1)
                row.replace []

                data = [
                  issue.id,
                  issue.project&.name || issue.project_id.to_s,
                  format_datetime(issue.created_on),
                  format_datetime(journal.created_on),
                  get_issue_status(detail.old_value, issue_statuses),
                  get_issue_status(detail.value, issue_statuses)
                ]

                data.each_with_index do |e, e_idx|
                  lf_pos = get_value_width(e)
                  columns_width[e_idx] = lf_pos if !columns_width[e_idx] || columns_width[e_idx] < lf_pos
                  row << e
                end
                idx += 1
              end
            end
          end
          columns_width
        end

        def status_histories_to_xls(issues, options = {})
          book, sheet = init_status_histories_book
          columns_width = add_columns_header_for_status_histories(sheet)
          set_columns_default_format(sheet, options)
          columns_width = extract_status_histories(sheet, columns_width, issues)
          update_sheet_formatting(sheet, columns_width)

          xls_stream = StringIO.new('')
          book.write(xls_stream)
          xls_stream.string
        end

        def issues_to_xls2(issues, project, query, options = {})
          Spreadsheet.client_encoding = 'UTF-8'
          
          date_formats = init_date_formats(options)
          group_by_query = query.grouped? ? options[:group] : false
          book = Spreadsheet::Workbook.new
          issue_columns = create_issue_columns(project, query, options)
          
          sheet1 = nil
          group = false
          columns_width = []
          idx = 0
          
          issues.each do |issue|
            if group_by_query == '1'
              new_group = query_get_group_column_name(issue, query)
              if new_group != group
                group = new_group
                update_sheet_formatting(sheet1, columns_width) if sheet1
                sheet1 = book.create_worksheet(name: (group.blank? ? l(:label_none) : pretty_xls_tab_name(group.to_s)))
                columns_width = init_header_columns(query, sheet1, issue_columns, date_formats)
                idx = 0
              end
            else
              sheet1 ||= book.create_worksheet(name: l(:label_issue_plural))
              columns_width ||= init_header_columns(query, sheet1, issue_columns, date_formats)
            end
            
            row = sheet1.row(idx + 1)
            init_row(row, query, issue.id)
            
            lf_pos = get_value_width(issue.id)
            columns_width[0] = lf_pos if columns_width[0].nil? || columns_width[0] < lf_pos
            
            last_prj = project
            
            issue_columns.each_with_index do |c, j|
              v = if c.is_a?(QueryCustomFieldColumn)
                    format_custom_field_value(issue, c, options)
                  else
                    format_column_value(issue, c, last_prj, options)
                  end
              
              value = format_value_for_excel(v)
              
              lf_pos = get_value_width(value)
              index = has_id?(query) ? j : j + 1
              columns_width[index] = lf_pos if columns_width[index].nil? || columns_width[index] < lf_pos
              
              if c.name == :id
                insert_issue_id(row, issue)
              else
                row << value
              end
            end
            
            idx += 1
            journal_details_to_xls(issue, options, book) if options[:journal_worksheets]
          end
          
          if sheet1
            update_sheet_formatting(sheet1, columns_width)
          else
            sheet1 = book.create_worksheet(name: 'Issues')
            sheet1.row(0).replace [l(:label_no_data)]
          end
          
          xls_stream = StringIO.new('')
          book.write(xls_stream)
          xls_stream.string
        end

        private

        def format_custom_field_value(issue, column, options)
          value = issue.custom_value_for(column.custom_field)
          case column.custom_field.field_format
            when "int"
              begin
                Integer(value.to_s)
              rescue
                show_value_for_xls(value)
              end
            when "float"
              begin
                Float(value.to_s)
              rescue
                show_value_for_xls(value)
              end
            when "date"
              begin
                Date.parse(value.to_s)
              rescue
                show_value_for_xls(value)
              end
            else
              custom_value = issue.custom_field_values.detect { |v| v.custom_field == column.custom_field }
              show_value_for_xls(custom_value) unless custom_value.nil?
          end
        end

        def format_column_value(issue, column, project, options)
          case column.name
            when :done_ratio
              (Float(issue.send(column.name))) / 100
            when :description
              strip_html(issue.description.to_s.gsub("\r", ""), options)
            when :relations
              format_relations(issue)
            when :watcher
              format_watchers(issue, project)
            when :spent_time
              column.value(issue) if User.current.allowed_to?(:view_time_entries, project)
            when :attachments
              format_attachments(column.value(issue))
            when :journal
              column.value(issue, options)
            when :project
              project = issue.send(column.name)
              project
            when :created_on, :updated_on, :closed_on
              datetime = issue.respond_to?(column.name) ? issue.send(column.name) : column.value(issue)
              localtime(datetime)
            when :"parent.subject"
              issue.parent&.subject.to_s
            else
              issue.respond_to?(column.name) ? issue.send(column.name) : column.value(issue)
          end
        end

        def format_relations(issue)
          relations = issue.relations.select { |r| r.other_issue(issue).visible? }
          relations.map { |relation| 
            "#{l(relation.label_for(issue))} #{relation.other_issue(issue).tracker} ##{relation.other_issue(issue).id}"
          }.join("\n")
        end

        def format_watchers(issue, project)
          if User.current.allowed_to?(:view_issue_watchers, project)
            issue.watcher_users.collect(&:to_s).join("\n")
          end
        end

        def format_attachments(attachments)
          Array(attachments).
            compact.
            select { |a| a.respond_to?(:filename) }.
            map { |a| a.filename }.
            join("\n")
        end

        def format_value_for_excel(v)
          %w(Time Date Fixnum Float Integer String).include?(v.class.name) ? v : v.to_s
        end

# Si hay otros métodos que usan localtime, también hay que actualizarlos
        def journal_details_to_xls(issue, options, book_to_add = nil)
          journals = get_visible_journals(issue)
          return nil if journals.size == 0

          Spreadsheet.client_encoding = 'UTF-8'
          book = book_to_add ? book_to_add : Spreadsheet::Workbook.new
          sheet1 = book.create_worksheet(name: "%05i - Journal" % [issue.id])

          columns_width = []
          sheet1.row(0).replace []
          ['#',l(:field_updated_on),l(:field_user),l(:label_details),l(:field_notes)].each do |c|
            sheet1.row(0) << c
            columns_width << (get_value_width(c)*1.1)
          end
          sheet1.column(0).default_format = Spreadsheet::Format.new(number_format: "0")

          idx = 0
          journals.each do |journal|
            row = sheet1.row(idx+1)
            row.replace []

            details = ''
            journal.visible_details.each do |detail|
              details << "#{show_detail(detail, true)}"
              details << "\n" unless detail == journal.visible_details.last
            end
            details = strip_html(details, options)
            notes = strip_html(journal.notes? ? journal.notes.to_s : '', options)

            [idx+1, format_datetime(journal.created_on), journal.user.name, details, notes].each_with_index do |e,e_idx|
              lf_pos = get_value_width(e)
              columns_width[e_idx] = lf_pos unless columns_width[e_idx] >= lf_pos
              row << e
            end

            idx += 1
          end

          update_sheet_formatting(sheet1,columns_width)

          if book_to_add.nil?
            xls_stream = StringIO.new('')
            book.write(xls_stream)
            xls_stream.string
          end
        end
      end
    end
  end
end