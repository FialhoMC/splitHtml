#!/usr/bin/env ruby

require 'fileutils'

class Section
  attr_accessor :name, :content, :children, :parent, :start_comment, :end_comment, :full_path

  def initialize(name, parent = nil)
    @name = name
    @content = []
    @children = []
    @parent = parent
    @start_comment = nil
    @end_comment = nil
    @full_path = calculate_full_path
  end

  def add_child(child)
    @children << child
    child.parent = self
    child.update_full_path
  end

  def update_full_path
    @full_path = calculate_full_path
    @children.each(&:update_full_path)
  end

  def calculate_full_path
    return @name if @parent.nil? || @parent.name == 'root'
    path = []
    current = self
    while current && current.name != 'root'
      path.unshift(current.name)
      current = current.parent
    end
    path.join('/')
  end

  def partial_name
    "_#{full_path.gsub('/', '_')}.html"
  end

  def partial_reference
    "'partials/#{partial_name}'"
  end

  def full_content
    result = []
    result << @start_comment if @start_comment

    @content.each do |line|
      next if line == @start_comment || line == @end_comment
      if line.strip.empty? && @content.size == 1
        next
      end
      result << line
    end

    if @children.any?
      @children.each do |child|
        result << "    <%= render #{child.partial_reference} %>\n"
      end
    end

    result << @end_comment if @end_comment
    result.join
  end
end

class HTMLPartialExtractor
  def initialize(input_file)
    @input_file = input_file
    @content = File.read(input_file)
    @partials_dir = 'partials'
    @section_counts = Hash.new(0)
  end

  def extract_partials
    FileUtils.mkdir_p(@partials_dir)
    header_content, root = parse_document
    create_partials(root)
    create_new_index(root, header_content)
    print_structure(root)
  end

  private

  def parse_document
    lines = @content.lines
    root = Section.new('root')
    stack = [root]
    current_section = root
    header_content = []
    in_header = true

    lines.each do |line|
      if in_header
        if comment = parse_comment(line)
          if comment[:is_begin] && !line.include?('Product:')
            in_header = false
            new_section = create_section(comment[:name], current_section)
            new_section.start_comment = line
            current_section.add_child(new_section)
            stack.push(new_section)
            current_section = new_section
          else
            header_content << line
          end
        else
          header_content << line
        end
      else
        if comment = parse_comment(line)
          if comment[:is_begin]
            new_section = create_section(comment[:name], current_section)
            new_section.start_comment = line
            current_section.add_child(new_section)
            stack.push(new_section)
            current_section = new_section
          elsif comment[:is_end]
            if stack.last.name.start_with?(normalize_section_name(comment[:name]))
              current_section.end_comment = line
              stack.pop
              current_section = stack.last
            end
          end
        else
          current_section.content << line
        end
      end
    end

    [header_content.join, root]
  end

  def create_section(name, parent)
    base_name = normalize_section_name(name)
    @section_counts[base_name] += 1
    count = @section_counts[base_name]

    # Add a number to the name only if there is more than one section with the same name
    final_name = count > 1 ? "#{base_name}_#{count}" : base_name
    Section.new(final_name, parent)
  end

  def parse_comment(line)
    return nil unless line.include?('<!--') && line.include?('-->')

    comment_text = line[/<!--\s*(.+?)\s*-->/, 1]&.strip
    return nil unless comment_text

    if comment_text.start_with?('begin:')
      name = comment_text.sub('begin:', '').strip
      {name: name, is_begin: true, is_end: false}
    elsif comment_text.start_with?('end:')
      name = comment_text.sub('end:', '').strip
      {name: name, is_begin: false, is_end: true}
    elsif comment_text.start_with?('End of')
      name = comment_text.sub('End of', '').strip
      {name: name, is_begin: false, is_end: true}
    elsif !comment_text.include?('end') && !comment_text.include?('End of')
      {name: comment_text, is_begin: true, is_end: false}
    else
      nil
    end
  end

  def normalize_section_name(name)
    return nil if name.nil?
    name.downcase
        .gsub(/[^a-z0-9]+/, '_')
        .gsub(/^_+|_+$/, '')
  end

  def create_partials(root)
    root.children.each do |section|
      create_partial_recursive(section)
    end
  end

  def create_partial_recursive(section)
    return if section.name.nil? || section.full_content.strip.empty?

    #  Create subfolder if necessary
    ensure_subdirectories(section)

    File.write(File.join(@partials_dir, section.partial_name), section.full_content)
    puts "Criado partial: #{section.partial_name} (Caminho completo: #{section.full_path})"

    section.children.each do |child|
      create_partial_recursive(child)
    end
  end

  def ensure_subdirectories(section)
    return unless section.full_path.include?('/')

    path_parts = section.full_path.split('/')
    current_path = @partials_dir

    path_parts[0...-1].each do |part|
      current_path = File.join(current_path, part)
      FileUtils.mkdir_p(current_path) unless File.directory?(current_path)
    end
  end

  def create_new_index(root, header_content)
    new_index_content = header_content.dup
    new_index_content << "\n" unless new_index_content.end_with?("\n")

    root.children.each do |section|
      new_index_content << "    <%= render #{section.partial_reference} %>\n"
    end

    unless new_index_content.include?("</body>") && new_index_content.include?("</html>")
      new_index_content << "  </body>\n</html>\n"
    end

    File.write('new_index.html', new_index_content)
  end

  def print_structure(root, level = 0)
    root.children.each do |section|
      puts "#{' ' * (level * 2)}- #{section.full_path} -> #{section.partial_name}"
      print_structure(section, level + 1)
    end
  end
end

# Use script
if ARGV.empty?
  puts "Please provide the [index].html file as an argument."
  exit 1
end

extractor = HTMLPartialExtractor.new(ARGV[0])
extractor.extract_partials
