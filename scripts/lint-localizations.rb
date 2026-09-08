#!/usr/bin/env ruby

require "json"

catalog_path = File.expand_path("../Nostur/Localizable.xcstrings", __dir__)
catalog = JSON.parse(File.read(catalog_path))
placeholder = /%(?:\d+\$)?(?:@|lld|ld|d|lf|f|s)/

def normalized_placeholders(text, pattern)
  text.scan(pattern).map { |item| item.sub(/%\d+\$/, "%") }.sort
end

errors = []
warnings = []

catalog.fetch("strings").each do |source, entry|
  next if entry["shouldTranslate"] == false

  %w[es id].each do |language|
    localization = entry.dig("localizations", language)
    unless localization
      errors << "#{language}: missing translation for #{source.inspect}"
      next
    end

    units = []
    visit = lambda do |node|
      next unless node.is_a?(Hash)
      units << node["stringUnit"] if node["stringUnit"].is_a?(Hash)
      node.each_value { |child| visit.call(child) if child.is_a?(Hash) }
    end
    visit.call(localization)

    if units.empty?
      errors << "#{language}: no localized string units for #{source.inspect}"
      next
    end

    units.each do |unit|
      value = unit["value"]
      if value.nil? || value.empty? && !source.empty?
        errors << "#{language}: empty translation for #{source.inspect}"
        next
      end
      if unit["state"] != "translated"
        warnings << "#{language}: translation is marked #{unit["state"].inspect} for #{source.inspect}"
      end

      source_placeholders = normalized_placeholders(source, placeholder)
      value_placeholders = normalized_placeholders(value, placeholder)
      if source_placeholders != value_placeholders
        errors << "#{language}: placeholder mismatch for #{source.inspect}"
      end

      source_links = source.scan(/nostur:[^)\s]+/).map { |link| link.gsub(/%\d+\$/, "%") }
      value_links = value.scan(/nostur:[^)\s]+/).map { |link| link.gsub(/%\d+\$/, "%") }
      if source.include?("nostur:") && source_links != value_links
        errors << "#{language}: changed nostur link in #{source.inspect}"
      end

      unless source.start_with?("Last updated: May 27th, 2023")
        warnings << "es: English-formal address in #{source.inspect}" if language == "es" && value.match?(/\b(?:usted|ustedes)\b/i)
      end
      spanish_literals = %w[Alimentar Hogar Ahorrar Espectáculo Costumbre Reflejos Interpretación Rever Vocero]
      warnings << "es: forbidden machine translation in #{source.inspect}" if language == "es" && spanish_literals.any? { |literal| value.casecmp?(literal) }
      warnings << "es: Following mistranslated as Next in #{source.inspect}" if language == "es" && source.casecmp?("following") && value.match?(/\bsiguiente\b/i)
      warnings << "id: English plural 'relays' in #{source.inspect}" if language == "id" && value.match?(/\brelays\b/i)
      indonesian_literals = ["memberi makan", "rumah", "benang", "membuka peniti", "kebiasaan"]
      warnings << "id: forbidden literal translation in #{source.inspect}" if language == "id" && indonesian_literals.any? { |literal| value.casecmp?(literal) }
    end
  end
end

warnings.each { |warning| warn "warning: #{warning}" }
errors.each { |error| warn "error: #{error}" }

puts "Checked #{catalog.fetch("strings").length} strings: #{errors.length} errors, #{warnings.length} warnings"
commented = catalog.fetch("strings").count { |_source, entry| !entry.fetch("comment", "").empty? }
puts "Translator context: #{commented}/#{catalog.fetch("strings").length} strings have comments"
exit 1 unless errors.empty?
