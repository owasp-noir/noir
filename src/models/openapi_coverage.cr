require "./skipped_files"

# Evidence collected during one scan, before endpoint merging and filtering.
class Noir::OpenAPICoverage
  getter enabled_analyzers = [] of String
  @documents = Set(String).new
  @mutex = Mutex.new

  def select_analyzers(detectors, excluded : Array(String)) : Nil
    @enabled_analyzers = %w[oas2 oas3].select do |tech|
      !excluded.includes?(tech) && detectors.any? { |detector| detector.name == tech }
    end
  end

  def reset_documents : Nil
    @documents.clear
  end

  def record_document(path : String) : Nil
    # OAS2 and OAS3 run concurrently. Overlapping scan roots can also
    # register different spellings of the same document.
    @mutex.synchronize { @documents << File.expand_path(path) }
  end

  def summary(errors : Array(AnalyzerFailure))
    status = if @enabled_analyzers.empty?
               "disabled"
             elsif errors.any? { |e| e.tech == Noir::SkippedFiles::DETECT_SCOPE || @enabled_analyzers.includes?(e.tech) }
               "incomplete"
             elsif @documents.empty?
               "no_documents"
             else
               "available"
             end
    {enabled_analyzers: @enabled_analyzers, documents_read: @documents.size, status: status}
  end
end
